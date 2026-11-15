import XCTest

@testable import RemindersCore

final class ReminderBadgeTests: XCTestCase {
    func testEmojiAndEmblemUseTheirNativeRepresentations() throws {
        let runtime = ReminderKitRuntime()
        let rocket = try runtime.makeListBadge("🚀")
        XCTAssertEqual(runtime.stringValue(from: rocket, selectors: ["emoji"]), "🚀")
        let emblem = try runtime.makeListBadge("education1")
        XCTAssertEqual(runtime.stringValue(from: emblem, selectors: ["emblem"]), "education1")
    }

    func testRejectsEmptyAndMultipleEmojiBadges() {
        let runtime = ReminderKitRuntime()
        XCTAssertThrowsError(try runtime.makeListBadge(" "))
        XCTAssertThrowsError(try runtime.makeListBadge("🚀🚀"))
    }
}
