import XCTest

final class TelecomUITests: XCTestCase {
    func testLoginScreenElementsExist() throws {
        let app = XCUIApplication()
        app.launch()

        // Splash briefly shows TELECOM, then login if logged out.
        let telecom = app.staticTexts["TELECOM"]
        XCTAssertTrue(telecom.waitForExistence(timeout: 5))

        let accountLogin = app.staticTexts["Account Login"]
        // May already be home if a session exists in the simulator keychain.
        if accountLogin.waitForExistence(timeout: 3) {
            XCTAssertTrue(app.buttons["Login"].exists)
        }
    }
}
