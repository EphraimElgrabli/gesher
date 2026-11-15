import GesherKit
import GesherPlatform
import XCTest
@testable import CalendarCli
@testable import CalendarCore

final class CalendarOperationTests: XCTestCase {
    /// An app whose context must not be created: input validation happens first.
    private func appWithoutContext() -> AgentApp<CalendarContext> {
        CalendarApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
    }

    private func run(_ app: AgentApp<CalendarContext>, _ args: [String]) -> (code: Int32, out: String) {
        var out: [String] = []
        let code = app.run(args, stdout: { out.append($0) }, stderr: { _ in })
        return (code, out.joined(separator: "\n"))
    }

    func testExamplesToolNamesAndEffects() {
        let app = CalendarApp.make()
        XCTAssertEqual(app.exampleFailures(), [])
        XCTAssertEqual(
            app.operations.map(\.toolName),
            [
                "agenda", "event_get", "event_search", "event_create", "event_update", "event_invite", "event_delete",
                "event_batch",
                "free_slots", "free_busy", "invitation_list", "invitation_respond", "calendar_list", "calendar_create",
                "calendar_update", "calendar_delete", "account_list", "doctor", "permissions",
            ])
        let effects = Dictionary(uniqueKeysWithValues: app.operations.map { ($0.toolName, $0.effect) })
        XCTAssertEqual(effects["agenda"], .read)
        XCTAssertEqual(effects["free_slots"], .read)
        XCTAssertEqual(effects["event_create"], .write)
        XCTAssertEqual(effects["event_delete"], .destructive)
        XCTAssertEqual(effects["calendar_delete"], .destructive)
        XCTAssertEqual(effects["event_batch"], .destructive)
        // Invitations email people from the user's account: only event_invite sends them, and it is
        // destructive so clients ask first. Create, update and batch cannot invite anyone.
        XCTAssertEqual(effects["event_invite"], .destructive)
        let invite = app.operations.first { $0.toolName == "event_invite" }
        XCTAssertTrue(invite?.summary.contains("emails") == true)
        for name in ["event_create", "event_update"] {
            let params = app.operations.first { $0.toolName == name }?.params.map(\.name) ?? []
            XCTAssertFalse(params.contains("invite") || params.contains("uninvite"), name)
        }
    }

