import GesherKit
import GesherPlatform
import CalendarCore
import Foundation

/// A range word (`today`, `tomorrow`, `week`, `next week`, `month`, `next month`) or a day
/// expression (`friday`, `2026-11-05`). Validated while decoding.
struct RangeWord: Decodable, Sendable {
    static let words = [
        "today", "tomorrow", "yesterday", "week", "this week", "next week", "next-week", "month", "next month",
        "next-month",
    ]
    let text: String

    init(_ text: String) throws {
        let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
        if !Self.words.contains(lowered) {
            do { _ = try DateInput().parse(text) } catch {
                throw AgentError.invalid(
                    "Unrecognized range '\(text)'.",
                    hint:
                        "Use today, tomorrow, week, next week, month, next month, a day like friday or 2026-11-05, or from/to."
                )
            }
        }
        self.text = Self.words.contains(lowered) ? lowered.replacingOccurrences(of: "-", with: " ") : lowered
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do { try self.init(text) } catch let error as AgentError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.message, underlyingError: error))
        }
    }
}

/// `when` / `from` / `to` / `days`, shared by agenda, free-busy and free-slots.
struct DateRange {
    static let params: [Param] = [
        .string(
            "when", "today (default), tomorrow, week, next-week, month, next-month, or a day (friday, 2026-11-05).",
            positional: true),
        .date("from", "Range start (overrides when)."),
        .date("to", "Range end; a day without a time includes that whole day."),
        .integer("days", "Number of days from the start of the range.", min: 1, max: 366),
    ]

    static func resolve(
        when: RangeWord?, from: DateText?, to: DateText?, days: Int?, context: CalendarContext,
        defaultWord: String = "today"
    ) throws -> (start: Date, end: Date) {
        let calendar = context.gregorian
        let input = context.dateInput
        func dayStart(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        func addDays(_ date: Date, _ count: Int) -> Date { calendar.date(byAdding: .day, value: count, to: date)! }
        var start: Date
        var end: Date
        if let from {
            let resolved = try from.resolve(input)
            start = resolved.hasTime ? resolved.date : dayStart(resolved.date)
            end = addDays(dayStart(start), 1)
        } else {
            let today = dayStart(context.now())
            switch when?.text ?? defaultWord {
            case "today": (start, end) = (today, addDays(today, 1))
            case "tomorrow": (start, end) = (addDays(today, 1), addDays(today, 2))
            case "yesterday": (start, end) = (addDays(today, -1), today)
            case "week", "this week":
                let week = calendar.dateInterval(of: .weekOfYear, for: today)!
                (start, end) = (today, week.end)
            case "next week":
                let week = calendar.dateInterval(of: .weekOfYear, for: today)!
                (start, end) = (week.end, addDays(week.end, 7))
            case "month":
                (start, end) = (today, calendar.dateInterval(of: .month, for: today)!.end)
            case "next month":
                let next = calendar.dateInterval(of: .month, for: today)!.end
                (start, end) = (next, calendar.dateInterval(of: .month, for: next)!.end)
            case let text:
                let day = dayStart(try DateText(text).resolve(input).date)
                (start, end) = (day, addDays(day, 1))
            }
        }
        if let days { end = addDays(dayStart(start), days) }
        if let to {
            let resolved = try to.resolve(input)
            end = resolved.hasTime ? resolved.date : addDays(dayStart(resolved.date), 1)
        }
        guard end > start else { throw AgentError.invalid("The range ends before it starts.") }
        guard end.timeIntervalSince(start) <= 86400 * 732 else {
            throw AgentError.invalid("Ranges are limited to two years.", hint: "Query a shorter range.")
        }
        return (start, end)
    }
}

private let eventParam = Param.string(
    "event", "Event id, or its title (searched from 2 weeks ago to 3 months ahead).", required: true, positional: true)
private let onParam = Param.date("on", "Day of the occurrence when selecting an event by title.")
private let scopeParam = Param.choice(
    "scope", RecurrenceScope.allCases.map(\.rawValue),
    "For repeating events: this occurrence, this and future ones, or all.")
private let calendarsParam = Param.list("calendar", "Only these calendars (names or ids).")

enum Agenda: AgentOperation {
    struct Input: Decodable, Sendable {
        var when: RangeWord?
        var from: DateText?
        var to: DateText?
        var days: Int?
        var calendar: [String]?
    }

