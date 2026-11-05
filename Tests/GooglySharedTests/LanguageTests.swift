import XCTest
@testable import GooglyShared

final class LanguageTests: XCTestCase {
    private var saved: BlueyLanguage?

    override func setUp() { saved = BlueyLanguage.chosen }
    override func tearDown() { BlueyLanguage.chosen = saved }

    func testChoiceWinsOverSystem() {
        BlueyLanguage.chosen = .ukrainian
        XCTAssertEqual(BlueyLanguage.current, .ukrainian)
        BlueyLanguage.chosen = .english
        XCTAssertEqual(BlueyLanguage.current, .english)
    }

    func testClearingChoiceFollowsSystem() {
        BlueyLanguage.chosen = .ukrainian
        BlueyLanguage.chosen = nil
        XCTAssertNil(BlueyLanguage.chosen)
        XCTAssertEqual(BlueyLanguage.current, BlueyLanguage.system)
    }

    func testTranslationHelperPicksCurrentLanguage() {
        BlueyLanguage.chosen = .english
        XCTAssertEqual(tr("Done", "Готово"), "Done")
        BlueyLanguage.chosen = .ukrainian
        XCTAssertEqual(tr("Done", "Готово"), "Готово")
    }

    func testModelDirectiveAndSpeechCode() {
        XCTAssertEqual(BlueyLanguage.english.modelDirective, "")
        XCTAssertNil(BlueyLanguage.english.speechCode)
        XCTAssertTrue(BlueyLanguage.ukrainian.modelDirective.contains("Ukrainian"))
        XCTAssertEqual(BlueyLanguage.ukrainian.speechCode, "uk")
    }

    func testSessionDetailFollowsLanguage() {
        BlueyLanguage.chosen = .ukrainian
        let session = FocusSession(task: "test", duration: 600)
        XCTAssertTrue(session.detail.contains("Перша перевірка"))
    }
}
