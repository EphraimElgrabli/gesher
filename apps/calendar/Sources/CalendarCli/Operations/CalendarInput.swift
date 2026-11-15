import GesherKit
import GesherPlatform
import CalendarCore
import Foundation

/// A natural date kept as text: validated while decoding (so bad input fails before Calendar is
/// touched) and resolved later in the event's own time zone when one is given.
struct DateText: Decodable, Sendable, Equatable {
    let text: String

    init(_ text: String) throws {
        self.text = text
        _ = try DateInput().parse(text)
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do { try self.init(text) } catch let error as AgentError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.message, underlyingError: error))
        }
    }

    func resolve(_ input: DateInput, zone: TimeZone? = nil) throws -> ResolvedDate {
        try DateInput(timeZone: zone ?? input.timeZone, now: input.now).parse(text)
    }
}

/// An alert: minutes before the start (`15`, `15m`, `2h`, `1d`, `1w`, `0` = at start) or an
/// absolute time (`2026-11-05 08:00`, `tomorrow 7:30`). `none` clears all alerts.
struct AlertText: Decodable, Sendable, Equatable {
    let spec: AlertSpec?  // nil = none

    init(_ text: String, dateInput: DateInput = DateInput()) throws {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "none" {
            spec = nil
            return
        }
        let body = trimmed.hasSuffix(" before") ? String(trimmed.dropLast(7)) : trimmed
        if let minutes = Self.minutes(body) {
            guard (0...40320).contains(minutes) else {
                throw AgentError.invalid("Alerts can be at most 4 weeks before the start.")
            }
            spec = .before(minutes: minutes)
            return
        }
        do {
            spec = .at(try dateInput.parse(text).date)
        } catch {
            throw AgentError.invalid(
                "Unrecognized alert '\(text)'.",
                hint:
                    "Use minutes before the start (15, 15m, 2h, 1d, 1w, 0 = at start), a time (2026-11-05 08:00), or none."
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text: String
        if let string = try? container.decode(String.self) {
            text = string
        } else {
            text = String(try container.decode(Int.self))
        }
        do { try self.init(text) } catch let error as AgentError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.message, underlyingError: error))
        }
    }

    static func minutes(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        guard let unit = text.last, let value = Int(text.dropLast().trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        switch unit {
        case "m": return value
        case "h": return value * 60
        case "d": return value * 1440
        case "w": return value * 10080
        default: return nil
        }
    }

    static func specs(_ texts: [AlertText]?) throws -> [AlertSpec]? {
        guard let texts else { return nil }
        if texts.contains(where: { $0.spec == nil }) {
            guard texts.count == 1 else { throw AgentError.invalid("'none' cannot be combined with other alerts.") }
            return []
        }
        let specs = texts.compactMap(\.spec)
        guard specs.count <= 10 else { throw AgentError.invalid("At most 10 alerts per event.") }
        return specs
    }
}

/// A color validated while decoding.
struct ColorText: Decodable, Sendable {
    let hex: String

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do { hex = try CalendarColor.hex(text)! } catch let error as AgentError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.message, underlyingError: error))
        }
    }
}

/// Runs a check while decoding so its `AgentError` surfaces as invalid input.
func decodingCheck(_ decoder: Decoder, _ body: () throws -> Void) throws {
    do { try body() } catch let error as AgentError {
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: error.message, underlyingError: error))
    }
}

/// `#RRGGBB` or a Calendar color name.
enum CalendarColor {
    static let named = [
        "red": "#FF2968", "orange": "#FF9500", "yellow": "#FFCC00", "green": "#63DA38", "blue": "#1BADF8",
        "purple": "#CC73E1", "brown": "#A2845E", "gray": "#8E8E93", "grey": "#8E8E93",
    ]

    static func hex(_ text: String?) throws -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let named = named[trimmed.lowercased()] { return named }
        let value = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
        guard value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
            throw AgentError.invalid(
                "Unrecognized color '\(text)'.",
                hint: "Use #RRGGBB or one of: " + named.keys.sorted().joined(separator: ", ") + ".")
        }
        return value.uppercased()
    }
}

