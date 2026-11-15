import GesherKit
import GesherPlatform
import CalendarCore
import Foundation

@main
enum CalendarCli {
    static func main() { CalendarApp.make().main() }
}

/// The Calendar app: its operations, defaults and shared dependencies (see AGENTS.md).
enum CalendarApp {
    static func make(context: @escaping () throws -> CalendarContext = { CalendarContext() }) -> AgentApp<
        CalendarContext
    > {
        AgentApp(
            name: "calendar",
            summary: "Agenda, events, scheduling and calendars from Apple Calendar.",
            instructions: """
                Times are in the user's time zone with an offset; all-day events use plain days (end day inclusive). \
                Dates accept today, tomorrow 9:00, friday 14:30, +2h, 2026-11-05 or ISO 8601. Calendars and events \
                accept a name or an id; prefer ids from earlier results. Repeating events need scope this, future or \
                all for edits and deletes. Writes echo the saved event: check it. Never guess free time: use \
                free_slots or free_busy. event_invite emails real invitations from the user's account: only invite \
                people the user named, after confirming.
                """,
            permission: .calendar,
            permissionBackend: CalendarPermission(),
            operations: [
                AnyOperation(Agenda.self),
                AnyOperation(GetEvent.self),
                AnyOperation(SearchEvents.self),
                AnyOperation(CreateEvent.self),
                AnyOperation(UpdateEvent.self),
                AnyOperation(InviteToEvent.self),
                AnyOperation(DeleteEvents.self),
                AnyOperation(BatchEvents.self),
                AnyOperation(FreeSlots.self),
                AnyOperation(FreeBusy.self),
                AnyOperation(ListInvitations.self),
                AnyOperation(RespondToInvitation.self),
                AnyOperation(ListCalendars.self),
                AnyOperation(CreateCalendar.self),
                AnyOperation(UpdateCalendar.self),
                AnyOperation(DeleteCalendar.self),
                AnyOperation(ListAccounts.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Calendar operation for the life of the process (or MCP session).
/// Repositories re-read native state on every call; nothing here caches user data.
final class CalendarContext {
    let read: CalendarReadRepository
    let write: CalendarWriteRepository
    let config: UserConfig
    let backups: BackupStore
    let timeZone: TimeZone
    let now: () -> Date

    init(config: UserConfig = .load()) {
        let runtime = CalendarRuntime()
        read = CalendarReadRepository(runtime: runtime)
        write = CalendarWriteRepository(runtime: runtime, readRepository: read)
        self.config = config
        backups = BackupStore()
        timeZone = .current
        now = { Date() }
    }

    /// For tests: inject repositories, configuration, a backup directory and a clock.
    init(
        read: CalendarReadRepository, write: CalendarWriteRepository, config: UserConfig, backups: BackupStore,
        timeZone: TimeZone = .current, now: @escaping () -> Date = { Date() }
    ) {
        self.read = read
        self.write = write
        self.config = config
        self.backups = backups
        self.timeZone = timeZone
        self.now = now
    }

    var dateInput: DateInput { DateInput(timeZone: timeZone, now: now()) }

    var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale.current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    // MARK: Calendars

    func calendar(_ selector: String, policy: MatchPolicy = .fuzzy, calendars: [CalendarSnapshot]? = nil) throws
        -> CalendarSnapshot
    {
        try EntityResolver.resolve(
            selector, in: try calendars ?? read.fetchCalendars(), type: "calendar", id: \.id, name: \.title,
            detail: { $0.sourceTitle }, policy: policy)
    }

    /// A calendar new events may be written to.
    func writableCalendar(_ selector: String, calendars: [CalendarSnapshot]? = nil) throws -> CalendarSnapshot {
        let match = try calendar(selector, calendars: calendars)
        guard match.writable else {
            throw AgentError(
                code: "read_only_calendar", message: "'\(match.title)' (\(match.kind.rawValue)) is read-only.",
                hint: "Choose a writable calendar from calendar list.")
        }
        return match
    }

    /// Explicit calendar > configured `calendar.calendar` > Calendar's default for new events >
    /// the only writable calendar.
    func targetCalendar(_ selector: String?, calendars: [CalendarSnapshot]? = nil) throws -> CalendarSnapshot {
        let all = try calendars ?? read.fetchCalendars()
        if let selector = selector ?? config.value("calendar", "calendar") {
            return try writableCalendar(selector, calendars: all)
        }
        if let native = all.first(where: { $0.isDefault && $0.writable }) { return native }
        let writable = all.filter(\.writable)
        if writable.count == 1 { return writable[0] }
        throw AgentError(
            code: "invalid_argument", message: "No default calendar for new events.",
            hint: "Pass calendar, or set calendar.calendar in ~/.config/gesher/config.json.",
            candidates: writable.map { Candidate(id: $0.id, name: $0.title, detail: $0.sourceTitle) })
    }

    /// Calendars to consider for scheduling: the given ones, else every calendar except
    /// subscribed, birthday and holiday calendars.
    func schedulingCalendars(_ selectors: [String]?) throws -> [CalendarSnapshot] {
        let all = try read.fetchCalendars()
        if let selectors, !selectors.isEmpty {
            return try EntityResolver.resolveAll(
                selectors, in: all, type: "calendar", id: \.id, name: \.title, detail: { $0.sourceTitle })
        }
        if let configured = config.value("calendar", "scheduling") {
            return try EntityResolver.resolveAll(
                configured.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, in: all,
                type: "calendar", id: \.id, name: \.title, detail: { $0.sourceTitle })
        }
        return all.filter { ![.subscribed, .birthdays, .holidays].contains($0.kind) }
    }

    // MARK: Events

    static func looksLikeID(_ selector: String) -> Bool { selector.hasPrefix("x-apple-eventkit:") }

    /// An event by id, or by title among events near `on` (that day) or from 2 weeks ago to
    /// 3 months ahead. A repeating series is offered once, at its next occurrence.
    func event(_ selector: String, on day: DateText? = nil, policy: MatchPolicy = .fuzzy) throws
        -> CalendarEventSnapshot
    {
        if Self.looksLikeID(selector) { return try read.fetchEvent(id: selector) }
        let window: (Date, Date)
        if let day {
            let resolved = try day.resolve(dateInput)
            let start = gregorian.startOfDay(for: resolved.date)
            window = (start, gregorian.date(byAdding: .day, value: 1, to: start)!)
        } else {
            let today = gregorian.startOfDay(for: now())
            window = (
                gregorian.date(byAdding: .day, value: -14, to: today)!,
                gregorian.date(byAdding: .day, value: 92, to: today)!
            )
        }
        let current = now()
        var bySeries: [String: CalendarEventSnapshot] = [:]
        var singles: [CalendarEventSnapshot] = []
        for event in try read.fetchEvents(start: window.0, end: window.1) {
            guard day == nil, let series = event.seriesID else {
                singles.append(event)
                continue
            }
            // Keep the next occurrence (or the latest past one) per series.
            if let kept = bySeries[series] {
                let keptFuture = kept.end > current
                if (event.end > current && (!keptFuture || event.start < kept.start))
                    || (!keptFuture && event.start > kept.start)
                {
                    bySeries[series] = event
                }
            } else {
                bySeries[series] = event
            }
        }
        let candidates = (singles + bySeries.values).sorted { $0.start < $1.start }
        return try EntityResolver.resolve(
            selector, in: candidates, type: "event", id: \.id, name: \.title,
            detail: { [self] in EventOutput.when($0, zone: timeZone) + " · " + $0.calendarTitle }, policy: policy)
    }

    /// Events in `calendars` that overlap [start, end) and block time, excluding `ignoring`.
    func conflicts(start: Date, end: Date, calendars: [CalendarSnapshot], ignoring: Set<String> = []) throws
        -> [CalendarEventSnapshot]
    {
        guard !calendars.isEmpty else { return [] }
        return try read.fetchEvents(start: start, end: end, calendarIDs: calendars.map(\.id)).filter { event in
            !event.isAllDay && event.blocksTime && event.start < end && event.end > start
                && !ignoring.contains(event.id) && !ignoring.contains(event.nativeID)
        }
    }
}
