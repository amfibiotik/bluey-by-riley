import AppKit
import GooglyShared

/// Which coding assistant Bluey hands jobs to. Codex uses your ChatGPT sign-in; Claude Code and Gemini CLI use
/// the sign-in you already made in their own terminal apps (a Claude or Google subscription: no API key needed).
enum CodingAgentKind: String, CaseIterable {
    case codex, claude, gemini

    private static let key = "coder"

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .gemini: return "Gemini CLI"
        }
    }

    var isInstalled: Bool {
        self == .codex ? CodexController.isInstalled : CLIAgentController.locate(self) != nil
    }

    /// The saved choice; with none, the first assistant that is installed (Codex first, as before).
    static var selected: CodingAgentKind {
        get {
            if let saved = UserDefaults.standard.string(forKey: key).flatMap(CodingAgentKind.init(rawValue:)) { return saved }
            return allCases.first { $0.isInstalled } ?? .codex
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// What the rest of the app needs from a coding assistant. `CodexController` and `CLIAgentController` both fit.
@MainActor
protocol CodingAgent: AnyObject {
    var displayName: String { get }
    var installed: Bool { get }
    var onEvent: ((CodexController.Event) -> Void)? { get set }
    var onChange: (() -> Void)? { get set }
    var jobs: [CodexController.Job] { get }
    var approvals: [CodexController.Approval] { get }
    var pendingSummary: String? { get }

    func warmUp()
    func shutdown()
    func start(project query: String?, prompt: String) -> String
    func followUp(_ hint: String?, message: String) async -> String
    func stop(_ hint: String?) async -> String
    func answer(_ decision: String) -> String
    func status() -> String
    func open(_ hint: String?) -> String
    func open(threadID: String)
    func openApp()
}

extension CodexController: CodingAgent {
    var displayName: String { "Codex" }
    var installed: Bool { CodexController.isInstalled }
    func openApp() { NSWorkspace.shared.open(URL(string: "codex://")!) }
}

/// Runs a job with a command-line assistant (Claude Code or Gemini CLI) in headless mode: one process per job,
/// started in the project's folder, answering with a single JSON result when it finishes.
///
/// Permissions: by default the assistant may read and edit files but is not allowed to run shell commands
/// ("careful"). The menu can switch Claude Code and Gemini CLI to full access (no prompts at all), which is what
/// Codex always uses here.
@MainActor
final class CLIAgentController: CodingAgent {
    let kind: CodingAgentKind
    init(kind: CodingAgentKind) { self.kind = kind }

    var onEvent: ((CodexController.Event) -> Void)?
    var onChange: (() -> Void)?
    private(set) var jobs: [CodexController.Job] = []
    /// These assistants never pause to ask in headless mode, so there is nothing to approve by voice.
    private(set) var approvals: [CodexController.Approval] = []
    var pendingSummary: String? { nil }

    private var processes: [String: Process] = [:]
    /// Claude Code session ids per job, so a follow-up can continue the same conversation.
    private var sessions: [String: String] = [:]
    private var stopped: Set<String> = []

    var displayName: String { kind.title }
    var installed: Bool { Self.locate(kind) != nil }

    func warmUp() {}

    func shutdown() {
        for process in processes.values where process.isRunning { process.terminate() }
    }

    // MARK: Finding and launching the tool

    /// Where the tool is installed (nil when it isn't). Checks the usual places, including nvm-managed Node.
    nonisolated static func locate(_ kind: CodingAgentKind) -> String? {
        guard kind != .codex else { return nil }
        let name = kind == .claude ? "claude" : "gemini"
        return searchDirectories().map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func searchDirectories() -> [String] {
        let home = NSHomeDirectory()
        var dirs = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                    "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            dirs += versions.sorted(by: >).map { "\(nvm)/\($0)/bin" }
        }
        return dirs
    }

    /// API keys are removed so the tools use the subscription sign-in, not a pay-per-token key left in the environment.
    nonisolated static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "GEMINI_API_KEY", "GOOGLE_API_KEY"] { env.removeValue(forKey: key) }
        let path = (searchDirectories() + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        env["PATH"] = path + ":" + (env["PATH"] ?? "")
        return env
    }

    /// The command-line arguments for one headless run.
    nonisolated static func arguments(kind: CodingAgentKind, prompt: String, resume: String?, fullAccess: Bool) -> [String] {
        switch kind {
        case .claude:
            var args = ["-p", prompt, "--output-format", "json"]
            if fullAccess {
                args += ["--dangerously-skip-permissions"]
            } else {
                args += ["--permission-mode", "acceptEdits", "--allowedTools", "Read,Edit,Write,Glob,Grep,WebFetch,WebSearch"]
            }
            if let resume { args += ["--resume", resume] }
            return args
        case .gemini:
            return ["-p", prompt, "--output-format", "json", "--approval-mode", fullAccess ? "yolo" : "auto_edit"]
        case .codex:
            return []
        }
    }

    /// Reads the tool's JSON result: Claude Code gives `result`/`session_id`/`is_error`, Gemini CLI `response`/`error`.
    /// Tolerates text printed before the JSON and the array form some Claude Code versions print.
    nonisolated static func parse(_ data: Data) -> (text: String?, session: String?, isError: Bool) {
        var body = data
        if let brace = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) { body = data[brace...] }
        var object: [String: Any]?
        if let parsed = try? JSONSerialization.jsonObject(with: body) {
            if let dict = parsed as? [String: Any] { object = dict }
            else if let array = parsed as? [[String: Any]] { object = array.last { $0["type"] as? String == "result" } ?? array.last }
        }
        guard let object else { return (nil, nil, false) }
        let text = (object["result"] as? String) ?? (object["response"] as? String)
        let errorText = (object["error"] as? [String: Any])?["message"] as? String
        let isError = (object["is_error"] as? Bool) == true || errorText != nil
        return (text ?? errorText, object["session_id"] as? String, isError)
    }

    // MARK: Jobs (what his tools call)

    private var notInstalled: String {
        switch kind {
        case .claude: return tr("Claude Code isn't installed on this Mac. Install it and sign in once by running `claude` in Terminal.",
                                "Claude Code не встановлено на цьому Mac. Встанови його й один раз увійди, запустивши `claude` у Терміналі.")
        default: return tr("Gemini CLI isn't installed on this Mac. Install it and sign in once by running `gemini` in Terminal.",
                           "Gemini CLI не встановлено на цьому Mac. Встанови його й один раз увійди, запустивши `gemini` у Терміналі.")
        }
    }

    func start(project query: String?, prompt: String) -> String {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return "What should \(displayName) do?" }
        guard installed else { return notInstalled }
        let folder: URL
        var name = "Bluey"
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            switch CodexProjects.resolve(query) {
            case .one(let project):
                folder = URL(fileURLWithPath: project.path)
                name = project.name
            case .many(let names):
                return "Several projects match \"\(query)\": \(names.prefix(6).joined(separator: ", ")). Ask the user which one in one short line."
            case .none:
                return "No project called \"\(query)\". Projects: \(CodexProjects.all().map(\.name).prefix(20).joined(separator: ", ")). Ask which one, or leave the project out to work in the Bluey folder."
            }
        } else {
            do { folder = try CodexProjects.blueyFolder(register: false) }
            catch { return "Couldn't prepare the Bluey folder: \(error.localizedDescription)" }
        }
        let job = CodexController.Job(threadID: UUID().uuidString, project: name, folder: folder.path, prompt: prompt)
        jobs.append(job)
        run(jobID: job.threadID, prompt: prompt, folder: folder, resume: nil)
        return "\(displayName) is on it (\(name)). It'll ping you when it's done."
    }

    /// Asks for a short closing summary, in the user's language, because that summary is what Bluey reports.
    private static func withSummaryRequest(_ prompt: String) -> String {
        let ask = BlueyLanguage.current.isUkrainian
            ? "Наприкінці коротко (2–4 речення) поясни українською, що ти зробив."
            : "When you finish, end with a short plain summary (2–4 sentences) of what you did."
        return prompt + "\n\n" + ask
    }

    private func run(jobID: String, prompt: String, folder: URL, resume: String?) {
        guard let path = Self.locate(kind), let i = jobs.lastIndex(where: { $0.threadID == jobID }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = Self.arguments(kind: kind, prompt: Self.withSummaryRequest(prompt), resume: resume,
                                           fullAccess: Settings.shared.coderFullAccess)
        process.currentDirectoryURL = folder
        process.environment = Self.environment()
        let out = Pipe(), err = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            jobs[i].status = "failed"
            onChange?()
            onEvent?(.finished(note: "\(displayName) couldn't start the job (\"\(CodexController.short(prompt, 120))\"): \(error.localizedDescription)",
                               line: "\(displayName) wouldn't start: \(CodexController.short(error.localizedDescription, 80))"))
            return
        }
        processes[jobID] = process
        jobs[i].status = "working"
        onChange?()
        // Read both pipes while the tool runs, so a long answer can never fill a pipe and stall it.
        Task.detached(priority: .utility) { [weak self] in
            let errTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = await errTask.value
            process.waitUntilExit()
            let code = process.terminationStatus
            await self?.finished(jobID: jobID, output: data, errors: errData, exitCode: code)
        }
    }

    private func finished(jobID: String, output: Data, errors: Data, exitCode: Int32) {
        processes[jobID] = nil
        guard let i = jobs.lastIndex(where: { $0.threadID == jobID }) else { return }
        if stopped.remove(jobID) != nil {
            jobs[i].status = "stopped"
            onChange?()
            return
        }
        let parsed = Self.parse(output)
        if let session = parsed.session { sessions[jobID] = session }
        let plain = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = parsed.text ?? plain
        let job = jobs[i]
        if exitCode == 0 && !parsed.isError {
            jobs[i].status = "done"
            jobs[i].lastMessage = text
            onEvent?(.finished(
                note: "\(displayName) finished in \(job.project) (job: \"\(CodexController.short(job.prompt, 160))\"). \(displayName)'s own summary: \(CodexController.short(text.isEmpty ? "(no summary)" : text, 900))",
                line: "\(displayName) is done in \(job.project)."))
        } else {
            jobs[i].status = "failed"
            let stderr = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let why = CodexController.short(parsed.isError || !text.isEmpty ? text : (stderr.isEmpty ? "exit code \(exitCode)" : stderr))
            onEvent?(.finished(
                note: "\(displayName) hit a problem in \(job.project) (job: \"\(CodexController.short(job.prompt, 160))\"). Error: \(why). If this looks like a sign-in problem, the user should run the tool once in Terminal to sign in.",
                line: "\(displayName) tripped over something in \(job.project). Have a look?"))
        }
        onChange?()
    }

    /// Finds a job by project name or words from its prompt; the newest one if no hint.
    private func job(_ hint: String?) -> Int? {
        let hint = hint?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard !hint.isEmpty else { return jobs.indices.last }
        let key = CodexProjects.key(hint)
        return jobs.lastIndex { CodexProjects.key($0.project).contains(key) || key.contains(CodexProjects.key($0.project)) }
            ?? jobs.lastIndex { $0.prompt.lowercased().contains(hint) }
            ?? jobs.indices.last
    }

    func followUp(_ hint: String?, message: String) async -> String {
        guard let i = job(hint) else { return "There's no \(displayName) job yet. Start one with codex_start." }
        let job = jobs[i]
        guard processes[job.threadID] == nil else {
            return "\(displayName) is still working in \(job.project) and can't take new instructions mid-run. Wait for it to finish, or stop it first."
        }
        var prompt = message
        var resume: String?
        if kind == .claude, let session = sessions[job.threadID] {
            resume = session
        } else {
            prompt = "Earlier job: \(job.prompt)\nWhat was reported back: \(job.lastMessage ?? "(nothing)")\n\nFollow-up from the user: \(message)"
        }
        run(jobID: job.threadID, prompt: prompt, folder: URL(fileURLWithPath: job.folder), resume: resume)
        return "Sent the follow-up to \(displayName) in \(job.project)."
    }

    func stop(_ hint: String?) async -> String {
        guard let i = job(hint) else { return "No \(displayName) job to stop." }
        let job = jobs[i]
        guard let process = processes[job.threadID], process.isRunning else {
            return "\(displayName) isn't working on anything in \(job.project) right now."
        }
        stopped.insert(job.threadID)
        process.terminate()
        return "Stopped \(displayName) in \(job.project)."
    }

    func answer(_ decision: String) -> String {
        "\(displayName) never waits for approval here: it either has permission already or the action is refused."
    }

    func status() -> String {
        var lines: [String] = []
        for job in jobs.suffix(6).reversed() {
            let mins = Int(Date().timeIntervalSince(job.started) / 60)
            var line = "\(job.project): \(job.status), started \(mins) min ago, job \"\(CodexController.short(job.prompt, 100))\""
            if let last = job.lastMessage { line += ". Latest from \(displayName): \(CodexController.short(last, 300))" }
            lines.append(line)
        }
        return lines.isEmpty ? "No \(displayName) jobs yet." : lines.joined(separator: "\n")
    }

    func open(_ hint: String?) -> String {
        guard let i = job(hint) else {
            openApp()
            return "Opened the Bluey folder."
        }
        open(threadID: jobs[i].threadID)
        return "Opened the \(jobs[i].project) folder in Finder."
    }

    func open(threadID: String) {
        guard let job = jobs.last(where: { $0.threadID == threadID }) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: job.folder))
    }

    func openApp() {
        if let folder = try? CodexProjects.blueyFolder(register: false) { NSWorkspace.shared.open(folder) }
    }
}
