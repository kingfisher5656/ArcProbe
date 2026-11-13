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
    /// Regression: these sheets used to open and close again on the first tap.
    func testSettingsSheetsOpenOnFirstTap() {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); openSettings(app)
        tap("settings.main", app: app)
        tap("main.signIn", app: app)
        let confirm = element("login.confirm", app: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertTrue(confirm.exists, "The login sheet must stay open")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(element("main.signIn", app: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].firstMatch.tap()
        tap("settings.library", app: app)
        tap("library.wiki", app: app)
        let download = app.buttons["Download missing wiki covers"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertTrue(download.exists, "The wiki sheet must stay open")
    }
    func testTrackingStatusAndShortcutGuideAreReachable() {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); openSettings(app)
        XCTAssertTrue(app.staticTexts["Tracker not set up"].waitForExistence(timeout: 5))
        tap("settings.shortcuts", app: app)
        XCTAssertTrue(app.staticTexts["Start Arcaea Tracking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["When Arcaea is closed → Stop Arcaea Tracking"].exists)
    }

    func testSheetStartsDisconnectedWithImportAndSendUnavailable() {
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch()
        openSheet(app)
        XCTAssertTrue(app.buttons["sheet.connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sheet.connect"].isEnabled)
        XCTAssertTrue(app.buttons["sheet.export.open"].exists)
        XCTAssertFalse(app.buttons["sheet.export.open"].isEnabled)
        XCTAssertTrue(app.buttons["sheet.import.open"].exists)
        XCTAssertFalse(app.buttons["sheet.import.open"].isEnabled)
        select("Scores", app: app)
        XCTAssertTrue(app.staticTexts["No saved scores"].waitForExistence(timeout: 5))
    }
    func testDiagnosticsAreReachableAndCopyableInLandscape() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        openSheet(app)
        let diagnostics = app.buttons["sheet.diagnostics.toolbar"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertTrue(diagnostics.isHittable)
        diagnostics.tap()
        let copy = app.buttons["sheet.diagnostics.copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); XCTAssertTrue(copy.isHittable)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Report copied"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sheet.diagnostics.text"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Diagnostics visible and copied in landscape"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func openSheet(_ app: XCUIApplication) {
        openSettings(app)
        tap("settings.sheet", app: app)
    }
    private func openSettings(_ app: XCUIApplication) { tap("openSettings", app: app) }
    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func tap(_ identifier: String, app: XCUIApplication) {
        let target = element(identifier, app: app)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)")
        target.tap()
    }
    private func select(_ name: String, app: XCUIApplication) {
        let button = app.buttons[name].firstMatch
        if button.exists, button.isHittable { button.tap(); return }
        let cell = app.cells[name].firstMatch
        if !cell.isHittable, app.buttons["Toggle sidebar"].exists { app.buttons["Toggle sidebar"].tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        if app.buttons["Hide Sidebar"].exists { app.buttons["Hide Sidebar"].tap() }
    }
}
