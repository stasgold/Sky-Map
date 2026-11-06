/*
 * Copyright (c) 2026 Penterakt LLC and contributors.
 * Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import XCTest

/// Captures App Store screenshots by driving the real app through its real screens. This
/// target is a UI test bundle: it is never compiled into the app, and the app has no special
/// screenshot mode. Run by `.github/workflows/screenshots.yml`.
final class AppStoreScreenshots: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        // If the location prompt appears anyway, allow it.
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        app.tap()
        sleep(5) // let location, the catalog and the first frames settle
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ label: String, timeout: TimeInterval = 5) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "no button \(label)")
        button.tap()
    }

    func testCaptureAppStoreScreens() {
        shot("01-sky")

        // Search, then the info card for a planet.
        tap("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Jupiter")
        sleep(1)
        shot("03-search")
        let firstResult = app.cells.firstMatch
        if firstResult.waitForExistence(timeout: 5) {
            firstResult.swipeLeft()
            tap("Info")
            sleep(3)
            shot("02-info-card")
            tap("Done")
            sleep(1)
        }

        // Search for a constellation and let the map glide to it.
        tap("Search")
        let field2 = app.searchFields.firstMatch
        if field2.waitForExistence(timeout: 5) {
            field2.tap()
            field2.typeText("Orion")
            sleep(1)
            let hit = app.cells.firstMatch
            if hit.waitForExistence(timeout: 5) {
                hit.tap()
                sleep(3)
                shot("04-find-orion")
            }
        }

        tap("Layers")
        sleep(2)
        shot("05-layers")
        tap("Done")
        sleep(1)

        tap("Time travel")
        sleep(2)
        shot("06-time-travel")
        tap("Done")
        sleep(1)

        tap("Night mode")
        sleep(2)
        shot("07-night-mode")
        tap("Night mode") // leave the setting as it was
    }
}
