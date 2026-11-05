import SwiftUI

struct FocusFaceHUD: View {
    @ObservedObject var focus: FocusClient
    @ObservedObject var link: MacLink
    @ObservedObject var live: LiveVoice
    var open: () -> Void
    var pair: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(focus.current.flatMap { $0.status == .ended ? nil : $0.task } ?? tr("What's the mission?", "Яка сьогодні місія?"))
                        .font(.fredoka(22)).lineLimit(2)
                    Text(status).font(.plexMono(10)).foregroundStyle(.white.opacity(0.65))
                    if focus.developerMode {
                        Text(tr("Developer Mode · 4× clock · checks every 10s", "Режим розробника · годинник ×4 · перевірка кожні 10 с"))
                            .font(.plexMono(10)).foregroundStyle(.white.opacity(0.8))
                    }
                    if !feedback.isEmpty {
                        Text(feedback).font(.plexSans(12)).lineLimit(2).foregroundStyle(.white.opacity(0.85))
                    }
                    if live.state == .asking {
                        Capsule().fill(Color.white).frame(width: 20 + live.inputLevel * 100, height: 3)
                    }
                }.frame(maxWidth: 360, alignment: .leading)
                Spacer()
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                HStack(spacing: 2) {
                    if !link.connected {
                        icon("qrcode.viewfinder", label: tr("Pair Mac", "Підключити Mac"), action: pair)
                    } else if let session = focus.current, session.status != .ended {
                        icon(session.status == .running ? "pause.fill" : "play.fill",
                             label: session.status == .running ? tr("Pause focus", "Пауза фокусу") : tr("Resume focus", "Продовжити фокус")) {
                            focus.command(session.status == .running ? "focusPause" : "focusResume")
                        }.disabled(!focus.fresh)
                        icon("stop.fill", label: tr("End focus", "Завершити фокус")) { focus.command("focusEnd") }
                            .disabled(!focus.fresh)
                    }
                    icon("scope", label: tr("Focus sessions", "Сесії фокусу"), action: open)
                    Image(systemName: voiceIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(live.state == .asleep ? .white.opacity(0.35) : .white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                        .padding(5)
                        .accessibilityLabel(voiceStatus)
                }
                Spacer(minLength: 24)
                Text(FocusSession.clock(countdown))
                    .font(.system(size: 76, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel(tr("Time remaining", "Залишилось часу"))
                    .accessibilityValue(FocusSession.clock(countdown))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 18)
    }
    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.09)))
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
    private var countdown: Double {
        focus.current.flatMap { $0.status == .ended ? nil : $0.remaining } ?? 1800
    }
    private var feedback: String { focus.nudgeText.isEmpty ? live.feedback : focus.nudgeText }
    private var voiceIcon: String {
        switch live.state {
        case .asleep: return "mic.slash"
        case .waking: return "arrow.triangle.2.circlepath"
        case .listening: return "ear"
        case .asking: return "mic.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "bubble.left.fill"
        }
    }
    private var voiceStatus: String {
        switch live.state {
        case .asleep: return tr("Hold Bluey to speak", "Потримай Bluey, щоб говорити")
        case .waking: return tr("Voice connecting", "Підключаю голос")
        case .listening: return tr("Listening. Hold Bluey to ask", "Слухаю. Потримай Bluey, щоб запитати")
        case .asking: return tr("Recording your request", "Записую твій запит")
        case .thinking: return tr("Thinking", "Думаю")
        case .speaking: return tr("Replying", "Відповідаю")
        }
    }
    private var status: String {
        guard link.connected else { return tr("Pair your Mac to focus together", "Підключи Mac, щоб фокусуватись разом") }
        guard let session = focus.current, session.status != .ended else { return tr("Hold Bluey and describe a task", "Потримай Bluey і опиши завдання") }
        guard focus.fresh else { return tr("Connection lost · monitoring will pause", "Зв'язок втрачено · стеження призупиниться") }
        if session.status == .paused { return tr("Paused", "Пауза") }
        guard let check = session.checks.last(where: { $0.activity != .paused }) else { return tr("Focusing together", "Фокусуємось разом") }
        switch check.activity {
        case .offTask: return tr("Off task · \(check.probability.focusPercent) estimate\(check.nudged ? " · nudged" : "")", "Відволікання · оцінка \(check.probability.focusPercent)\(check.nudged ? " · нагадав" : "")")
        case .onTask: return tr("On task", "За справою")
        case .uncertain: return tr("Not sure yet · checking again", "Ще не певен · перевіряю знову")
        default: return tr("Last check unavailable · trying again", "Остання перевірка недоступна · пробую знову")
        }
    }
}

