import XCTest
@testable import GesherPlatform

final class DateInputTests: XCTestCase {
    // Tuesday 2026-11-03 10:30 in Jerusalem (UTC+2).
    let zone = TimeZone(identifier: "Asia/Jerusalem")!
    lazy var input = DateInput(timeZone: zone, now: ISO8601DateFormatter().date(from: "2026-11-03T08:30:00Z")!)

    private func iso(_ text: String) throws -> String { try input.parse(text).iso }

    func testDayWords() throws {
        XCTAssertEqual(try iso("today"), "2026-11-03")
        XCTAssertEqual(try iso("Tomorrow"), "2026-11-04")
        XCTAssertEqual(try iso("מחר"), "2026-11-04")
        XCTAssertEqual(try iso("yesterday"), "2026-11-02")
        XCTAssertEqual(try iso("friday"), "2026-11-06")
        XCTAssertEqual(try iso("next tue"), "2026-11-10")
    }

    func testTimes() throws {
        XCTAssertEqual(try iso("tomorrow 9:00"), "2026-11-04T09:00:00+02:00")
        XCTAssertEqual(try iso("today 6pm"), "2026-11-03T18:00:00+02:00")
        XCTAssertEqual(try iso("friday at 18:30"), "2026-11-06T18:30:00+02:00")
        XCTAssertEqual(try iso("9:00"), "2026-11-04T09:00:00+02:00")
        XCTAssertEqual(try iso("11:00"), "2026-11-03T11:00:00+02:00")
        XCTAssertEqual(try iso("tonight"), "2026-11-03T20:00:00+02:00")
    }

    func testRelativeAndISO() throws {
        XCTAssertEqual(try iso("in 2 hours"), "2026-11-03T12:30:00+02:00")
        XCTAssertEqual(try iso("+1d"), "2026-11-04T10:30:00+02:00")
        XCTAssertEqual(try iso("2026-12-01"), "2026-12-01")
        XCTAssertEqual(try iso("2026-12-01 14:00"), "2026-12-01T14:00:00+02:00")
        XCTAssertEqual(try iso("2026-12-01T14:00:00Z"), "2026-12-01T16:00:00+02:00")
        XCTAssertFalse(try input.parse("2026-12-01").hasTime)
    }

    func testPastDates() throws {
        XCTAssertEqual(try iso("7 days ago"), "2026-10-27")
        XCTAssertFalse(try input.parse("7 days ago").hasTime)
        XCTAssertEqual(try iso("2 weeks ago"), "2026-10-20")
        XCTAssertEqual(try iso("1 month ago"), "2026-10-03")
        XCTAssertEqual(try iso("1 year ago"), "2025-11-03")
        XCTAssertEqual(try iso("3d ago"), "2026-10-31")
        XCTAssertEqual(try iso("2 hours ago"), "2026-11-03T08:30:00+02:00")
        XCTAssertEqual(try iso("-1d"), "2026-11-02T10:30:00+02:00")
        XCTAssertEqual(try iso("last friday"), "2026-10-30")
        XCTAssertEqual(try iso("last tue 9:00"), "2026-10-27T09:00:00+02:00")
        XCTAssertEqual(try iso("in 2 months"), "2027-01-03T10:30:00+02:00")
        XCTAssertThrowsError(try input.parse("days ago"))
    }

    func testInvalidHasHint() {
        XCTAssertThrowsError(try input.parse("someday")) { error in
            XCTAssertEqual((error as? AgentError)?.code, "invalid_argument")
            XCTAssertNotNil((error as? AgentError)?.hint)
        }
        XCTAssertThrowsError(try input.parse("tomorrow 25:00"))
    }
}
