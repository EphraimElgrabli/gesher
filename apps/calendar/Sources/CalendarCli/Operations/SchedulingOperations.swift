import GesherKit
import GesherPlatform
import CalendarCore
import Foundation

/// Working hours like `09:00-18:00`.
struct WorkingHours: Decodable, Sendable, Equatable {
    let start: Int  // minutes from midnight
    let end: Int

    init(_ text: String) throws {
        let parts = text.replacingOccurrences(of: " ", with: "").split(separator: "-").map(String.init)
        func minutes(_ value: String) -> Int? {
            let pieces = value.split(separator: ":").compactMap { Int($0) }
            guard (1...2).contains(pieces.count), (0...24).contains(pieces[0]) else { return nil }
            let minute = pieces.count == 2 ? pieces[1] : 0
            guard (0...59).contains(minute) else { return nil }
            return pieces[0] * 60 + minute
        }
        guard parts.count == 2, let start = minutes(parts[0]), let end = minutes(parts[1]), end > start, end <= 1440
        else {
            throw AgentError.invalid("Working hours must look like 09:00-18:00.")
        }
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        var parsed: WorkingHours?
        try decodingCheck(decoder) { parsed = try WorkingHours(text) }
        self = parsed!
    }

    var text: String { String(format: "%02d:%02d-%02d:%02d", start / 60, start % 60, end / 60, end % 60) }
}

/// Pure interval arithmetic for free/busy and slot finding (unit tested).
enum Scheduling {
    struct Interval: Equatable, Sendable {
        var start: Date
        var end: Date
        var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    }

    /// Busy time of events: travel time before and `buffer` minutes around each, merged.
    static func busy(_ events: [CalendarEventSnapshot], buffer: Int, includeAllDay: Bool) -> [Interval] {
        let intervals = events.filter { $0.blocksTime && (includeAllDay || !$0.isAllDay) }.map { event in
            Interval(
                start: event.start.addingTimeInterval(-(event.travelTimeSeconds ?? 0) - Double(buffer * 60)),
                end: event.end.addingTimeInterval(Double(buffer * 60)))
        }
        return merge(intervals)
    }

