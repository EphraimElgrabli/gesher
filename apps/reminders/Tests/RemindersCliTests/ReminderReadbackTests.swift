import GesherPlatform
import Foundation
import XCTest
@testable import RemindersCore

private final class StorageFixture: NSObject {
    @objc var isCompleted: Bool { false }
    @objc var priority: Int { 5 }
    @objc var flagged: Int { 1 }
    @objc var titleAsString: String { "fixture" }
    @objc var alarms: NSArray { [] }
    @objc var dueDateComponents: NSDateComponents?
}

private final class ReminderFixture: NSObject {
    let fixture = StorageFixture()
    @objc var storage: NSObject { fixture }
}

final class ReminderReadbackTests: XCTestCase {
    let read = ReminderReadRepository(runtime: ReminderKitRuntime())

    func testDateOnlyComponentsAreAllDay() throws {
        let components = NSDateComponents()
        components.year = 2030
        components.month = 3
        components.day = 4
        let date = try XCTUnwrap(read.reminderDate(components))
        XCTAssertFalse(date.hasTime)
        XCTAssertEqual(date.text(), "2030-03-04")
    }

    func testTimedComponentsKeepTheirZone() throws {
        let components = NSDateComponents()
        components.year = 2030
        components.month = 3
        components.day = 4
        components.hour = 9
        components.minute = 30
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let date = try XCTUnwrap(read.reminderDate(components))
        XCTAssertTrue(date.hasTime)
        XCTAssertEqual(date.text(in: TimeZone(identifier: "UTC")!), "2030-03-04T00:30:00Z")
    }

    func testWriteComponentsRoundTripThroughRead() throws {
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        let timed = ReminderDate(date: Date(timeIntervalSince1970: 1_900_000_000), hasTime: true, timeZone: nil)
        let written = ReminderWriteRepository.components(timed, zone: zone)
        XCTAssertEqual(written.timeZone, zone)
        XCTAssertEqual(read.reminderDate(written)?.date, timed.date)
        let day = ReminderDate(date: timed.date, hasTime: false, timeZone: nil)
        let dayComponents = ReminderWriteRepository.components(day, zone: zone)
        XCTAssertEqual(dayComponents.hour, NSDateComponentUndefined)
        XCTAssertNil(dayComponents.timeZone)
    }

    func testSnapshotReadsStorageWithoutInventingValues() throws {
        let reminder = ReminderFixture()
        let task = try read.makeTaskSnapshot(reminder, listID: "list")
        XCTAssertEqual(task.title, "fixture")
        XCTAssertEqual(task.priority, 5)
        XCTAssertTrue(task.isFlagged)
        XCTAssertNil(task.due)
        XCTAssertThrowsError(try read.makeTaskSnapshot(NSObject(), listID: "list"))
    }

    func testOverdueFollowsTheAppForDateOnlyAndTimedDueDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_900_000_000)  // mid-day UTC
        let today = calendar.startOfDay(for: now)
        let dueToday = ReminderTaskSnapshot(
            id: "a", listID: "l", title: "a", due: ReminderDate(date: today, hasTime: false, timeZone: nil))
        let dueEarlierToday = ReminderTaskSnapshot(
            id: "b", listID: "l", title: "b",
            due: ReminderDate(date: now.addingTimeInterval(-60), hasTime: true, timeZone: nil))
        XCTAssertFalse(dueToday.isOverdue(now: now, calendar: calendar))
        XCTAssertTrue(dueEarlierToday.isOverdue(now: now, calendar: calendar))
    }

    func testSectionPayloadKeepsSectionOrder() throws {
        let payload: NSDictionary = [
            "model": [
                "sectionsModel": [
                    "sections": [
                        [
                            "type": ["unsectioned": [:]],
                            "reminders": [["objectID": ["entityName": "REMCDReminder", "uuid": "r1"]]],
                        ],
                        [
                            "type": ["sectioned": ["sectionID": ["entityName": "REMCDListSection", "uuid": "s2"]]],
                            "reminders": [["objectID": ["entityName": "REMCDReminder", "uuid": "r2"]]],
                        ],
                        [
                            "type": ["sectioned": ["sectionID": ["entityName": "REMCDListSection", "uuid": "s1"]]],
                            "reminders": [],
                        ],
                    ]
                ]
            ]
        ]
        let view = try read.sectionedDataView(fromResultPayload: payload)
        XCTAssertEqual(view.sectionOrder, ["REMCDListSection:s2", "REMCDListSection:s1"])
        XCTAssertEqual(view.membershipByReminderID, ["REMCDReminder:r2": "REMCDListSection:s2"])
        XCTAssertThrowsError(try read.sectionedDataView(fromResultPayload: NSDictionary()))
    }

    func testTagMutationsAndEarlyAlertParsing() throws {
        let mutation = TaskMutation(addTags: ["#Errands", "home"], removeTags: ["OLD"])
        XCTAssertEqual(mutation.resultingTags(from: ["old", "home"]), ["home", "Errands"])
        XCTAssertEqual(TaskMutation(tags: ["a b"]).resultingTags(from: ["x"]), ["a-b"])
        XCTAssertEqual(try ReminderEarlyAlert(parsing: "15m").text, "15m")
        XCTAssertEqual(try ReminderEarlyAlert(parsing: "2 days before"), ReminderEarlyAlert(unit: .day, count: 2))
        XCTAssertThrowsError(try ReminderEarlyAlert(parsing: "soon"))
    }

    func testVerificationReportsFieldsThatDidNotRoundTrip() {
        let write = ReminderWriteRepository(runtime: ReminderKitRuntime(), readRepository: read)
        let task = ReminderTaskSnapshot(id: "t", listID: "l", title: "t", tags: ["a"])
        XCTAssertEqual(
            write.mismatches(TaskMutation(addTags: ["a"]), title: nil, before: task, after: task, listID: nil), [])
        XCTAssertEqual(
            write.mismatches(
                TaskMutation(flagged: true, addTags: ["b"]), title: nil, before: task, after: task, listID: nil),
            ["flagged", "tags"])
        XCTAssertEqual(
            write.mismatches(TaskMutation(section: .set("s")), title: nil, before: nil, after: task, listID: nil),
            ["section"])
    }

    func testRecurrenceValidation() {
        XCTAssertThrowsError(try RecurrenceMutation(frequency: .weekly, interval: 0))
        XCTAssertThrowsError(try RecurrenceMutation(frequency: .weekly, weekdays: [8]))
        XCTAssertThrowsError(try RecurrenceMutation(frequency: .daily, endDate: Date(), count: 2))
        XCTAssertEqual(try RecurrenceMutation(frequency: .weekly, weekdays: [4, 2, 4]).weekdays, [2, 4])
    }
}