struct FocusDashboard: View {
    @ObservedObject var focus: FocusClient
    @ObservedObject var link: MacLink
    @Environment(\.dismiss) private var dismiss
    @State private var task = ""
    @State private var minutes = 30.0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(tr("Developer Mode", "Режим розробника"), isOn: Binding(
                            get: { focus.developerMode },
                            set: { focus.command("focusDeveloperMode", developerMode: $0) }
                        )).disabled(!link.connected || !focus.fresh)
                            .accessibilityIdentifier("focusDeveloperMode")
                        Text(tr("4× clock and a screen check every 10 real seconds. Repeated off-task checks nudge after about 20–30 real seconds, plus request time. Applies immediately; test sessions are labelled in history.", "Годинник ×4 і перевірка екрана кожні 10 справжніх секунд. Повторні відволікання викликають нагадування приблизно за 20–30 справжніх секунд плюс час запиту. Діє одразу; тестові сесії позначені в історії."))
                            .font(.plexSans(12)).foregroundStyle(.secondary)
                        if focus.developerMode {
                            Button(tr("Test a nudge", "Перевірити нагадування")) { focus.command("focusTestNudge") }
                                .buttonStyle(.bordered).disabled(!link.connected || !focus.fresh)
                        }
                    }
                    if let finished = focus.current, finished.status == .ended {
                        Text("Lovely bit of focus.").font(.fredoka(26))
                        FocusSummary(session: finished)
                            .padding(16).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let session = focus.current, session.status != .ended {
                        FocusSummary(session: session)
                        Text(focus.fresh ? session.detail : tr("Connection lost. Reconnect before resuming.", "Зв'язок втрачено. Підключись знову, перш ніж продовжувати."))
                            .font(.plexSans(13)).foregroundStyle(.secondary)
                        HStack {
                            Button(session.status == .running ? tr("Pause", "Пауза") : tr("Resume", "Продовжити")) {
                                focus.command(session.status == .running ? "focusPause" : "focusResume")
                            }
                            Button(tr("End focus", "Завершити фокус")) { focus.command("focusEnd") }
                        }.buttonStyle(.bordered).disabled(!link.connected || !focus.fresh)
                    } else {
                        Text("A little company. A little focus.").font(.fredoka(26))
                        Text("Hold Bluey and say what you're working on, or type it here.").font(.plexSans(14))
                        TextField(tr("What are we working on?", "Над чим працюємо?"), text: $task).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("focusTask")
                        Stepper(tr("\(Int(minutes)) minutes", "\(Int(minutes)) хв"), value: $minutes, in: 1...240, step: 5)
                        Button(tr("Start focus", "Почати фокус")) { focus.command("focusStart", task: task, minutes: minutes) }
                            .buttonStyle(.borderedProminent).disabled(task.trimmingCharacters(in: .whitespaces).isEmpty || !link.connected)
                            .accessibilityIdentifier("startFocus")
                    }
                    if !focus.message.isEmpty { Text(focus.message).font(.plexSans(13)).foregroundStyle(.secondary) }
                    Text(tr("While focusing, Bluey sends your main Mac display, task, elapsed time, idle duration and recent check results to OpenAI every \(focus.developerMode ? 10 : 30) real seconds. Brief detours are fine. Stillness isn't distraction.", "Під час фокусу Bluey кожні \(focus.developerMode ? 10 : 30) справжніх секунд надсилає в OpenAI головний екран Mac, завдання, витрачений час, тривалість бездіяльності та останні результати перевірок. Короткі відволікання — це нормально. Нерухомість — не відволікання."))
                        .font(.plexSans(13)).foregroundStyle(.secondary)
                    Text(tr("Screen Recording is required on Mac; microphone is needed for voice. Screenshots aren't saved by Bluey. Pause, end, lock, sleep or disconnect stops capture. Resume is always manual. OpenAI processing follows your API account's data controls.", "На Mac потрібен дозвіл на запис екрана; для голосу потрібен мікрофон. Bluey не зберігає знімки екрана. Пауза, завершення, блокування, сон або розрив зв'язку зупиняють захоплення. Продовження завжди ручне. Обробка в OpenAI підпорядковується налаштуванням даних твого API-акаунта."))
                        .font(.plexSans(13)).foregroundStyle(.secondary)
                    Divider()
                    Text("Your focus sessions").font(.fredoka(23))
                    if focus.history.isEmpty { Text(tr("Your first timeline will appear here when you finish.", "Твоя перша стрічка з'явиться тут, коли ти завершиш сесію.")).foregroundStyle(.secondary) }
                    ForEach(focus.history) { session in
                        FocusSummary(session: session)
                            .padding(16).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(24)
            }.background(Color.black).navigationTitle(tr("bluey · focus friend", "bluey · друг для фокусу"))
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("Back to Bluey", "Назад до Bluey")) { dismiss() } } }
        }.preferredColorScheme(.dark).tint(Color(hex: Palette.berry2))
    }
}