    static func merge(_ intervals: [Interval]) -> [Interval] {
        var merged: [Interval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// `window` minus `busy`.
    static func free(_ window: Interval, busy: [Interval]) -> [Interval] {
        var gaps: [Interval] = []
        var cursor = window.start
        for block in busy where block.end > window.start && block.start < window.end {
            if block.start > cursor { gaps.append(Interval(start: cursor, end: min(block.start, window.end))) }
            cursor = max(cursor, block.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end { gaps.append(Interval(start: cursor, end: window.end)) }
        return gaps
    }

    /// Free intervals of at least `duration` minutes inside working hours on working days.
    static func slots(
        range: Interval, busy: [Interval], duration: Int, hours: WorkingHours, workday: (Date) -> Bool,
        calendar: Calendar, limit: Int
    ) -> [Interval] {
        var result: [Interval] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end && result.count < limit {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day)! }
            guard workday(day) else { continue }
            let open = calendar.date(byAdding: .minute, value: hours.start, to: day)!
            let close = calendar.date(byAdding: .minute, value: hours.end, to: day)!
            let window = Interval(start: max(open, range.start), end: min(close, range.end))
            guard window.end > window.start else { continue }
            for gap in free(window, busy: busy) {
                // Start on a 5-minute boundary.
                let seconds = gap.start.timeIntervalSinceReferenceDate
                let rounded = Date(timeIntervalSinceReferenceDate: (seconds / 300).rounded(.up) * 300)
                let slot = Interval(start: rounded, end: gap.end)
                if slot.end > slot.start, slot.minutes >= duration { result.append(slot) }
                if result.count >= limit { break }
            }
        }
        return result
    }

    static func output(_ interval: Interval, zone: TimeZone) -> SlotOutput {
        SlotOutput(
            start: DateOutput.iso(interval.start, timeZone: zone), end: DateOutput.iso(interval.end, timeZone: zone),
            minutes: interval.minutes)
    }
}

private let schedulingCalendarsParam = Param.list(
    "calendar", "Calendars to consider (names or ids). Default: all except subscribed, birthdays and holidays.")
private let includeAllDayParam = Param.boolean("includeAllDay", "Count all-day events marked busy as busy.")

enum FreeSlots: AgentOperation {
    struct Input: Decodable, Sendable {
        var when: RangeWord?
        var from: DateText?
        var to: DateText?
        var days: Int?
        var duration: Int
        var workingHours: WorkingHours?
        var workdays: [String]?
        var buffer: Int
        var calendar: [String]?
        var includeAllDay: Bool
        var limit: Int

        enum CodingKeys: String, CodingKey {
            case when, from, to, days, duration, workingHours, workdays, buffer, calendar, includeAllDay, limit
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            when = try c.decodeIfPresent(RangeWord.self, forKey: .when)
            from = try c.decodeIfPresent(DateText.self, forKey: .from)
            to = try c.decodeIfPresent(DateText.self, forKey: .to)
            days = try c.decodeIfPresent(Int.self, forKey: .days)
            duration = try c.decode(Int.self, forKey: .duration)
            workingHours = try c.decodeIfPresent(WorkingHours.self, forKey: .workingHours)
            workdays = try c.decodeIfPresent([String].self, forKey: .workdays)
            buffer = try c.decode(Int.self, forKey: .buffer)
            calendar = try c.decodeIfPresent([String].self, forKey: .calendar)
            includeAllDay = try c.decode(Bool.self, forKey: .includeAllDay)
            limit = try c.decode(Int.self, forKey: .limit)
            try decodingCheck(decoder) { _ = try FreeSlots.weekdays(workdays) }
        }
    }

    static let path = ["free-slots"]
    static let summary = "Find free time of a given length inside working hours (default: the next 7 days)."
    static let params: [Param] =
        DateRange.params + [
            .integer("duration", "Minutes needed.", default: 30, min: 5, max: 1440),
            .string(
                "workingHours",
                "Hours to search, e.g. 09:00-18:00. Default: config calendar.workingHours or 09:00-18:00."),
            .list(
                "workdays",
                "Days to search, e.g. SU MO TU WE TH. Default: config calendar.workdays or your locale's weekdays."),
            .integer("buffer", "Minutes to keep free before and after other events.", default: 0, min: 0, max: 240),
            schedulingCalendarsParam, includeAllDayParam,
            .integer("limit", "Maximum slots.", default: 10, min: 1, max: 100),
        ]
    static let examples = [
        "free-slots --duration 60", "free-slots tomorrow --duration 30 --working-hours 10:00-16:00",
        "free-slots next-week --duration 90 --calendar Work --calendar Personal --buffer 15",
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> FreeSlotsOutput {
        let hours =
            try input.workingHours ?? WorkingHours(context.config.value("calendar", "workingHours") ?? "09:00-18:00")
        let workday = try workdayTest(input.workdays, context)
        var range: (start: Date, end: Date)
        if input.when == nil && input.from == nil && input.to == nil {
            let today = context.gregorian.startOfDay(for: context.now())
            range = (today, context.gregorian.date(byAdding: .day, value: input.days ?? 7, to: today)!)
        } else {
            range = try DateRange.resolve(
                when: input.when, from: input.from, to: input.to, days: input.days, context: context)
        }
        range.start = max(range.start, context.now())
        let calendars = try context.schedulingCalendars(input.calendar)
        let events =
            range.end > range.start
            ? try context.read.fetchEvents(start: range.start, end: range.end, calendarIDs: calendars.map(\.id)) : []
        let busy = Scheduling.busy(events, buffer: input.buffer, includeAllDay: input.includeAllDay)
        let slots =
            range.end > range.start
            ? Scheduling.slots(
                range: .init(start: range.start, end: range.end), busy: busy, duration: input.duration, hours: hours,
                workday: workday, calendar: context.gregorian, limit: input.limit) : []
        return FreeSlotsOutput(
            range: RangeOutput(range.start, max(range.start, range.end), zone: context.timeZone),
            duration: input.duration, workingHours: hours.text, calendars: calendars.map(\.title),
            slots: slots.map { Scheduling.output($0, zone: context.timeZone) })
    }

    static func pretty(_ output: FreeSlotsOutput) -> String? { CalendarPretty.slots(output) }

    static func weekdays(_ codes: [String]?) throws -> Set<Int>? {
        try codes.map { codes in
            try Set(
                codes.flatMap { $0.split(separator: ",").map(String.init) }.map { code -> Int in
                    guard let day = RecurrenceRule.Day.parse(code), day.ordinal == 0 else {
                        throw AgentError.invalid(
                            "Unrecognized workday '\(code)'.", hint: "Use SU, MO, TU, WE, TH, FR, SA.")
                    }
                    return day.weekday
                })
        }
    }

    static func workdayTest(_ explicit: [String]?, _ context: CalendarContext) throws -> (Date) -> Bool {
        let codes =
            explicit?.flatMap { $0.split(separator: ",").map(String.init) }
            ?? context.config.value("calendar", "workdays").map { $0.split(separator: ",").map(String.init) }
        guard let codes else {
            let calendar = context.gregorian
            return { !calendar.isDateInWeekend($0) }
        }
        let weekdays = try Self.weekdays(codes) ?? []
        let calendar = context.gregorian
        return { weekdays.contains(calendar.component(.weekday, from: $0)) }
    }
}

enum FreeBusy: AgentOperation {
    struct Input: Decodable, Sendable {
        var when: RangeWord?
        var from: DateText?
        var to: DateText?
        var days: Int?
        var calendar: [String]?
        var includeAllDay: Bool
    }

    static let path = ["free-busy"]
    static let summary = "Busy and free blocks for a range (default today) without event details."
    static let params: [Param] = DateRange.params + [schedulingCalendarsParam, includeAllDayParam]
    static let examples = ["free-busy", "free-busy tomorrow", "free-busy --from 'monday 8:00' --to 'monday 20:00'"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> FreeBusyOutput {
        let range = try DateRange.resolve(
            when: input.when, from: input.from, to: input.to, days: input.days, context: context)
        let calendars = try context.schedulingCalendars(input.calendar)
        let events = try context.read.fetchEvents(start: range.start, end: range.end, calendarIDs: calendars.map(\.id))
        let window = Scheduling.Interval(start: range.start, end: range.end)
        let busy = Scheduling.busy(events, buffer: 0, includeAllDay: input.includeAllDay).compactMap {
            interval -> Scheduling.Interval? in
            let clipped = Scheduling.Interval(
                start: max(interval.start, window.start), end: min(interval.end, window.end))
            return clipped.end > clipped.start ? clipped : nil
        }
        return FreeBusyOutput(
            range: RangeOutput(range.start, range.end, zone: context.timeZone), calendars: calendars.map(\.title),
            busy: busy.map { Scheduling.output($0, zone: context.timeZone) },
            free: Scheduling.free(window, busy: busy).map { Scheduling.output($0, zone: context.timeZone) })
    }
}

enum ListInvitations: AgentOperation {
    struct Input: Decodable, Sendable {
        var days: Int
    }

    static let path = ["invitation", "list"]
    static let summary = "Invitations you have not answered yet (default: the next 60 days)."
    static let params: [Param] = [.integer("days", "Days ahead to look.", default: 60, min: 1, max: 366)]
    static let examples = ["invitation list", "invitation list --days 14"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> EventsOutput {
        let start = context.gregorian.startOfDay(for: context.now())
        let end = context.gregorian.date(byAdding: .day, value: input.days, to: start)!
        var series = Set<String>()
        let pending = try context.read.fetchEvents(start: start, end: end).filter { event in
            guard event.selfStatus == .pending, event.organizer?.isCurrentUser != true else { return false }
            return event.seriesID.map { series.insert($0).inserted } ?? true
        }
        return EventsOutput(events: pending.map { EventOutput($0, zone: context.timeZone, detail: true) })
    }
}

enum RespondToInvitation: AgentOperation {
    struct Input: Decodable, Sendable {
        var event: String
        var response: String
        var on: DateText?
    }

    static let path = ["invitation", "respond"]
    static let summary = "Accept, decline or tentatively accept an invitation (the account sends the reply)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("event", "Invitation event id or title.", required: true, positional: true),
        .choice("response", ["accept", "decline", "maybe"], "Your answer.", required: true),
        .date("on", "Day of the occurrence when selecting by title."),
    ]
    static let examples = ["invitation respond 'Quarterly review' --response accept"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> EventOutput {
        let event = try context.event(input.event, on: input.on)
        let status: ParticipantStatus =
            switch input.response {
            case "accept": .accepted
            case "decline": .declined
            default: .tentative
            }
        return EventOutput(
            try context.write.respond(id: event.id, status: status), zone: context.timeZone, detail: true)
    }
}