    static let path = ["agenda"]
    static let summary = "Events in a range (default today), sorted by start, from all or some calendars."
    static let params = DateRange.params + [calendarsParam]
    static let examples = [
        "agenda", "agenda tomorrow", "agenda week --calendar Work", "agenda --from 2026-11-05 --to 2026-11-07",
        "agenda friday",
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> AgendaOutput {
        let range = try DateRange.resolve(
            when: input.when, from: input.from, to: input.to, days: input.days, context: context)
        let ids = try input.calendar.map { selectors in
            let all = try context.read.fetchCalendars()
            return try selectors.map { try context.calendar($0, calendars: all).id }
        }
        let events = try context.read.fetchEvents(start: range.start, end: range.end, calendarIDs: ids)
        return AgendaOutput(
            range: RangeOutput(range.start, range.end, zone: context.timeZone),
            events: events.map { EventOutput($0, zone: context.timeZone) })
    }

    static func pretty(_ output: AgendaOutput) -> String? { CalendarPretty.agenda(output) }
}

enum GetEvent: AgentOperation {
    struct Input: Decodable, Sendable {
        var event: String
        var on: DateText?
    }

    static let path = ["event", "get"]
    static let summary = "One event with all its details (repeat rule, alerts, attendees, location, travel time)."
    static let params = [eventParam, onParam]
    static let examples = ["event get 'Team sync'", "event get Dentist --on friday"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> EventOutput {
        EventOutput(try context.event(input.event, on: input.on), zone: context.timeZone, detail: true)
    }
}

enum SearchEvents: AgentOperation {
    struct Input: Decodable, Sendable {
        var query: String
        var from: DateText?
        var to: DateText?
        var calendar: [String]?
        var limit: Int
    }

    static let path = ["event", "search"]
    static let summary =
        "Find events whose title, location or notes contain the text (default: past month to next year)."
    static let params: [Param] = [
        .string("query", "Text to look for (case, accents and niqqud ignored).", required: true, positional: true),
        .date("from", "Search from. Default: 30 days ago."),
        .date("to", "Search until. Default: a year from now."),
        calendarsParam,
        .integer("limit", "Maximum events (a repeating series counts once).", default: 25, min: 1, max: 200),
    ]
    static let examples = ["event search dentist", "event search 'רופא' --from 2026-01-01 --to 2026-12-31"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> EventsOutput {
        let today = context.gregorian.startOfDay(for: context.now())
        let start =
            try input.from.map { try $0.resolve(context.dateInput).date }
            ?? context.gregorian.date(byAdding: .day, value: -30, to: today)!
        let end =
            try input.to.map { resolved -> Date in
                let date = try resolved.resolve(context.dateInput)
                return date.hasTime ? date.date : context.gregorian.date(byAdding: .day, value: 1, to: date.date)!
            } ?? context.gregorian.date(byAdding: .day, value: 366, to: today)!
        let ids = try input.calendar.map { selectors in
            let all = try context.read.fetchCalendars()
            return try selectors.map { try context.calendar($0, calendars: all).id }
        }
        let query = NameMatcher.normalize(input.query)
        guard !query.isEmpty else { throw AgentError.invalid("The search text is empty.") }
        var seenSeries = Set<String>()
        let matches = try context.read.fetchEvents(start: start, end: end, calendarIDs: ids).filter { event in
            let haystack = [event.title, event.location?.title ?? "", event.location?.address ?? "", event.notes ?? ""]
                .map(NameMatcher.normalize).joined(separator: "\n")
            guard haystack.contains(query) else { return false }
            if let series = event.seriesID, event.id != event.nativeID || event.seriesID == event.nativeID {
                return seenSeries.insert(series).inserted
            }
            return true
        }
        return EventsOutput(events: matches.prefix(input.limit).map { EventOutput($0, zone: context.timeZone) })
    }
}

enum CreateEvent: AgentOperation {
    struct Input: Decodable, Sendable {
        let fields: EventFields

