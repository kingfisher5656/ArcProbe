import XCTest

@MainActor final class OfflineFlowTests: XCTestCase {
    func testManualEntrySurvivesRelaunchAndDeleteCanBeUndone() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        print("UI_ARCHIVE_ID:" + app.launchEnvironment["ARCAEA_TEST_ARCHIVE"]!)
        app.launch()
        select("Scores", app: app)
        XCTAssertTrue(app.buttons["addScore"].waitForExistence(timeout: 10))
        app.buttons["addScore"].tap()
        app.buttons["chooseChart"].tap()
        let custom = app.textFields["customSongID"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap(); custom.typeText("offline-uitest")
        app.buttons["useCustomChart"].tap()
        let score = app.textFields["scoreField"]
        score.tap(); score.typeText("9900000")
        app.buttons["saveScore"].tap()
        XCTAssertTrue(app.staticTexts["offline-uitest"].waitForExistence(timeout: 5))
        app.staticTexts["offline-uitest"].firstMatch.tap()
        app.buttons["Edit"].firstMatch.tap()
        let editScore = app.textFields["scoreField"]
        XCTAssertTrue(editScore.waitForExistence(timeout: 5))
        editScore.tap()
        let previous = editScore.value as? String ?? ""
        editScore.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "9850000")
        app.buttons["saveScore"].tap()
        XCTAssertTrue(app.staticTexts["9,850,000"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        select("Scores", app: app)
        XCTAssertTrue(app.staticTexts["offline-uitest"].waitForExistence(timeout: 10))
        app.staticTexts["offline-uitest"].firstMatch.tap()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete play"].tap()
        XCTAssertTrue(app.buttons["undoChange"].waitForExistence(timeout: 5))
        app.buttons["undoChange"].tap()
        XCTAssertTrue(app.staticTexts["9,850,000"].firstMatch.waitForExistence(timeout: 5))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Offline edited score details"; detail.lifetime = .keepAlways; add(detail)
        select("Best 50", app: app)
        let dashboard = XCTAttachment(screenshot: app.screenshot()); dashboard.name = "Offline Best 50 dashboard"; dashboard.lifetime = .keepAlways; add(dashboard)
    }
    func testInvalidScoreShowsValidationAndDoesNotDismissEditor() {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); select("Scores", app: app)
        app.buttons["addScore"].tap(); app.buttons["saveScore"].tap()
        XCTAssertTrue(app.staticTexts["validationMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveScore"].exists)
    }
    private func select(_ name: String, app: XCUIApplication) {
        let button = app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }
}
