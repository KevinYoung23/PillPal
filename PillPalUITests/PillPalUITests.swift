//
//  PillPalUITests.swift
//  PillPalUITests
//
//  Created by Yang, Yingkai on 11/02/2026.
//

import XCTest

final class PillPalUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCaptureMarketingScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        sleep(2)
        saveScreenshot(from: app, named: "home")

        let userTab = app.buttons["User"]
        if userTab.waitForExistence(timeout: 5) {
            userTab.tap()
            sleep(1)
            saveScreenshot(from: app, named: "user-center")
        }

        let remindersTab = app.buttons["Reminders"]
        if remindersTab.waitForExistence(timeout: 5) {
            remindersTab.tap()
            sleep(1)
        }

        let addButtonCandidates = app.buttons.matching(
            NSPredicate(format: "label == %@ OR identifier == %@ OR label == %@", "plus", "plus", "+")
        )
        if addButtonCandidates.firstMatch.waitForExistence(timeout: 5) {
            addButtonCandidates.firstMatch.tap()
            sleep(1)
            saveScreenshot(from: app, named: "add-menu")
        }
    }

    private func saveScreenshot(from app: XCUIApplication, named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let outputDir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            return
        }
        let fileURL = URL(fileURLWithPath: outputDir, isDirectory: true)
            .appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try screenshot.pngRepresentation.write(to: fileURL)
        } catch {
            XCTFail("Failed to save screenshot \(name): \(error.localizedDescription)")
        }
    }
}
