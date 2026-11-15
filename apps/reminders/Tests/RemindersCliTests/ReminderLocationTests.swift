import XCTest

@testable import RemindersCore

final class ReminderLocationTests: XCTestCase {
    func testValidLocationUsesRequestedValues() throws {
        let location = try ReminderLocationMutation(
            title: "Cafe Tamar",
            address: "Nagy Diófa u. 3, Budapest",
            latitude: 47.497,
            longitude: 19.063,
            radius: 125,
            proximity: .leaving
        )

        XCTAssertEqual(location.title, "Cafe Tamar")
        XCTAssertEqual(location.address, "Nagy Diófa u. 3, Budapest")
        XCTAssertEqual(location.latitude, 47.497)
        XCTAssertEqual(location.longitude, 19.063)
        XCTAssertEqual(location.radius, 125)
        XCTAssertEqual(location.proximity, .leaving)
        XCTAssertEqual(location.proximity.reminderKitValue, 2)
    }

    func testLocationRejectsInvalidCoordinatesAndRadius() {
        XCTAssertThrowsError(
            try ReminderLocationMutation(
                title: "Bad latitude",
                address: "Budapest",
                latitude: 91,
                longitude: 19
            )
        )
        XCTAssertThrowsError(
            try ReminderLocationMutation(
                title: "Bad longitude",
                address: "Budapest",
                latitude: 47,
                longitude: 181
            )
        )
        XCTAssertThrowsError(
            try ReminderLocationMutation(
                title: "Bad radius",
                address: "Budapest",
                latitude: 47,
                longitude: 19,
                radius: 0
            )
        )
    }

    func testReminderKitProximityMapping() {
        XCTAssertEqual(ReminderLocationProximity(reminderKitValue: 1), .arriving)
        XCTAssertEqual(ReminderLocationProximity(reminderKitValue: 2), .leaving)
        XCTAssertNil(ReminderLocationProximity(reminderKitValue: 0))
    }
}
