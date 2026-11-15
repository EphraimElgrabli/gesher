import GesherPlatform
import Foundation

/// Reads calendars, accounts and event occurrences from CalendarDaemon. Every call re-reads
/// native state; nothing is cached between calls.
public final class CalendarReadRepository: @unchecked Sendable {
    let runtime: CalendarRuntime

    public init(runtime: CalendarRuntime) {
        self.runtime = runtime
    }

    static let eventKeys = [
        "unlocalizedTitle", "startDateRaw", "endDateRaw", "isAllDay", "startTimeZoneName", "endTimeZoneName",
        "structuredLocationWithoutPrediction", "notes", "URLString", "calendar", "hasRecurrenceRules",
        "recurrenceRulesSet", "allAlarmsSet", "availability", "travelTime", "attendeesRaw", "organizer",
        "selfParticipantStatusRaw", "selfAttendee", "originalItem", "originalStartDate", "uniqueID",
        "ekExceptionDates", "detachedItems",
    ]
    static let calendarKeys = ["UUID", "unlocalizedTitle", "colorStringRaw", "source", "allowedEntities", "flags"]
    static let sourceKeys = ["title", "sourceTypeRaw", "disabled"]

    // MARK: Accounts and calendars

    public func fetchSources() throws -> [CalendarSourceSnapshot] {
        try runtime.session { try sources($0) }
    }

    func sources(_ session: CalendarSession) throws -> [CalendarSourceSnapshot] {
        try session.fetchAll("CADDatabaseGetSourcesWithFaultedProperties:reply:", keys: Self.sourceKeys).map { source in
            guard let id = source.identifier, let title = source.properties["title"] as? String else {
                throw PlatformError.fetchFailed("CalendarDaemon source is missing required properties.")
            }
            return CalendarSourceSnapshot(
                id: id, title: title, sourceType: source.number("sourceTypeRaw")?.intValue ?? 0,
                disabled: source.number("disabled")?.boolValue ?? false)
        }
    }

    /// Event calendars (reminder-only lists are skipped), with account, kind, writability and default.
    public func fetchCalendars() throws -> [CalendarSnapshot] {
        try runtime.session { try calendars($0) }
    }

    func calendars(_ session: CalendarSession) throws -> [CalendarSnapshot] {
        let sources = Dictionary(uniqueKeysWithValues: try self.sources(session).map { ($0.id, $0) })
        let defaultID = try? session.defaultCalendarID()
        return try session.fetchAll("CADDatabaseGetCalendarsWithFaultedProperties:reply:", keys: Self.calendarKeys)
            .compactMap { calendar in
                // CalendarDaemon also returns reminder lists. Bit 2 of allowedEntities is events.
                guard let entities = calendar.number("allowedEntities") else {
                    throw PlatformError.fetchFailed("CalendarDaemon calendar has no entity mask.")
                }
                guard entities.intValue & 4 != 0 else { return nil }
                guard let id = calendar.identifier, let title = calendar.properties["unlocalizedTitle"] as? String
                else {
                    throw PlatformError.fetchFailed("CalendarDaemon calendar is missing its identifier or title.")
                }
                let source = calendar.relatedIdentifier("source").flatMap { sources[$0] }
                let flags = calendar.number("flags")?.intValue ?? 0
                let kind = CalendarSnapshot.kind(sourceType: source?.sourceType, flags: flags)
                return CalendarSnapshot(
                    id: id, title: title, sourceID: source?.id, sourceTitle: source?.title ?? "",
                    colorHex: calendar.string("colorStringRaw"), kind: kind,
                    writable: CalendarSnapshot.writable(kind: kind, flags: flags), isDefault: id == defaultID)
            }
    }

    public func fetchCalendar(id: String) throws -> CalendarSnapshot {
        guard let calendar = try fetchCalendars().first(where: { $0.id == id }) else {
            throw PlatformError.objectNotFound(type: "calendar", id: id)
        }
        return calendar
    }

    // MARK: Events

