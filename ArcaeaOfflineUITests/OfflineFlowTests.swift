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
        select("Potential", app: app)
        XCTAssertTrue(app.staticTexts["No history in this range"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Local · Best 50"].exists)
        XCTAssertTrue(app.staticTexts["Official"].exists)
        XCTAssertTrue(app.staticTexts["Local estimate"].exists)
        let graph = XCTAttachment(screenshot: app.screenshot()); graph.name = "Official history without fabricated past"; graph.lifetime = .keepAlways; add(graph)
    }
    func testInvalidScoreShowsValidationAndDoesNotDismissEditor() {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); select("Scores", app: app)
        app.buttons["addScore"].tap(); app.buttons["saveScore"].tap()
        XCTAssertTrue(app.staticTexts["validationMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveScore"].exists)
    }
    func testMinimumIntervalSettingPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); select("Settings", app: app)
        let toggle = app.switches["minimumFetchInterval"].firstMatch
        for _ in 0..<5 {
            if toggle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.terminate(); app.launch(); select("Settings", app: app)
        for _ in 0..<5 {
            if toggle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    private func select(_ name: String, app: XCUIApplication) {
        // Sidebar destinations are cells, unlike the compact tab bar's buttons.
        if name == "Settings" {
            let cell = app.cells[name].firstMatch
            if !cell.exists, app.buttons["Toggle sidebar"].exists {
                app.buttons["Toggle sidebar"].tap()
            }
            XCTAssertTrue(cell.waitForExistence(timeout: 10))
            cell.tap()
            if app.buttons["Hide Sidebar"].exists { app.buttons["Hide Sidebar"].tap() }
            return
        }
        let button = app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }
}