/// The fields shared by event create and update (property names == Param names).
struct EventFields: Decodable, Sendable {
    var title: String?
    var start: DateText?
    var end: DateText?
    var duration: Int?
    var allDay: Bool?
    var calendar: String?
    var timeZone: String?
    var location: String?
    var address: String?
    var coordinates: String?
    var url: String?
    var notes: String?
    var availability: String?
    var travelTime: Int?
    var alerts: [AlertText]?
    var `repeat`: String?
    var repeatDays: [String]?
    var repeatInterval: Int?
    var repeatCount: Int?
    var repeatUntil: DateText?
    var rejectConflicts: Bool?

    static let params: [Param] = [
        .date("start", "Start, e.g. 'tomorrow 10:00'. A day without a time makes an all-day event."),
        .date("end", "End time; for all-day events the last day (inclusive). Default: start + duration."),
        .integer("duration", "Length in minutes when no end is given. Default 60.", min: 1, max: 60 * 24 * 14),
        Param("allDay", .boolean, "All-day event (days only)."),
        .string("calendar", "Calendar name or id. Default: your default calendar."),
        .string("timeZone", "IANA time zone the times are in, e.g. Europe/London. Default: yours."),
        .string("location", "Location title. Empty clears it."),
        .string("address", "Street address for the location."),
        .string("coordinates", "Location coordinates 'lat,lon'."),
        .string("url", "Web link (http/https). Empty clears it."),
        .string("notes", "Notes. Empty clears them."),
        .choice("availability", ["busy", "free", "tentative", "unavailable"], "Show as. Default busy."),
        .integer("travelTime", "Travel time before the event in minutes (0 clears).", min: 0, max: 1440),
        .list("alerts", "Alerts: minutes before (15, 2h, 1d) or a time ('2026-11-05 08:00'); 'none' clears."),
        .string(
            "repeat",
            "daily, weekly, monthly, yearly, weekdays, none, or an RRULE like FREQ=MONTHLY;BYDAY=2TU."),
        .list("repeatDays", "Days for weekly/monthly repeats: MO, WE; 2TU = second Tuesday; -1FR = last Friday."),
        .integer("repeatInterval", "Repeat every N days/weeks/months/years.", min: 1, max: 999),
        .integer("repeatCount", "Number of occurrences.", min: 1, max: 9999),
        .date("repeatUntil", "Last day the repeat may occur."),
        .boolean("rejectConflicts", "Fail instead of warning when the time overlaps busy events."),
    ]

    var availabilityValue: EventAvailability? { availability.flatMap(EventAvailability.init(name:)) }