    /// Occurrences overlapping [start, end), sorted by start. `calendarIDs` nil means all calendars.
    public func fetchEvents(start: Date, end: Date, calendarIDs: [String]? = nil) throws -> [CalendarEventSnapshot] {
        guard end > start else { throw AgentError.invalid("The end of the range must be after its start.") }
        return try runtime.session { session in
            let calendars = try self.calendars(session)
            var events: [CalendarEventSnapshot] = []
            // The daemon predicate is limited to about a year; query longer ranges in chunks.
            var chunkStart = start
            var seen = Set<String>()
            while chunkStart < end {
                let chunkEnd = min(end, chunkStart.addingTimeInterval(86400 * 360))
                let ids = try calendarIDs.map {
                    try $0.map {
                        try CalendarSession.objectID($0, entity: "Calendar", type: CalendarEntityType.calendar)
                    }
                }
                let found = try session.occurrences(start: chunkStart, end: chunkEnd, calendars: ids)
                for event in try snapshots(found, calendars: calendars, session: session)
                where seen.insert(event.id).inserted {
                    events.append(event)
                }
                chunkStart = chunkEnd
            }
            return events.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        }
    }

    /// One event or occurrence by id (`native` or `native#epoch`).
    public func fetchEvent(id: String) throws -> CalendarEventSnapshot {
        try runtime.session { try event(id: id, session: $0) }
    }

    func event(id: String, session: CalendarSession) throws -> CalendarEventSnapshot {
        let (native, occurrence) = try Self.split(id)
        let object = try CalendarSession.objectID(native, entity: "Event", type: CalendarEntityType.event)
        guard try session.exists(object) else { throw PlatformError.objectNotFound(type: "event", id: id) }
        guard
            let event = try snapshots([(object, occurrence)], calendars: calendars(session), session: session).first
        else { throw PlatformError.objectNotFound(type: "event", id: id) }
        return event
    }

    /// The raw native entity (used by writes to reach related object IDs).
    func nativeEvent(_ nativeID: String, session: CalendarSession) throws -> NativeCalendarEntity {
        let object = try CalendarSession.objectID(nativeID, entity: "Event", type: CalendarEntityType.event)
        guard try session.exists(object), let entity = try session.properties([object], keys: Self.eventKeys).first
        else { throw PlatformError.objectNotFound(type: "event", id: nativeID) }
        return entity
    }

