import GesherPlatform
import CalendarCore
import Foundation

/// Agent-facing output models: user fields only, local times with offsets, optionals omitted.

struct CalendarOutput: Encodable, Sendable {
    let id: String
    let title: String
    let account: String
    let kind: String
    let color: String?
    let writable: Bool
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey { case id, title, account, kind, color, writable, isDefault = "default" }

    init(_ calendar: CalendarSnapshot) {
        id = calendar.id
        title = calendar.title
        account = calendar.sourceTitle
        kind = calendar.kind.rawValue
        color = calendar.colorHex
        writable = calendar.writable
        isDefault = calendar.isDefault ? true : nil
    }
}

struct PersonOutput: Encodable, Sendable {
    let name: String?
    let email: String?
    let status: String?

    init(_ person: CalendarAttendeeSnapshot, status: Bool = true) {
        name = person.name
        email = person.email
        self.status = status ? person.status.name : nil
    }
}

struct EventOutput: Encodable, Sendable {
    let id: String
    let title: String
    let calendar: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String?
    let recurring: Bool
    let notes: String?
    let url: String?
    let alerts: [String]?
    let attendees: [PersonOutput]?
    // Detail fields, only when they carry information.
    let timeZone: String?
    let availability: String?
    let travelTime: Int?
    let `repeat`: String?
    let address: String?
    let coordinates: String?
    let organizer: PersonOutput?
    let myStatus: String?

    init(_ event: CalendarEventSnapshot, zone: TimeZone, detail: Bool = false) {
        id = event.id
        title = event.title
        calendar = event.calendarTitle
        if event.isAllDay, let first = event.startDay, let last = event.endDay {
            start = first
            end = last
        } else {
            start = DateOutput.iso(event.start, timeZone: zone)
            end = DateOutput.iso(event.end, timeZone: zone)
        }
        allDay = event.isAllDay
        location = event.location?.title
        recurring = event.isRecurring
        notes = event.notes
        url = event.url
        alerts = event.alerts.isEmpty ? nil : event.alerts.map { Self.alert($0, zone: zone) }
        let others = event.attendees.filter { !$0.isCurrentUser || event.organizer?.isCurrentUser == true }
        attendees = others.isEmpty ? nil : others.map { PersonOutput($0) }
        let invited = event.organizer.map { !$0.isCurrentUser } ?? false
        myStatus = invited ? event.selfStatus.map(\.name) : nil
        guard detail else {
            timeZone = nil
            availability = nil
            travelTime = nil
            self.repeat = nil
            address = nil
            coordinates = nil
            organizer = nil
            return
        }
        timeZone = event.timeZone.flatMap { name in
            TimeZone(identifier: name).flatMap {
                $0.secondsFromGMT(for: event.start) == zone.secondsFromGMT(for: event.start) ? nil : name
            }
        }
        availability = event.availability.flatMap { $0 == .busy ? nil : $0.name }
        travelTime = event.travelTimeSeconds.map { Int(($0 / 60).rounded()) }
        self.repeat = event.recurrence?.rrule
        address = event.location?.address
        coordinates = event.location.flatMap { location in
            guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
            return String(format: "%.5f,%.5f", latitude, longitude)
        }
        organizer = event.organizer.map { PersonOutput($0, status: false) }
    }

    static func alert(_ alert: CalendarAlertSnapshot, zone: TimeZone) -> String {
        switch alert.spec {
        case .at(let date): return DateOutput.iso(date, timeZone: zone)
        case .before(let minutes):
            let magnitude = abs(minutes)
            let text: String
            if magnitude == 0 {
                text = "0m"
            } else if magnitude % 10080 == 0 {
                text = "\(magnitude / 10080)w"
            } else if magnitude % 1440 == 0 {
                text = "\(magnitude / 1440)d"
            } else if magnitude % 60 == 0 {
                text = "\(magnitude / 60)h"
            } else {
                text = "\(magnitude)m"
            }
            return minutes < 0 ? text + " after" : text
        }
    }