        init(from decoder: Decoder) throws {
            fields = try EventFields(from: decoder)
            try decodingCheck(decoder) { try fields.check() }
        }
    }

    static let path = ["event", "create"]
    static let summary =
        "Create an event (timed or all-day) with optional location, alerts and repeat; warns about conflicts. Invite people with event_invite."
    static let effect = OperationEffect.write
    static let params: [Param] =
        [.string("title", "Event title.", required: true, positional: true)]
        + EventFields.params.map { $0.name == "start" ? .date("start", $0.summary, required: true) : $0 }
    static let examples = [
        "event create 'Dentist' --start 'tomorrow 10:00' --duration 45 --location 'Clinic' --alerts 1h",
        "event create 'Conference' --start 2026-11-10 --end 2026-11-12 --calendar Work",
        "event create Standup --start 'monday 9:30' --duration 15 --repeat weekdays --alerts 5m",
        "event create 'Book club' --start '2026-11-10 19:00' --repeat monthly --repeat-days 2TU --repeat-count 10",
        "event create 'Call with London' --start 'friday 16:00' --time-zone Europe/London --reject-conflicts",
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> SavedEventOutput {
        let draft = try makeDraft(input.fields, context)
        var conflicts: [CalendarEventSnapshot] = []
        if !draft.isAllDay {
            conflicts = try context.conflicts(
                start: draft.start, end: draft.end, calendars: try context.schedulingCalendars(nil))
            if input.fields.rejectConflicts == true, !conflicts.isEmpty { throw conflictError(conflicts, context) }
        }
        let saved = try context.write.createEvent(draft)
        return SavedEventOutput(
            event: EventOutput(saved, zone: context.timeZone, detail: true),
            conflicts: conflicts.isEmpty ? nil : conflicts.map { EventOutput($0, zone: context.timeZone) })
    }

    static func makeDraft(_ input: EventFields, _ context: CalendarContext) throws -> EventDraft {
        guard let title = input.title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AgentError.invalid("Missing required parameter 'title' for event create.")
        }
        guard let start = input.start else {
            throw AgentError.invalid("Missing required parameter 'start' for event create.")
        }
        let zone = try input.zone() ?? context.timeZone
        let dateInput = context.dateInput
        let times = try EventTimes.make(
            start: try start.resolve(dateInput, zone: zone),
            end: try input.end.map { try $0.resolve(dateInput, zone: zone) },
            duration: input.duration, allDay: input.allDay, zone: zone)
        let calendar = try context.targetCalendar(input.calendar)
        let recurrence = try input.recurrence(dateInput)
        return EventDraft(
            calendarID: calendar.id, title: title, start: times.start, end: times.end, isAllDay: times.allDay,
            timeZone: zone, location: try input.locationInput(), notes: input.notes, url: try input.validatedURL(),
            availability: input.availabilityValue,
            travelTimeSeconds: input.travelTime.flatMap { $0 > 0 ? Double($0 * 60) : nil },
            alerts: try AlertText.specs(input.alerts), recurrence: recurrence ?? nil, attendees: [])
    }

    static func conflictError(_ conflicts: [CalendarEventSnapshot], _ context: CalendarContext) -> AgentError {
        AgentError(
            code: "conflict", message: "The time overlaps \(conflicts.count) busy event(s); nothing was saved.",
            hint: "Pick another time (free_slots helps), or retry without rejectConflicts to save anyway.",
            candidates: conflicts.map {
                Candidate(id: $0.id, name: $0.title, detail: EventOutput.when($0, zone: context.timeZone))
            })
    }
}

enum UpdateEvent: AgentOperation {
    struct Input: Decodable, Sendable {
        var event: String
        var on: DateText?
        var scope: RecurrenceScope?
        var fields: EventFields

        enum CodingKeys: String, CodingKey { case event, on, scope }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            event = try container.decode(String.self, forKey: .event)
            on = try container.decodeIfPresent(DateText.self, forKey: .on)
            scope = try container.decodeIfPresent(String.self, forKey: .scope).flatMap(RecurrenceScope.init(rawValue:))
            fields = try EventFields(from: decoder)
            try decodingCheck(decoder) { try fields.check() }
        }
    }