    static func split(_ id: String) throws -> (native: String, occurrence: Date?) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: "#")
        switch parts.count {
        case 1: return (trimmed, nil)
        case 2:
            guard let seconds = Double(parts[1]) else { break }
            return (parts[0], Date(timeIntervalSince1970: seconds))
        default: break
        }
        throw AgentError.invalid("'\(id)' is not an event id.", hint: "Use an id returned by agenda or event search.")
    }

    // MARK: Snapshot assembly

    func snapshots(
        _ found: [(id: AnyObject, occurrence: Date?)], calendars: [CalendarSnapshot], session: CalendarSession
    ) throws -> [CalendarEventSnapshot] {
        if found.isEmpty { return [] }
        let entities = try session.properties(found.map(\.id), keys: Self.eventKeys)
        let related = try RelatedEntities(entities, session: session)
        let calendarTitles = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.title) })
        return try zip(entities, found).map { entity, item in
            try snapshot(entity, occurrence: item.occurrence, related: related, calendarTitles: calendarTitles)
        }
    }

    private func snapshot(
        _ entity: NativeCalendarEntity, occurrence: Date?, related: RelatedEntities, calendarTitles: [String: String]
    ) throws -> CalendarEventSnapshot {
        guard let nativeID = entity.identifier, let rawStart = entity.date("startDateRaw"),
            let rawEnd = entity.date("endDateRaw"), let calendarID = entity.relatedIdentifier("calendar")
        else { throw PlatformError.fetchFailed("CalendarDaemon event is missing required properties.") }
        let allDay = entity.number("isAllDay")?.boolValue ?? false
        let zoneName = entity.string("startTimeZoneName")
        let isSeries = entity.number("hasRecurrenceRules")?.boolValue ?? false
        let start = occurrence ?? rawStart
        let end = start.addingTimeInterval(rawEnd.timeIntervalSince(rawStart))
        let seriesID = isSeries ? nativeID : entity.relatedIdentifier("originalItem")
        let id = isSeries && occurrence != nil ? nativeID + "#" + String(Int64(start.timeIntervalSince1970)) : nativeID
        let days = allDay ? EventDates.allDayRange(start: start, end: end, zoneName: zoneName) : nil
        let selfAttendee = entity.relatedIdentifier("selfAttendee").flatMap { related.attendees[$0] }
        return CalendarEventSnapshot(
            id: id, nativeID: nativeID, calendarID: calendarID, calendarTitle: calendarTitles[calendarID] ?? "",
            title: entity.string("unlocalizedTitle") ?? "", start: start, end: end, isAllDay: allDay,
            startDay: days?.first, endDay: days?.last, timeZone: EventDates.isFloating(zoneName) ? nil : zoneName,
            location: entity.relatedIdentifier("structuredLocationWithoutPrediction").flatMap { related.locations[$0] },
            notes: entity.string("notes"), url: entity.string("URLString"),
            availability: entity.number("availability").flatMap { EventAvailability(rawValue: $0.intValue) },
            travelTimeSeconds: entity.number("travelTime").map(\.doubleValue).flatMap { $0 > 0 ? $0 : nil },
            alerts: entity.related("allAlarmsSet").compactMap { try? CalendarSession.string($0) }
                .compactMap { related.alarms[$0] }
                .sorted {
                    ($0.absoluteDate?.timeIntervalSince1970 ?? 0, $0.relativeOffsetSeconds ?? 0) > (
                        $1.absoluteDate?.timeIntervalSince1970 ?? 0, $1.relativeOffsetSeconds ?? 0
                    )
                },
            recurrence: isSeries
                ? entity.related("recurrenceRulesSet").compactMap { try? CalendarSession.string($0) }
                    .compactMap { related.rules[$0] }.first : nil,
            seriesID: seriesID,
            occurrenceDate: seriesID == nil
                ? nil : (isSeries ? occurrence ?? rawStart : entity.date("originalStartDate") ?? start),
            attendees: entity.related("attendeesRaw").compactMap { try? CalendarSession.string($0) }
                .compactMap { related.attendees[$0] },
            organizer: entity.relatedIdentifier("organizer").flatMap { related.organizers[$0] },
            selfStatus: selfAttendee?.status
                ?? entity.number("selfParticipantStatusRaw").flatMap { ParticipantStatus(rawValue: $0.intValue) }
                .flatMap { $0 == .unknown ? nil : $0 })
    }
}

/// Related rows (locations, alarms, rules, attendees, organizers) fetched once per batch of events.
struct RelatedEntities {
    var locations: [String: CalendarLocationSnapshot] = [:]
    var alarms: [String: CalendarAlertSnapshot] = [:]
    var rules: [String: RecurrenceRule] = [:]
    var attendees: [String: CalendarAttendeeSnapshot] = [:]
    var organizers: [String: CalendarAttendeeSnapshot] = [:]

