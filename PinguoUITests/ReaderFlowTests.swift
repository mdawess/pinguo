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
}
