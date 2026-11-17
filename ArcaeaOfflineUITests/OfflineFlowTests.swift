import SQLite3
import XCTest

@MainActor final class OfflineFlowTests: XCTestCase {
    func testManualEntrySurvivesRelaunchAndDeleteCanBeUndone() throws {
        let app = englishApp()
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
        tap("playActions", app: app)
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
        tap("playActions", app: app)
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts.buttons["Delete play"].waitForExistence(timeout: 5))
        sleep(1) // The alert is still animating in while the menu closes; a tap during that is lost.
        app.alerts.buttons["Delete play"].tap()
        XCTAssertTrue(app.buttons["undoChange"].waitForExistence(timeout: 5))
        app.buttons["undoChange"].tap()
        XCTAssertTrue(app.staticTexts["9,850,000"].firstMatch.waitForExistence(timeout: 5))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Offline edited score details"; detail.lifetime = .keepAlways; add(detail)
        select("Best 50", app: app)
        let dashboard = XCTAttachment(screenshot: app.screenshot()); dashboard.name = "Offline Best 50 dashboard"; dashboard.lifetime = .keepAlways; add(dashboard)
        select("Potential", app: app)
        XCTAssertTrue(app.staticTexts["No potential history yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Local · Best 50"].exists)
        XCTAssertTrue(app.staticTexts["Official"].exists)
        XCTAssertTrue(app.staticTexts["Local estimate"].exists)
        let graph = XCTAttachment(screenshot: app.screenshot()); graph.name = "Official history without fabricated past"; graph.lifetime = .keepAlways; add(graph)
    }
    func testInvalidScoreShowsValidationAndDoesNotDismissEditor() {
        let app = englishApp()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); select("Scores", app: app)
        app.buttons["addScore"].tap(); app.buttons["saveScore"].tap()
        XCTAssertTrue(app.staticTexts["validationMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveScore"].exists)
    }
    /// Regression: these sheets used to open and close again on the first tap.
    func testSettingsSheetsOpenOnFirstTap() {
        let app = englishApp()
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
    /// The folder picker itself belongs to iOS; a prepared folder stands in for the user's choice.
    func testGameFolderImportAddsItsScores() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-gamedata-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(folder.appendingPathComponent("Documents/st3").path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, """
            CREATE TABLE scores(id integer primary key autoincrement not null, version int, score int, shinyPerfectCount int, perfectCount int, nearCount int, missCount int, date int, songId text, songDifficulty int, modifier int, health int, ct int default 0);
            CREATE TABLE cleartypes(id integer primary key autoincrement not null, songId text, songDifficulty int, clearType int, ct int default 0);
            INSERT INTO scores(version,score,shinyPerfectCount,perfectCount,nearCount,missCount,date,songId,songDifficulty,modifier,health) VALUES(1,9912345,700,800,5,2,0,'tempestissimo',3,0,100);
            INSERT INTO cleartypes(songId,songDifficulty,clearType) VALUES('tempestissimo',3,1);
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let app = englishApp()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launchEnvironment["ARCAEA_TEST_GAME_FOLDER"] = folder.path
        app.launch(); openSettings(app)
        tap("settings.gamedata", app: app)
        let run = app.buttons["Import 1 score"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.name = "Game folder preview"; preview.lifetime = .keepAlways; add(preview)
        run.tap()
        XCTAssertTrue(app.buttons["Everything is up to date"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Added 1 score."].exists)
        XCTAssertTrue(app.buttons["Remove 1 game-folder score"].exists)
        closeSettings(app)
        select("Scores", app: app)
        XCTAssertTrue(app.staticTexts["9,912,345"].firstMatch.waitForExistence(timeout: 10))
        // The song's pack is offered as a filter, and filtering by it keeps the score.
        tap("scores.pack", app: app)
        let pack = app.buttons["Black Fate (1)"]
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "Pack filter menu"; menu.lifetime = .keepAlways; add(menu)
        pack.tap()
        XCTAssertTrue(app.staticTexts["9,912,345"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 chart best"].exists || app.staticTexts["1 CHART BEST"].exists)
        // Switching a difficulty on that the score does not have empties the list; clearing the filters brings it back.
        app.buttons["PST"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No scores match"].waitForExistence(timeout: 5))
        tap("scores.clearFilters", app: app)
        XCTAssertTrue(app.staticTexts["9,912,345"].firstMatch.waitForExistence(timeout: 5))
    }
    func testTrackingStatusAndShortcutGuideAreReachable() {
        let app = englishApp()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch(); openSettings(app)
        XCTAssertTrue(app.staticTexts["Tracker not set up"].waitForExistence(timeout: 5))
        tap("settings.shortcuts", app: app)
        XCTAssertTrue(app.staticTexts["Start Arcaea Tracking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["When Arcaea is closed → Stop Arcaea Tracking"].exists)
    }

    /// An empty screen offers the way forward itself, and Settings opens at the screen it names.
    func testEmptyStatesOpenTheScreenTheyName() {
        let app = englishApp()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch()
        tap("empty.importOnline", app: app)
        XCTAssertTrue(element("main.signIn", app: app).waitForExistence(timeout: 5))
        closeSettings(app)
        tap("empty.importFolder", app: app)
        XCTAssertTrue(element("gamedata.choose", app: app).waitForExistence(timeout: 5))
        closeSettings(app)
        select("Recent", app: app)
        XCTAssertTrue(app.staticTexts["No tracked plays yet"].waitForExistence(timeout: 5))
        tap("tracking.openShortcuts", app: app)
        XCTAssertTrue(app.staticTexts["Start Arcaea Tracking"].waitForExistence(timeout: 5))
        // The back button leads to the Settings list, as if the screen had been opened from there.
        app.navigationBars.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(element("settings.tracker", app: app).waitForExistence(timeout: 5))
        closeSettings(app)
        select("Scores", app: app)
        tap("empty.addScore", app: app)
        XCTAssertTrue(app.textFields["scoreField"].waitForExistence(timeout: 5))
    }
    func testSheetStartsDisconnectedWithImportAndSendUnavailable() {
        let app = englishApp()
        app.launchEnvironment["ARCAEA_TEST_ARCHIVE"] = UUID().uuidString
        app.launch()
        openSheet(app)
        XCTAssertTrue(app.buttons["sheet.connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sheet.connect"].isEnabled)
        XCTAssertTrue(app.buttons["sheet.export.open"].exists)
        XCTAssertFalse(app.buttons["sheet.export.open"].isEnabled)
        XCTAssertTrue(app.buttons["sheet.import.open"].exists)
        XCTAssertFalse(app.buttons["sheet.import.open"].isEnabled)
        closeSettings(app)
        select("Scores", app: app)
        XCTAssertTrue(app.staticTexts["No saved scores"].waitForExistence(timeout: 5))
    }
    func testDiagnosticsAreReachableAndCopyableInLandscape() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = englishApp()
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

    /// These tests find things by their English text, so the app is started in English
    /// whatever language the simulator is set to.
    private func englishApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }
    private func openSheet(_ app: XCUIApplication) {
        openSettings(app)
        tap("settings.sheet", app: app)
    }
    private func openSettings(_ app: XCUIApplication) { tap("openSettings", app: app) }
    /// Settings is a sheet over the tabs; it has to be closed before a tab can be chosen.
    private func closeSettings(_ app: XCUIApplication) {
        tap("settings.done", app: app)
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 5))
        sleep(1) // the sheet is still sliding away
    }
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
