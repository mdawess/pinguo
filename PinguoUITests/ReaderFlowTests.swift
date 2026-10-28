import XCTest

final class ReaderFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(importing fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-PinguoInMemoryStore"]
        if let fixture {
            app.launchArguments += ["-PinguoImport", stagedFixture(fixture).path]
        }
        app.launch()
        return app
    }

    /// Copies a bundled fixture somewhere the app can read without crossing macOS privacy protections.
    private func stagedFixture(_ name: String) -> URL {
        let source = Bundle(for: Self.self).url(forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension)!
        let destination = FileManager.default.temporaryDirectory.appending(path: name)
        try? FileManager.default.removeItem(at: destination)
        try! FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testImportReadAndLookUpAWord() {
        let app = launch(importing: "weekend.epub")
        let book = app.staticTexts["周末的小山"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        snapshot(app, "library")

        book.tap()
        let word = app.staticTexts["风景"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        snapshot(app, "reader")

        word.tap()
        XCTAssertTrue(app.staticTexts["fēngjǐng"].waitForExistence(timeout: 5))
        snapshot(app, "word-card")

        app.buttons["Reading settings"].tap()
        app.buttons["Always"].tap()
        snapshot(app, "settings")
    }

    func testNarrationHighlightsSentences() {
        let app = launch(importing: "weekend.epub")
        let book = app.staticTexts["周末的小山"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()

        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20))
        sleep(4)
        snapshot(app, "playing")

        app.buttons["Choose a voice"].tap()
        XCTAssertTrue(app.staticTexts["Mainland Mandarin"].waitForExistence(timeout: 10))
        sleep(2)
        snapshot(app, "voice-picker")
    }

    func testLookedUpWordBecomesAReviewCard() {
        let app = launch(importing: "weekend.epub")
        let book = app.staticTexts["周末的小山"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        let word = app.staticTexts["风景"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()
        XCTAssertTrue(app.staticTexts["In review"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Review"].tap()
        let start = app.buttons["Start review"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        snapshot(app, "review-home")
        start.tap()

        XCTAssertTrue(app.buttons["Show answer"].waitForExistence(timeout: 5))
        snapshot(app, "review-front")
        app.buttons["Show answer"].tap()
        XCTAssertTrue(app.staticTexts["fēngjǐng"].waitForExistence(timeout: 5))
        sleep(3)
        snapshot(app, "review-back")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Good'")).firstMatch.tap()
        // Good on a new card schedules a 10 minute learning step, which the session pulls forward.
        XCTAssertTrue(app.staticTexts["1 / 2"].waitForExistence(timeout: 5))
    }

    /// Needs Apple Intelligence on the host Mac for the simulator's on-device model.
    func testConversationReplies() throws {
        let app = launch()
        app.tabBars.buttons["Speak"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ordering coffee'")).firstMatch.tap()
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Apple Intelligence'")).firstMatch
        let opened = app.buttons["Translate"].firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 60) || unavailable.exists)
        try XCTSkipIf(unavailable.exists, "Apple Intelligence is unavailable on this simulator host")
        snapshot(app, "conversation-opening")

        app.buttons["Type instead"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("我要一杯拿铁，热。\n")
        let replies = app.buttons.matching(identifier: "Translate")
        let replied = expectation(for: NSPredicate(format: "count >= 2"), evaluatedWith: replies)
        wait(for: [replied], timeout: 60)
        sleep(1)
        snapshot(app, "conversation-reply")
    }

    /// Needs English speech recognition and the English–Chinese translation pack, which the simulator lacks.
    func testEnglishAudioBecomesBilingualDocument() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["PINGUO_TRANSLATION_AVAILABLE"] == nil, "Translation framework is unavailable in the simulator")
        let app = launch(importing: "standup.m4a")
        let row = app.staticTexts["standup"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let ready = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Translated from English'")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 120))
        row.tap()
        XCTAssertTrue(app.buttons["Open in reader"].waitForExistence(timeout: 10))
        sleep(1)
        snapshot(app, "translated-audio")
    }

    /// Visits the main screens for a visual check (run on iPad and in dark mode).
    func testScreenTour() {
        let app = launch(importing: "weekend.epub")
        let book = app.staticTexts["周末的小山"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        let word = app.staticTexts["城外"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()
        sleep(1)
        snapshot(app, "tour-reader")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
        snapshot(app, "tour-library")
        app.buttons["Progress"].firstMatch.tap()
        sleep(1)
        snapshot(app, "tour-progress")
        app.buttons["Review"].firstMatch.tap()
        sleep(1)
        snapshot(app, "tour-review")
    }
}