private struct FocusSummary: View {
    let session: FocusSession
    private struct Inspection: Identifiable { let id: String }
    @State private var inspection: Inspection?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.task).font(.fredoka(22))
            if session.usedDeveloperMode == true {
                Text(tr("Developer test · \(FocusSession.clock(session.realActiveElapsed)) real active time · timeline uses focus-clock time", "Тест розробника · \(FocusSession.clock(session.realActiveElapsed)) справжнього активного часу · стрічка використовує годинник фокусу"))
                    .font(.plexMono(11)).foregroundStyle(.secondary)
            }
            Text(tr("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(FocusSession.clock(session.elapsed)) active", "\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · активно \(FocusSession.clock(session.elapsed))"))
                .font(.plexMono(11)).foregroundStyle(.secondary)
            Button { inspect("all") } label: {
                FocusTimeline(session: session).frame(height: 40)
            }.buttonStyle(.plain).accessibilityLabel(tr("Inspect focus checks", "Переглянути перевірки фокусу"))
            HStack(spacing: 16) {
                legend(tr("On task", "За справою"), .green, category: "on_task")
                legend(tr("Off task", "Відволікання"), Color(hex: 0xEBAC73), category: "off_task")
                legend(tr("Unknown", "Невідомо"), .gray, category: "uncertain")
            }.font(.plexSans(11))
            Text(tr("Tap a category to see probabilities and confidence. Grey also includes unchecked time. Pauses are excluded.", "Торкнись категорії, щоб побачити ймовірності й упевненість. Сірий колір також охоплює неперевірений час. Паузи не враховано."))
                .font(.plexSans(11)).foregroundStyle(.secondary)
        }
        .sheet(item: $inspection) { selection in FocusCheckList(session: session, category: selection.id) }
    }
    private func inspect(_ category: String) {
        inspection = Inspection(id: category)
    }
    private func legend(_ name: String, _ color: Color, category: String) -> some View {
        Button { inspect(category) } label: {
            HStack(spacing: 5) { Rectangle().fill(color).frame(width: 9, height: 9); Text(name) }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(tr("Inspect \(name) confidence", "Переглянути упевненість: \(name)"))
    }
}