    init(_ events: [NativeCalendarEntity], session: CalendarSession) throws {
        func fetch(_ key: String, _ keys: [String]) throws -> [(String, NativeCalendarEntity)] {
            let ids = events.flatMap { $0.related(key) }
            return try session.properties(ids, keys: keys).compactMap { entity in
                entity.identifier.map { ($0, entity) }
            }
        }
        for (id, row) in try fetch(
            "structuredLocationWithoutPrediction", ["title", "address", "latitude", "longitude"])
        {
            guard let title = row.string("title") else { continue }
            let latitude = row.number("latitude")?.doubleValue
            let longitude = row.number("longitude")?.doubleValue
            let hasCoordinates = latitude != nil && longitude != nil && !(latitude == 0 && longitude == 0)
            locations[id] = CalendarLocationSnapshot(
                title: title, address: row.string("address"), latitude: hasCoordinates ? latitude : nil,
                longitude: hasCoordinates ? longitude : nil)
        }
        for (id, row) in try fetch("allAlarmsSet", ["relativeOffset", "absoluteDate", "type"]) {
            alarms[id] = CalendarAlertSnapshot(
                id: id, relativeOffsetSeconds: row.number("relativeOffset")?.doubleValue,
                absoluteDate: row.date("absoluteDate"), type: row.number("type")?.intValue ?? 0)
        }
        for (id, row) in try fetch("recurrenceRulesSet", ["frequencyRaw", "interval", "endDate", "count", "specifier"])
        {
            rules[id] = RecurrenceRule(
                nativeFrequency: row.number("frequencyRaw")?.intValue ?? 0,
                interval: row.number("interval")?.intValue ?? 1, specifier: row.string("specifier"),
                count: row.number("count")?.intValue, until: row.date("endDate"))
        }
        let personKeys = [
            "displayNameRaw", "emailAddress", "URLString", "statusRaw", "participantRole", "isCurrentUser",
        ]
        for (id, row) in try fetch("attendeesRaw", personKeys) {
            attendees[id] = Self.person(id, row)
        }
        for (id, row) in try fetch("selfAttendee", personKeys) where attendees[id] == nil {
            attendees[id] = Self.person(id, row)
        }
        for (id, row) in try fetch("organizer", ["displayNameRaw", "emailAddress", "URLString", "isCurrentUser"]) {
            organizers[id] = Self.person(id, row)
        }
    }

    static func person(_ id: String, _ row: NativeCalendarEntity) -> CalendarAttendeeSnapshot {
        var email = row.string("emailAddress")
        if email == nil, let url = row.string("URLString"), url.lowercased().hasPrefix("mailto:") {
            email = String(url.dropFirst(7))
        }
        return CalendarAttendeeSnapshot(
            id: id, name: row.string("displayNameRaw"), email: email,
            status: ParticipantStatus(rawValue: row.number("statusRaw")?.intValue ?? 0) ?? .unknown,
            role: row.number("participantRole")?.intValue ?? 1,
            isCurrentUser: row.number("isCurrentUser")?.boolValue ?? false)
    }
}

/// All-day and floating-time conventions of CalendarDatabase.
public enum EventDates {
    public static let floating = "_float"

    public static func isFloating(_ zoneName: String?) -> Bool {
        zoneName == nil || zoneName == floating || TimeZone(identifier: zoneName!) == nil
    }

    /// Floating dates are stored as wall-clock times in GMT.
    static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }

    /// First and last (inclusive) day of an all-day event as `yyyy-MM-dd`.
    static func allDayRange(start: Date, end: Date, zoneName: String?) -> [String] {
        let zone = isFloating(zoneName) ? TimeZone(identifier: "GMT")! : TimeZone(identifier: zoneName!)!
        let last = end.addingTimeInterval(-1) < start ? start : end.addingTimeInterval(-1)
        return [DateOutput.day(start, timeZone: zone), DateOutput.day(last, timeZone: zone)]
    }

    /// Native start/end for an all-day event covering `firstDay...lastDay` (days as calendar dates).
    /// CalendarDatabase stores an all-day end as the last second of the last day (a one-day event
    /// lasts 86399 s); an end at the next midnight is stored as the end of that next day instead.
    public static func allDayNative(first: DateComponents, last: DateComponents) -> (start: Date, end: Date)? {
        guard let start = gmt.date(from: first), let lastDay = gmt.date(from: last), lastDay >= start,
            let end = gmt.date(byAdding: .day, value: 1, to: lastDay)
        else { return nil }
        return (start, end.addingTimeInterval(-1))
    }

    /// The local calendar day (in `zone`) of an instant, as components.
    public static func day(of date: Date, in zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }
}