    static let path = ["event", "update"]
    static let summary =
        "Change an event: reschedule, rename, move calendar, edit details, alerts or repeat. Invitees: event_invite."
    static let effect = OperationEffect.write
    static let params: [Param] =
        [eventParam, onParam, scopeParam, .string("title", "New title.")] + EventFields.params
    static let examples = [
        "event update 'Dentist' --start 'thursday 11:00'",
        "event update Standup --on tomorrow --scope this --start 'tomorrow 10:00'",
        "event update Standup --scope future --repeat-days MO,WE",
        "event update 'Planning' --calendar Work --alerts 15m --alerts 1d",
        "event update 'Planning' --location '' --notes ''",
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> SavedEventOutput {
        let current = try context.event(input.event, on: input.on)
        let changes = try makeChanges(input.fields, current: current, context)
        let scope = input.scope
        var conflicts: [CalendarEventSnapshot] = []
        let start = changes.start ?? current.start
        let end = changes.end ?? start.addingTimeInterval(current.end.timeIntervalSince(current.start))
        if (changes.start != nil || changes.end != nil) && !(changes.isAllDay ?? current.isAllDay) {
            conflicts = try context.conflicts(
                start: start, end: end, calendars: try context.schedulingCalendars(nil),
                ignoring: [current.id, current.nativeID])
            if input.fields.rejectConflicts == true, !conflicts.isEmpty {
                throw CreateEvent.conflictError(conflicts, context)
            }
        }
        let saved = try context.write.updateEvent(id: current.id, changes: changes, scope: scope)
        return SavedEventOutput(
            event: EventOutput(saved, zone: context.timeZone, detail: true),
            conflicts: conflicts.isEmpty ? nil : conflicts.map { EventOutput($0, zone: context.timeZone) })
    }

    static func makeChanges(_ fields: EventFields, current: CalendarEventSnapshot, _ context: CalendarContext) throws
        -> EventChanges
    {
        var changes = EventChanges()
        let zone = try fields.zone() ?? current.timeZone.flatMap(TimeZone.init(identifier:)) ?? context.timeZone
        let dateInput = context.dateInput
        changes.title = fields.title
        if fields.timeZone != nil { changes.timeZone = zone }
        if fields.start != nil || fields.end != nil || fields.duration != nil || fields.allDay != nil {
            let start = try fields.start.map { try $0.resolve(dateInput, zone: zone) }
            let end = try fields.end.map { try $0.resolve(dateInput, zone: zone) }
            let allDay = fields.allDay ?? start.map { !$0.hasTime } ?? current.isAllDay
            if allDay {
                let currentFirst = current.isAllDay ? current.startDay : DateOutput.day(current.start, timeZone: zone)
                let first = try start ?? Self.day(currentFirst ?? DateOutput.day(current.start, timeZone: zone), zone)
                let last =
                    try end ?? (start == nil && current.isAllDay ? current.endDay.map { try Self.day($0, zone) } : nil)
                let times = try EventTimes.make(start: first, end: last, duration: nil, allDay: true, zone: zone)
                (changes.start, changes.end) = (times.start, times.end)
            } else {
                if current.isAllDay && start == nil {
                    throw AgentError.invalid("Pass start with a time when turning off all-day.")
                }
                let newStart = start?.date ?? current.start
                let duration = fields.duration.map { Double($0) * 60 } ?? current.end.timeIntervalSince(current.start)
                let newEnd = end?.date ?? newStart.addingTimeInterval(duration)
                guard newEnd > newStart else { throw AgentError.invalid("The event must end after it starts.") }
                (changes.start, changes.end) = (newStart, newEnd)
            }
            if fields.allDay != nil || allDay != current.isAllDay { changes.isAllDay = allDay }
        }
        if let location = fields.location {
            if location.isEmpty { changes.clearLocation = true } else { changes.location = try fields.locationInput() }
        } else if fields.address != nil || fields.coordinates != nil {
            guard let title = current.location?.title else {
                throw AgentError.invalid("address and coordinates need a location title.")
            }
            var copy = fields
            copy.location = title
            changes.location = try copy.locationInput()
        }
        changes.notes = fields.notes
        changes.url = try fields.validatedURL()
        changes.availability = fields.availabilityValue
        changes.travelTimeSeconds = fields.travelTime.map { Double($0 * 60) }
        changes.alerts = try AlertText.specs(fields.alerts)
        changes.recurrence = try fields.recurrence(dateInput, base: current.recurrence)
        if let calendar = fields.calendar { changes.calendarID = try context.writableCalendar(calendar).id }
        return changes
    }

    static func day(_ day: String, _ zone: TimeZone) throws -> ResolvedDate {
        try DateInput(timeZone: zone).parse(day)
    }
}

/// Adds or removes invitees. The account (iCloud, Exchange, CalDAV) emails every change to the
/// people concerned from the user's address and it cannot be recalled, so this is its own tool,
/// declared destructive: MCP clients ask the user before running it.
enum InviteToEvent: AgentOperation {
    struct Input: Decodable, Sendable {
        var event: String
        var on: DateText?
        var scope: String?
        var add: [String]?
        var remove: [String]?
    }

