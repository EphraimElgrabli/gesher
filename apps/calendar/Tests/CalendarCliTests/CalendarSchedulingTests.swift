import GesherKit
import GesherPlatform
import XCTest
@testable import CalendarCli
@testable import CalendarCore

final class CalendarSchedulingTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Jerusalem")!

    private func date(_ text: String) throws -> Date { try DateInput(timeZone: zone).parse(text).date }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func event(
        _ start: String, _ end: String, availability: EventAvailability? = nil, travel: Double? = nil,
        status: ParticipantStatus? = nil, allDay: Bool = false
    ) throws -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID().uuidString, calendarID: "c", calendarTitle: "Work", title: "Busy", start: try date(start),
            end: try date(end), isAllDay: allDay, availability: availability, travelTimeSeconds: travel,
            selfStatus: status)
    }

    func testBusyMergesOverlapsAndHonorsTravelFreeAndDeclined() throws {
        let busy = Scheduling.busy(
            [
                try event("2026-11-05T09:00", "2026-11-05T10:00"),
                try event("2026-11-05T09:30", "2026-11-05T11:00"),
                try event("2026-11-05T13:00", "2026-11-05T14:00", travel: 1800),
                try event("2026-11-05T15:00", "2026-11-05T16:00", availability: .free),
                try event("2026-11-05T16:00", "2026-11-05T17:00", status: .declined),
                try event("2026-11-05", "2026-11-06", allDay: true),
            ], buffer: 0, includeAllDay: false)
        XCTAssertEqual(
            busy,
            [
                .init(start: try date("2026-11-05T09:00"), end: try date("2026-11-05T11:00")),
                .init(start: try date("2026-11-05T12:30"), end: try date("2026-11-05T14:00")),
            ])
    }

    func testSlotsRespectWorkingHoursWorkdaysDurationAndLimit() throws {
        let busy = Scheduling.busy(
            [
                try event("2026-11-05T09:00", "2026-11-05T10:00"),
                try event("2026-11-05T10:20", "2026-11-05T17:00"),
            ], buffer: 0, includeAllDay: false)
        let hours = try WorkingHours("09:00-18:00")
        // Thursday 2026-11-05 to Sunday 2026-11-08; Friday and Saturday are not workdays.
        let workdays: Set<Int> = [1, 2, 3, 4, 5]
        let slots = Scheduling.slots(
            range: .init(start: try date("2026-11-05T00:00"), end: try date("2026-11-09T00:00")), busy: busy,
            duration: 30, hours: hours,
            workday: { [calendar] in workdays.contains(calendar.component(.weekday, from: $0)) },
            calendar: calendar, limit: 10)
        XCTAssertEqual(
            slots.map { DateOutput.iso($0.start, timeZone: zone) + "/\($0.minutes)" },
            ["2026-11-05T17:00:00+02:00/60", "2026-11-08T09:00:00+02:00/540"])
        let limited = Scheduling.slots(
            range: .init(start: try date("2026-11-05T00:00"), end: try date("2026-11-09T00:00")), busy: [],
            duration: 30, hours: hours, workday: { _ in true }, calendar: calendar, limit: 2)
        XCTAssertEqual(limited.count, 2)
    }

    func testSlotsStartOnFiveMinuteBoundaries() throws {
        let busy = [Scheduling.Interval(start: try date("2026-11-05T09:00"), end: try date("2026-11-05T09:07"))]
        let slots = Scheduling.slots(
            range: .init(start: try date("2026-11-05T09:00"), end: try date("2026-11-05T10:00")), busy: busy,
            duration: 15, hours: try WorkingHours("09:00-18:00"), workday: { _ in true }, calendar: calendar, limit: 5)
        XCTAssertEqual(slots.first.map { DateOutput.iso($0.start, timeZone: zone) }, "2026-11-05T09:10:00+02:00")
    }

    func testFreeIsTheComplementOfBusy() throws {
        let window = Scheduling.Interval(start: try date("2026-11-05T08:00"), end: try date("2026-11-05T12:00"))
        let free = Scheduling.free(
            window,
            busy: [
                .init(start: try date("2026-11-05T07:00"), end: try date("2026-11-05T09:00")),
                .init(start: try date("2026-11-05T10:00"), end: try date("2026-11-05T11:00")),
            ])
        XCTAssertEqual(free.map(\.minutes), [60, 60])
    }

    func testWorkingHoursParsing() throws {
        XCTAssertEqual(try WorkingHours("8:30 - 17:00").text, "08:30-17:00")
        XCTAssertThrowsError(try WorkingHours("17:00-09:00"))
        XCTAssertThrowsError(try WorkingHours("nine to five"))
    }

    func testRangeWordsResolveInTheUserTimeZone() throws {
        let now = try date("2026-11-05T15:00")  // a Thursday
        let runtime = CalendarRuntime()
        let read = CalendarReadRepository(runtime: runtime)
        let context = CalendarContext(
            read: read, write: CalendarWriteRepository(runtime: runtime, readRepository: read),
            config: UserConfig(values: [:]), backups: BackupStore(directory: FileManager.default.temporaryDirectory),
            timeZone: zone, now: { now })
        func range(_ word: String?, from: String? = nil, to: String? = nil, days: Int? = nil) throws -> [String] {
            let resolved = try DateRange.resolve(
                when: try word.map(RangeWord.init), from: try from.map(DateText.init), to: try to.map(DateText.init),
                days: days, context: context)
            return [DateOutput.iso(resolved.start, timeZone: zone), DateOutput.iso(resolved.end, timeZone: zone)]
        }
        XCTAssertEqual(try range(nil), ["2026-11-05T00:00:00+02:00", "2026-11-06T00:00:00+02:00"])
        XCTAssertEqual(try range("tomorrow"), ["2026-11-06T00:00:00+02:00", "2026-11-07T00:00:00+02:00"])
        XCTAssertEqual(try range("today", days: 3)[1], "2026-11-08T00:00:00+02:00")
        XCTAssertEqual(
            try range(nil, from: "2026-11-10", to: "2026-11-11"),
            ["2026-11-10T00:00:00+02:00", "2026-11-12T00:00:00+02:00"])
        XCTAssertEqual(try range(nil, from: "2026-11-10 08:00", to: "2026-11-10 12:00")[1], "2026-11-10T12:00:00+02:00")
        XCTAssertThrowsError(try range(nil, from: "2026-11-10", to: "2026-11-01"))
    }

    func testBackupStoreWritesJSONSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try BackupStore(directory: directory).save("events", ["events": ["a", "b"]])
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(value["events"], ["a", "b"])
        XCTAssertTrue(path.hasPrefix(directory.path))
    }
}
