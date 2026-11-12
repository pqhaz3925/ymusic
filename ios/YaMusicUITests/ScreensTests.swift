import XCTest

/// Walks the main screens on a real device and attaches a screenshot of each.
/// Screenshots end up in the .xcresult bundle (export with `xcrun xcresulttool export attachments`).
final class ScreensTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-autoplay"]
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testWalkthrough() {
        // Home: wait for the hero title, let the wave start and the palette settle.
        XCTAssertTrue(app.staticTexts["Моя волна"].waitForExistence(timeout: 10))
        sleep(4)
        shot("01-home")

        // Scroll into shelves.
        app.swipeUp()
        sleep(1)
        shot("02-home-scrolled")
        app.swipeDown()
        app.swipeDown()
        sleep(1)

        // Now Playing via the mini player.
        let mini = app.staticTexts.matching(NSPredicate(format: "label != 'Моя волна'")).element(boundBy: 0)
        _ = mini
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            // The accessory sits right above the tab bar; tap its centre.
            let f = tabBar.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: f.midX - 60, dy: f.minY - 30))
                .tap()
            sleep(2)
            shot("03-now-playing")
            app.swipeDown(velocity: .fast)
            sleep(1)
        }

        // Collection tab.
        let collection = app.buttons["Коллекция"]
        if collection.waitForExistence(timeout: 3) {
            collection.tap()
            sleep(2)
            shot("04-collection")
        }

        // Search tab.
        let search = app.buttons["Поиск"].exists ? app.buttons["Поиск"] : app.buttons["Search"]
        if search.waitForExistence(timeout: 3) {
            search.tap()
            sleep(1)
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("мартин")
                sleep(2)
            }
            shot("05-search")
        }
    }
}