    /// A short human time for candidate lists, e.g. `2026-11-05 14:00`.
    static func when(_ event: CalendarEventSnapshot, zone: TimeZone) -> String {
        if event.isAllDay { return event.startDay ?? DateOutput.day(event.start, timeZone: zone) }
        return String(DateOutput.iso(event.start, timeZone: zone).prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

struct RangeOutput: Encodable, Sendable {
    let from: String
    let to: String

    init(_ start: Date, _ end: Date, zone: TimeZone) {
        from = DateOutput.iso(start, timeZone: zone)
        to = DateOutput.iso(end, timeZone: zone)
    }
}

struct AgendaOutput: Encodable, Sendable {
    let range: RangeOutput
    let events: [EventOutput]
}

struct EventsOutput: Encodable, Sendable {
    let events: [EventOutput]
}

/// A written event plus any busy events it overlaps (a warning, unless rejected).
struct SavedEventOutput: Encodable, Sendable {
    let event: EventOutput
    let conflicts: [EventOutput]?
}

struct DeletedEventOutput: Encodable, Sendable {
    let id: String
    let title: String
    let start: String
    let scope: String?
}

/// A batch result plus the path of the snapshot saved before bulk deletes.
struct BatchOutput<Item: Encodable & Sendable>: Encodable, Sendable, PartialFailureReporting {
    let results: [BatchResult<Item>.Entry]
    let succeeded: Int
    let failed: Int
    let backup: String?

    init(_ batch: BatchResult<Item>, backup: String?) {
        results = batch.results
        succeeded = batch.succeeded
        failed = batch.failed
        self.backup = backup
    }
}

struct SlotOutput: Encodable, Sendable {
    let start: String
    let end: String
    let minutes: Int
}

struct FreeSlotsOutput: Encodable, Sendable {
    let range: RangeOutput
    let duration: Int
    let workingHours: String
    let calendars: [String]
    let slots: [SlotOutput]
}

struct FreeBusyOutput: Encodable, Sendable {
    let range: RangeOutput
    let calendars: [String]
    let busy: [SlotOutput]
    let free: [SlotOutput]
}

struct CalendarsOutput: Encodable, Sendable {
    let calendars: [CalendarOutput]
}

struct AccountOutput: Encodable, Sendable {
    let id: String
    let title: String
    let kind: String
    let enabled: Bool

    init(_ source: CalendarSourceSnapshot) {
        id = source.id
        title = source.title
        kind =
            switch source.sourceType {
            case 0: "local"
            case 1: "exchange"
            case 2: "caldav"
            case 3: "icloud"
            case 4: "subscribed"
            case 5: "birthdays"
            default: "other"
            }
        enabled = !source.disabled
    }
}

struct AccountsOutput: Encodable, Sendable {
    let accounts: [AccountOutput]
}

struct DeletedCalendarOutput: Encodable, Sendable {
    let id: String
    let title: String
    let deletedEvents: Int
    let backup: String?
}

/// `--format pretty` renderers.
enum CalendarPretty {
    static func line(_ event: EventOutput) -> String {
        let time: String
        if event.allDay {
            time = event.start == event.end ? "all day" : "\(event.start) → \(event.end)"
        } else {
            time = "\(event.start.dropFirst(11).prefix(5))–\(event.end.dropFirst(11).prefix(5))"
        }
        var text = "  \(time)  \(event.title)"
        if let location = event.location { text += " @ \(location)" }
        text += "  [\(event.calendar)]"
        if event.recurring { text += " ↻" }
        if let status = event.myStatus { text += " (\(status))" }
        return text
    }

    static func agenda(_ output: AgendaOutput) -> String {
        if output.events.isEmpty { return "No events from \(output.range.from) to \(output.range.to)." }
        var lines: [String] = []
        var day = ""
        for event in output.events {
            let eventDay = String(event.start.prefix(10))
            if eventDay != day {
                day = eventDay
                lines.append(day)
            }
            lines.append(line(event))
        }
        return lines.joined(separator: "\n")
    }

    static func slots(_ output: FreeSlotsOutput) -> String {
        if output.slots.isEmpty { return "No free slot of \(output.duration) minutes in \(output.workingHours)." }
        return output.slots.map {
            "  \($0.start.prefix(16).replacingOccurrences(of: "T", with: " "))–\($0.end.dropFirst(11).prefix(5)) (\($0.minutes)m)"
        }
        .joined(separator: "\n")
    }
}