    /// Checks everything that does not need Calendar data, so bad input fails before any
    /// private framework is touched.
    func check() throws {
        _ = try zone()
        if let location, !location.isEmpty { _ = try locationInput() }
        _ = try validatedURL()
        _ = try recurrence(DateInput(), base: RecurrenceRule(frequency: .daily))
        _ = try AlertText.specs(alerts)
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AgentError.invalid("The title cannot be empty.")
        }
    }

    func zone() throws -> TimeZone? {
        guard let timeZone else { return nil }
        guard let zone = TimeZone(identifier: timeZone) else {
            throw AgentError.invalid("Unknown time zone '\(timeZone)'.", hint: "Use an IANA name like Asia/Jerusalem.")
        }
        return zone
    }

    func locationInput() throws -> LocationInput? {
        guard let location, !location.trimmingCharacters(in: .whitespaces).isEmpty else {
            if address != nil || coordinates != nil {
                throw AgentError.invalid("address and coordinates need a location title.")
            }
            return nil
        }
        var input = LocationInput(title: location.trimmingCharacters(in: .whitespaces), address: address)
        if let coordinates {
            let parts = coordinates.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let latitude = parts[0], let longitude = parts[1], (-90...90).contains(latitude),
                (-180...180).contains(longitude)
            else { throw AgentError.invalid("coordinates must be 'lat,lon', e.g. 32.0853,34.7818.") }
            input.latitude = latitude
            input.longitude = longitude
        }
        return input
    }

    func validatedURL() throws -> String? {
        guard let url else { return nil }
        if url.isEmpty { return "" }
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
            parsed.host != nil
        else { throw AgentError.invalid("url must be an absolute http or https link.") }
        return url
    }

    /// `.none` = untouched; `.some(nil)` = remove the repeat.
    func recurrence(_ input: DateInput, base: RecurrenceRule? = nil) throws -> RecurrenceRule?? {
        let touched =
            self.repeat != nil || repeatDays != nil || repeatInterval != nil || repeatCount != nil
            || repeatUntil != nil
        guard touched else { return .none }
        if self.repeat?.lowercased() == "none" { return .some(nil) }
        guard var rule = try self.repeat.map({ try RecurrenceRule.parse($0, dateInput: input) }) ?? base else {
            throw AgentError.invalid("repeatDays, repeatInterval, repeatCount and repeatUntil need repeat.")
        }
        if let repeatDays {
            rule.days = try repeatDays.flatMap { $0.split(separator: ",") }.map {
                guard let day = RecurrenceRule.Day.parse(String($0)) else {
                    throw AgentError.invalid("Unrecognized repeat day '\($0)'.", hint: "Use MO, TU, ... or 2TU, -1FR.")
                }
                return day
            }
        }
        if let repeatInterval { rule.interval = repeatInterval }
        if let repeatCount {
            rule.count = repeatCount
            rule.until = nil
        }
        if let repeatUntil {
            let resolved = try repeatUntil.resolve(input)
            rule.until = resolved.hasTime ? resolved.date : resolved.date.addingTimeInterval(86400 - 1)
            rule.count = nil
        }
        try rule.validate()
        return .some(rule)
    }

    static func attendees(_ values: [String]?) throws -> [AttendeeInput] {
        try (values ?? []).map { value in
            var name: String?
            var email = value.trimmingCharacters(in: .whitespaces)
            if let open = email.lastIndex(of: "<"), email.hasSuffix(">") {
                name = String(email[..<open]).trimmingCharacters(in: .whitespaces)
                email = String(email[email.index(after: open)..<email.index(before: email.endIndex)])
            }
            guard email.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil else {
                throw AgentError.invalid("'\(value)' is not an email address.")
            }
            return AttendeeInput(email: email, name: name?.isEmpty == false ? name : nil)
        }
    }
}

/// Native start/end for user dates. Timed events keep the instant; all-day events are stored
/// as floating days.
struct EventTimes {
    let start: Date
    let end: Date
    let allDay: Bool

    static func make(
        start: ResolvedDate, end: ResolvedDate?, duration: Int?, allDay requested: Bool?, zone: TimeZone
    ) throws -> EventTimes {
        let allDay = requested ?? !start.hasTime
        if allDay {
            let first = EventDates.day(of: start.date, in: zone)
            let last = end.map { EventDates.day(of: $0.date, in: zone) } ?? first
            guard let native = EventDates.allDayNative(first: first, last: last) else {
                throw AgentError.invalid("The last day must not be before the first day.")
            }
            return EventTimes(start: native.start, end: native.end, allDay: true)
        }
        let endDate = end?.date ?? start.date.addingTimeInterval(Double(duration ?? 60) * 60)
        guard endDate > start.date else {
            throw AgentError.invalid("The event must end after it starts.", hint: "Check end, or pass duration.")
        }
        return EventTimes(start: start.date, end: endDate, allDay: false)
    }
}

/// JSON snapshots written before bulk destructive operations, so they can be restored by hand.
struct BackupStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/gesher/backups")
    }

    /// More than this many items deleted at once are snapshotted first.
    static let threshold = 5

    func save<T: Encodable>(_ label: String, _ payload: T) throws -> String {
        try PrivateStorage.createDirectory(directory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent(
            "calendar-\(label)-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try PrivateStorage.write(try encoder.encode(payload), to: url)
        } catch {
            throw AgentError(
                code: "backup_failed",
                message: "Could not save a backup before deleting: \(error.localizedDescription)",
                hint: "Nothing was deleted. Fix the backup directory or delete fewer items at once.")
        }
        return url.path
    }
}