    static let path = ["event", "invite"]
    static let summary =
        "Invite people to an event or remove invitees. Sends real invitation or cancellation emails from the user's "
        + "account: confirm the people and the event with the user first."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("event", "Event id or exact title.", required: true, positional: true), onParam, scopeParam,
        .list("add", "Emails to invite ('Name <email>' accepted)."),
        .list("remove", "Invitee emails to remove (they are told the invitation was cancelled)."),
    ]
    static let examples = [
        "event invite 'Planning' --add 'Dana <dana@example.com>' --add sam@example.com",
        "event invite 'Planning' --remove sam@example.com",
    ]

    static func validate(_ input: Input) throws {
        guard input.add?.isEmpty == false || input.remove?.isEmpty == false else {
            throw AgentError.invalid("Nothing to change.", hint: "Pass add and/or remove with email addresses.")
        }
        _ = try EventFields.attendees(input.add)
        _ = try EventFields.attendees(input.remove)
    }

    static func run(_ input: Input, _ context: CalendarContext) throws -> SavedEventOutput {
        let current = try context.event(input.event, on: input.on, policy: .exactName)
        var changes = EventChanges()
        changes.invite = try EventFields.attendees(input.add)
        changes.uninvite = try EventFields.attendees(input.remove).map(\.email)
        let saved = try context.write.updateEvent(
            id: current.id, changes: changes, scope: input.scope.flatMap(RecurrenceScope.init(rawValue:)))
        return SavedEventOutput(event: EventOutput(saved, zone: context.timeZone, detail: true), conflicts: nil)
    }
}

enum DeleteEvents: AgentOperation {
    struct Input: Decodable, Sendable {
        var event: [String]
        var on: DateText?
        var scope: String?
    }

    static let path = ["event", "delete"]
    static let summary =
        "Delete events by id or exact title; repeating events need a scope. More than 5 are backed up first."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("event", "Event ids or exact titles.", required: true, positional: true), onParam, scopeParam,
    ]
    static let examples = [
        "event delete 'Dentist'", "event delete Standup --on tomorrow --scope this",
        "event delete x-apple-eventkit:///Event/p12 x-apple-eventkit:///Event/p13",
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> BatchOutput<DeletedEventOutput> {
        let scope = input.scope.flatMap(RecurrenceScope.init(rawValue:))
        let backup = try backupIfBulk(input.event, on: input.on, context: context)
        let batch = Batch.run(input.event, label: { $0 }) { selector in
            try delete(selector, on: input.on, scope: scope, context: context)
        }
        return BatchOutput(batch, backup: backup)
    }

    static func delete(_ selector: String, on: DateText?, scope: RecurrenceScope?, context: CalendarContext) throws
        -> DeletedEventOutput
    {
        let event = try context.event(selector, on: on, policy: .exactName)
        try context.write.deleteEvent(id: event.id, scope: scope)
        return DeletedEventOutput(
            id: event.id, title: event.title, start: EventOutput(event, zone: context.timeZone).start,
            scope: event.isRecurring ? scope?.rawValue : nil)
    }

    /// Saves the full details of the events about to be deleted when there are more than 5.
    static func backupIfBulk(_ selectors: [String], on: DateText?, context: CalendarContext) throws -> String? {
        guard selectors.count > BackupStore.threshold else { return nil }
        let events = selectors.compactMap { try? context.event($0, on: on, policy: .exactName) }
        return try context.backups.save(
            "events", ["events": events.map { EventOutput($0, zone: context.timeZone, detail: true) }])
    }
}

/// Several creates, updates and deletes in one call; each item succeeds or fails on its own.
enum BatchEvents: AgentOperation {
    struct Input: Decodable, Sendable {
        var create: [JSONValue]?
        var update: [JSONValue]?
        var delete: [JSONValue]?
    }

