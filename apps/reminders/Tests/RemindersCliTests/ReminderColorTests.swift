import XCTest

@testable import RemindersCore

final class ReminderColorTests: XCTestCase {
    func testNormalizesSupportedHexFormats() throws {
        XCTAssertEqual(try ReminderColor("af52de").hex, "#AF52DE")
        XCTAssertEqual(try ReminderColor(" #abc \n").hex, "#AABBCC")
        XCTAssertEqual(try ReminderColor("#11223344").hex, "#11223344")
    }

    func testRejectsInvalidColorsAsArguments() {
        for input in ["purple", "#purple", "", "#", "#12", "#12345", "#GG0000", "##FFFFFF", "#１２３４５６"] {
            XCTAssertThrowsError(try ReminderColor(input), input) { error in
                XCTAssertEqual((error as? ReminderCLIError)?.code, "invalid_argument")
            }
        }
    }

    func testNativeColorRoundTripWithoutAccessingReminderStore() throws {
        let runtime = ReminderKitRuntime()
        try runtime.load()
        let color = try runtime.makeColor(ReminderColor("#AF52DE"))
        let hex = try XCTUnwrap(runtime.stringValue(from: color, selectors: ["hexString"]))
        XCTAssertEqual(try ReminderColor(hex).hex, "#AF52DE")
    }
}