private struct FocusCheckList: View {
    let session: FocusSession
    @State var category: String
    @Environment(\.dismiss) private var dismiss
    private var checks: [FocusCheck] {
        session.checks.reversed().filter {
            if $0.activity == .paused { return false }
            if category == "all" { return true }
            if category == "uncertain" { return [.uncertain, .unavailable].contains($0.activity) }
            return $0.activity.rawValue == category
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(tr("Show checks", "Показати перевірки"), selection: $category) {
                        Text(tr("All", "Усі")).tag("all")
                        Text(tr("On task", "За справою")).tag("on_task")
                        Text(tr("Off task", "Відволікання")).tag("off_task")
                        Text(tr("Unknown", "Невідомо")).tag("uncertain")
                    }.pickerStyle(.segmented)
                    Text(tr("Each check is a periodic observation. Developer Mode checks every 10 real seconds with a 4× clock. Category probabilities and overall decision confidence are separate model estimates, not guarantees.", "Кожна перевірка — це періодичне спостереження. У режимі розробника перевірки йдуть кожні 10 справжніх секунд при годиннику ×4. Ймовірності категорій і загальна впевненість рішення — це окремі оцінки моделі, а не гарантії."))
                        .font(.plexSans(13)).foregroundStyle(.secondary)
                }
                Section(tr("Latest checks first", "Спочатку найновіші перевірки")) {
                    if checks.isEmpty {
                        Text(tr("No checks recorded in this category yet. Unchecked time has no confidence estimate.", "У цій категорії ще немає перевірок. Для неперевіреного часу немає оцінки впевненості."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(checks) { check in
                        NavigationLink {
                            FocusCheckDetail(check: check)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(check.activity.focusName).font(.fredoka(20))
                                    Spacer()
                                    Text(FocusSession.clock(check.elapsed)).font(.plexMono(12))
                                }
                                if let estimate = check.estimate(for: check.activity) {
                                    Text(tr("Category probability \(estimate.focusPercent) · confidence \(check.confidence.focusPercent)", "Ймовірність категорії \(estimate.focusPercent) · упевненість \(check.confidence.focusPercent)"))
                                        .font(.plexSans(12)).foregroundStyle(.secondary)
                                } else if check.activity == .unavailable {
                                    Text(tr("Check unavailable or stale · no valid estimate", "Перевірка недоступна або застаріла · немає дійсної оцінки"))
                                        .font(.plexSans(12)).foregroundStyle(.secondary)
                                } else {
                                    Text(tr("Category probability not saved · confidence \(check.confidence.focusPercent)", "Ймовірність категорії не збережено · упевненість \(check.confidence.focusPercent)"))
                                        .font(.plexSans(12)).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }.navigationTitle(tr("Focus checks", "Перевірки фокусу"))
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("Done", "Готово")) { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private struct FocusCheckDetail: View {
    let check: FocusCheck
    var body: some View {
        List {
            Section {
                LabeledContent(tr("Observation", "Спостереження"), value: check.activity.focusName)
                LabeledContent(tr("Active session time", "Активний час сесії"), value: FocusSession.clock(check.elapsed))
            }
            if check.activity == .unavailable {
                Text(tr("This check failed or arrived too late. It has no valid confidence estimate and does not count toward a nudge.", "Ця перевірка не вдалася або прийшла запізно. Вона не має дійсної оцінки впевненості й не враховується для нагадування."))
            } else {
                Section(tr("Category probabilities", "Ймовірності категорій")) {
                    ForEach([FocusActivity.onTask, .offTask, .uncertain], id: \.rawValue) { category in
                        LabeledContent(category.focusName, value: check.estimate(for: category)?.focusPercent ?? tr("Not saved", "Не збережено"))
                    }
                }
                Section(tr("Decision confidence", "Упевненість рішення")) {
                    LabeledContent(tr("Overall confidence", "Загальна впевненість"), value: check.confidence.focusPercent)
                    Text(tr("Confidence is reported separately by the API. It is not the probability of a particular category.", "Упевненість повертається API окремо. Це не ймовірність конкретної категорії."))
                        .font(.plexSans(13)).foregroundStyle(.secondary)
                }
                if check.probabilities == nil {
                    Text(tr("This older check saved only the Off task probability and overall confidence. The other probabilities weren't saved.", "Ця старіша перевірка зберегла лише ймовірність відволікання й загальну впевненість. Інші ймовірності не збережено."))
                        .foregroundStyle(.secondary)
                }
                if check.nudged { Label(tr("Bluey gave a gentle nudge after this check", "Після цієї перевірки Bluey м'яко нагадав"), systemImage: "bubble.left") }
            }
        }.navigationTitle(tr("Check details", "Деталі перевірки"))
    }
}

private extension FocusActivity {
    var focusName: String {
        switch self {
        case .onTask: return tr("On task", "За справою")
        case .offTask: return tr("Off task", "Відволікання")
        case .uncertain: return tr("Unknown", "Невідомо")
        case .unavailable: return tr("Unavailable", "Недоступно")
        case .paused: return tr("Paused", "Пауза")
        }
    }
}

private extension Double {
    var focusPercent: String { formatted(.percent.precision(.fractionLength(0...1))) }
}

struct FocusTimeline: View {
    let session: FocusSession
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.gray.opacity(0.35)))
            let total = max(1, session.status == .ended ? session.elapsed : session.duration)
            for check in session.checks where [.onTask, .offTask].contains(check.activity) {
                let span = check.sampleDuration ?? 30
                let start = max(0, check.elapsed - span)
                let rect = CGRect(x: start / total * size.width, y: 0,
                                  width: min(span, check.elapsed) / total * size.width, height: size.height)
                context.fill(Path(rect), with: .color(check.activity == .onTask ? .green : Color(hex: 0xEBAC73)))
            }
        }.overlay(Rectangle().stroke(.white.opacity(0.3), lineWidth: 1))
            .accessibilityLabel(tr("Focus timeline: green on task, peach off task, grey unknown", "Стрічка фокусу: зелений — за справою, персиковий — відволікання, сірий — невідомо"))
    }
}