    static let path = ["event", "batch"]
    static let summary =
        "Create, update and delete many events in one call with a result per item (deletes over 5 are backed up)."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("create", "Events to create: objects with the event_create parameters.", of: .object),
        .list("update", "Changes: objects with the event_update parameters (event required).", of: .object),
        .list("delete", "Deletes: objects {event, on?, scope?}.", of: .object),
    ]
    static let examples = [
        """
        event batch --json '{"create":[{"title":"Focus","start":"monday 9:00","duration":120},{"title":"Focus","start":"tuesday 9:00","duration":120}]}'
        """,
        """
        event batch --json '{"update":[{"event":"Focus","on":"monday","start":"monday 10:00"}],"delete":[{"event":"Old sync"}]}'
        """,
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> BatchOutput<JSONValue> {
        let creates = (input.create ?? []).enumerated().map { ("create", $0.offset, $0.element) }
        let updates = (input.update ?? []).enumerated().map { ("update", $0.offset, $0.element) }
        let deletes = (input.delete ?? []).enumerated().map { ("delete", $0.offset, $0.element) }
        let items = creates + updates + deletes
        guard !items.isEmpty else {
            throw AgentError.invalid("Nothing to do.", hint: "Pass create, update and/or delete lists.")
        }
        guard items.count <= 100 else { throw AgentError.invalid("At most 100 items per batch.") }
        let backup: String?
        if deletes.count > BackupStore.threshold {
            let snapshots = deletes.compactMap { item -> EventOutput? in
                guard let selector = item.2["event"]?.stringValue,
                    let event = try? context.event(
                        selector, on: try? item.2["on"]?.stringValue.map(DateText.init), policy: .exactName)
                else { return nil }
                return EventOutput(event, zone: context.timeZone, detail: true)
            }
            backup = try context.backups.save("batch", ["events": snapshots])
        } else {
            backup = nil
        }
        let operations: [String: AnyOperation<CalendarContext>] = [
            "create": AnyOperation(CreateEvent.self), "update": AnyOperation(UpdateEvent.self),
            "delete": AnyOperation(DeleteOne.self),
        ]
        let result = Batch.run(
            items,
            label: { item in
                "\(item.0) #\(item.1 + 1)"
                    + ((item.2["title"]?.stringValue ?? item.2["event"]?.stringValue).map { ": \($0)" } ?? "")
            }
        ) { item in
            try operations[item.0]!.call(item.2, context: { context }).value
        }
        return BatchOutput(result, backup: backup)
    }
}

/// The per-item delete used by `event batch` (not registered as its own tool).
enum DeleteOne: AgentOperation {
    struct Input: Decodable, Sendable {
        var event: String
        var on: DateText?
        var scope: String?
    }

    static let path = ["event", "delete-one"]
    static let summary = "Delete one event."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("event", "Event id or exact title.", required: true, positional: true), onParam, scopeParam,
    ]

    static func run(_ input: Input, _ context: CalendarContext) throws -> DeletedEventOutput {
        try DeleteEvents.delete(
            input.event, on: input.on, scope: input.scope.flatMap(RecurrenceScope.init(rawValue:)), context: context)
    }
}
