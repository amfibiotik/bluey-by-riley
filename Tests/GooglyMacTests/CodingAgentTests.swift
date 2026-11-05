import XCTest
@testable import GooglyMac

final class CodingAgentTests: XCTestCase {
    func testParsesClaudeCodeResult() {
        let json = #"{"type":"result","subtype":"success","is_error":false,"result":"Fixed the bug.","session_id":"abc-123"}"#
        let parsed = CLIAgentController.parse(Data(json.utf8))
        XCTAssertEqual(parsed.text, "Fixed the bug.")
        XCTAssertEqual(parsed.session, "abc-123")
        XCTAssertFalse(parsed.isError)
    }

    func testParsesClaudeCodeArrayForm() {
        let json = #"[{"type":"system","session_id":"s1"},{"type":"result","is_error":true,"result":"Not logged in","session_id":"s1"}]"#
        let parsed = CLIAgentController.parse(Data(json.utf8))
        XCTAssertEqual(parsed.text, "Not logged in")
        XCTAssertTrue(parsed.isError)
    }

    func testParsesGeminiResponseWithNoiseBeforeTheJSON() {
        let output = "Loaded cached credentials.\n" + #"{"response":"Done: added tests.","stats":{}}"#
        let parsed = CLIAgentController.parse(Data(output.utf8))
        XCTAssertEqual(parsed.text, "Done: added tests.")
        XCTAssertFalse(parsed.isError)
    }

    func testParsesGeminiError() {
        let parsed = CLIAgentController.parse(Data(#"{"error":{"message":"Quota exceeded"}}"#.utf8))
        XCTAssertEqual(parsed.text, "Quota exceeded")
        XCTAssertTrue(parsed.isError)
    }

    func testUnparseableOutputGivesNoText() {
        XCTAssertNil(CLIAgentController.parse(Data("plain text".utf8)).text)
    }

    func testClaudeArgumentsCarefulAndFullAccess() {
        let careful = CLIAgentController.arguments(kind: .claude, prompt: "hi", resume: "sid", fullAccess: false)
        XCTAssertEqual(Array(careful.prefix(2)), ["-p", "hi"])
        XCTAssertTrue(careful.contains("acceptEdits"))
        XCTAssertFalse(careful.contains("--dangerously-skip-permissions"))
        XCTAssertEqual(careful.suffix(2), ["--resume", "sid"])
        let full = CLIAgentController.arguments(kind: .claude, prompt: "hi", resume: nil, fullAccess: true)
        XCTAssertTrue(full.contains("--dangerously-skip-permissions"))
        XCTAssertFalse(full.contains("--resume"))
    }

    func testGeminiArguments() {
        XCTAssertEqual(CLIAgentController.arguments(kind: .gemini, prompt: "x", resume: nil, fullAccess: false).suffix(2), ["--approval-mode", "auto_edit"])
        XCTAssertEqual(CLIAgentController.arguments(kind: .gemini, prompt: "x", resume: nil, fullAccess: true).suffix(2), ["--approval-mode", "yolo"])
    }

    func testApiKeysAreRemovedSoSubscriptionLoginIsUsed() {
        setenv("ANTHROPIC_API_KEY", "sk-test", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        XCTAssertNil(CLIAgentController.environment()["ANTHROPIC_API_KEY"])
    }
}