    func testInvalidInputFailsBeforeTouchingCalendar() {
        let app = appWithoutContext()
        let cases: [[String]] = [
            ["agenda", "someday"],
            ["agenda", "--from", "nope"],
            ["event", "create", "X"],  // missing start
            ["event", "create", "X", "--start", "tomorrow 10:00", "--alerts", "soon"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--repeat", "FREQ=HOURLY"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--repeat", "weekly", "--repeat-days", "XX"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--time-zone", "Mars/Base"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--url", "file:///etc/passwd"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--invite", "a@example.com"],
            ["event", "invite", "X"],
            ["event", "invite", "X", "--add", "not-an-email"],
            ["event", "update", "X", "--invite", "a@example.com"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--location", "Here", "--coordinates", "999,1"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--alerts", "none", "--alerts", "15m"],
            ["event", "create", "X", "--start", "tomorrow 10:00", "--uninvite", "a@example.com"],
            ["event", "update", "X", "--scope", "sometimes"],
            ["event", "update", "X", "--availability", "maybe"],
            ["event", "delete"],
            ["free-slots", "--working-hours", "18:00-09:00"],
            ["free-slots", "--workdays", "XX"],
            ["free-slots", "--duration", "0"],
            ["calendar", "create", "X", "--color", "chartreuse-ish"],
            ["calendar", "update", "X", "--color", "#12345"],
            ["invitation", "respond", "X", "--response", "whatever"],
        ]
        for args in cases {
            XCTAssertEqual(run(app, args).code, 64, args.joined(separator: " "))
        }
        XCTAssertTrue(run(app, ["agenda", "--calender", "Work"]).out.contains("Did you mean --calendar?"))
    }

    func testRecurrenceRoundTripsBetweenRRULEAndNative() throws {
        let weekly = try RecurrenceRule.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=5")
        XCTAssertEqual(weekly.frequency.nativeRaw, 2)
        XCTAssertEqual(weekly.specifier, "D=0MO,0WE")
        XCTAssertEqual(weekly.rrule, "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=5")
        // Native forms observed for EventKit-built rules on this macOS.
        let cases: [(String, Int, String?)] = [
            ("FREQ=DAILY", 1, nil), ("FREQ=MONTHLY;BYMONTHDAY=15,-1", 3, "M=15,-1"),
            ("FREQ=MONTHLY;BYDAY=2TU", 3, "D=+2TU"),
            ("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", 3, "D=0MO,0TU,0WE,0TH,0FR;S=-1"),
            ("FREQ=YEARLY;BYMONTH=3,6", 4, "O=3,6"), ("FREQ=YEARLY;BYDAY=4TH;BYMONTH=11", 4, "D=+4TH;O=11"),
        ]
        for (text, raw, specifier) in cases {
            let rule = try RecurrenceRule.parse(text)
            XCTAssertEqual(rule.frequency.nativeRaw, raw, text)
            XCTAssertEqual(rule.specifier, specifier, text)
            let native = try XCTUnwrap(
                RecurrenceRule(nativeFrequency: raw, interval: 1, specifier: specifier, count: 0, until: nil))
            XCTAssertEqual(native, rule, text)
            XCTAssertEqual(native.rrule, text)
        }
        XCTAssertEqual(try RecurrenceRule.parse("weekdays").specifier, "D=0MO,0TU,0WE,0TH,0FR")
        let until = try RecurrenceRule.parse("FREQ=DAILY;UNTIL=20261231")
        XCTAssertNotNil(until.until)
        XCTAssertThrowsError(try RecurrenceRule.parse("FREQ=WEEKLY;BYDAY=2TU"))
        XCTAssertThrowsError(try RecurrenceRule.parse("FREQ=DAILY;COUNT=2;UNTIL=20261231"))
        XCTAssertEqual(RecurrenceRule.Day.parse("monday"), .init(weekday: 2))
        XCTAssertEqual(RecurrenceRule.Day.parse("-1fr"), .init(weekday: 6, ordinal: -1))
        XCTAssertNil(RecurrenceRule.Day.parse("mx"))
    }

    func testAlertParsing() throws {
        XCTAssertEqual(try AlertText("15").spec, .before(minutes: 15))
        XCTAssertEqual(try AlertText("2h").spec, .before(minutes: 120))
        XCTAssertEqual(try AlertText("1d").spec, .before(minutes: 1440))
        XCTAssertEqual(try AlertText("1w before").spec, .before(minutes: 10080))
        XCTAssertNil(try AlertText("none").spec)
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        let absolute = try AlertText("2026-11-05 08:00", dateInput: DateInput(timeZone: zone)).spec
        XCTAssertEqual(absolute, .at(try DateInput(timeZone: zone).parse("2026-11-05T08:00").date))
        XCTAssertThrowsError(try AlertText("soonish"))
        XCTAssertEqual(try AlertText.specs([try AlertText("none")]), [])
        let alert = CalendarAlertSnapshot(id: "a", relativeOffsetSeconds: -5400, absoluteDate: nil, type: 0)
        XCTAssertEqual(EventOutput.alert(alert, zone: zone), "90m")
        XCTAssertEqual(
            EventOutput.alert(.init(id: "b", relativeOffsetSeconds: -86400, absoluteDate: nil, type: 0), zone: zone),
            "1d")
    }

    func testCompactEventOutputInUserTimeZone() throws {
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        let start = try DateInput(timeZone: zone).parse("2026-11-05T09:00").date
        let event = CalendarEventSnapshot(
            id: "x-apple-eventkit:///Event/p1", calendarID: "c", calendarTitle: "עבודה", title: "פגישה", start: start,
            end: start.addingTimeInterval(1800), availability: .busy)
        let json = try JSONValue.encode(EventOutput(event, zone: zone, detail: true))
        XCTAssertEqual(json["start"], "2026-11-05T09:00:00+02:00")
        XCTAssertEqual(json["end"], "2026-11-05T09:30:00+02:00")
        XCTAssertEqual(json["calendar"], "עבודה")
        XCTAssertEqual(json["recurring"], false)
        for absent in [
            "location", "notes", "url", "alerts", "attendees", "availability", "repeat", "timeZone", "myStatus",
        ] {
            XCTAssertNil(json[absent], absent)
        }
        for hidden in ["nativeID", "calendarID", "seriesID", "selfStatus", "occurrenceDate"] {
            XCTAssertNil(json[hidden], hidden)
        }

        let allDay = CalendarEventSnapshot(
            id: "e2", calendarID: "c", calendarTitle: "Home", title: "Trip", start: start, end: start, isAllDay: true,
            startDay: "2026-11-05", endDay: "2026-11-07",
            alerts: [.init(id: "a", relativeOffsetSeconds: -900, absoluteDate: nil, type: 0)],
            recurrence: RecurrenceRule(frequency: .yearly))
        let allDayJSON = try JSONValue.encode(EventOutput(allDay, zone: zone, detail: true))
        XCTAssertEqual(allDayJSON["start"], "2026-11-05")
        XCTAssertEqual(allDayJSON["end"], "2026-11-07")
        XCTAssertEqual(allDayJSON["alerts"], ["15m"])
        XCTAssertEqual(allDayJSON["repeat"], "FREQ=YEARLY")
        XCTAssertEqual(allDayJSON["recurring"], true)

        let calendar = try JSONValue.encode(
            CalendarOutput(CalendarSnapshot(id: "c", title: "Home", sourceTitle: "iCloud", kind: .icloud)))
        XCTAssertNil(calendar["default"])
        XCTAssertEqual(calendar["writable"], true)
    }

    func testCalendarKindsAndWritability() {
        XCTAssertEqual(CalendarSnapshot.kind(sourceType: 5, flags: 0), .birthdays)
        XCTAssertEqual(CalendarSnapshot.kind(sourceType: 4, flags: 0), .subscribed)
        XCTAssertEqual(CalendarSnapshot.kind(sourceType: 2, flags: 0x1000), .holidays)
        XCTAssertEqual(CalendarSnapshot.kind(sourceType: 0, flags: 0), .local)
        XCTAssertFalse(CalendarSnapshot.writable(kind: .icloud, flags: 0x1))
        XCTAssertFalse(CalendarSnapshot.writable(kind: .birthdays, flags: 0))
        XCTAssertTrue(CalendarSnapshot.writable(kind: .local, flags: 0))
    }

    func testAllDayNativeDatesAreFloatingDays() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let first = try DateInput(timeZone: zone).parse("2026-11-05")
        let last = try DateInput(timeZone: zone).parse("2026-11-06")
        let times = try EventTimes.make(start: first, end: last, duration: nil, allDay: nil, zone: zone)
        XCTAssertTrue(times.allDay)
        XCTAssertEqual(DateOutput.iso(times.start, timeZone: TimeZone(identifier: "GMT")!), "2026-11-05T00:00:00Z")
        // CalendarDatabase stores the last second of the last day (as Calendar's own events).
        XCTAssertEqual(DateOutput.iso(times.end, timeZone: TimeZone(identifier: "GMT")!), "2026-11-06T23:59:59Z")
        XCTAssertEqual(
            EventDates.allDayRange(start: times.start, end: times.end, zoneName: EventDates.floating),
            ["2026-11-05", "2026-11-06"])
    }
}
