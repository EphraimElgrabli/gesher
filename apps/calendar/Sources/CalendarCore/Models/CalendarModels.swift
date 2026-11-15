import GesherPlatform
import Foundation

/// An account that holds calendars (iCloud, Exchange, On My Mac, Subscribed, Birthdays, ...).
public struct CalendarSourceSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// Native source type: 0 local, 1 Exchange, 2 CalDAV, 3 MobileMe/iCloud, 4 subscribed, 5 birthdays.
    public let sourceType: Int
    public let disabled: Bool

    public init(id: String, title: String, sourceType: Int, disabled: Bool) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.disabled = disabled
    }
}

/// What kind of calendar this is, derived from the source type and native flags.
public enum CalendarKind: String, Codable, Sendable {
    case local, icloud, caldav, exchange, subscribed, birthdays, holidays
}

public struct CalendarSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let sourceID: String?
    public let sourceTitle: String
    public let colorHex: String?
    public let kind: CalendarKind
    public let writable: Bool
    public let isDefault: Bool

    public init(
        id: String, title: String, sourceID: String? = nil, sourceTitle: String = "", colorHex: String? = nil,
        kind: CalendarKind = .local, writable: Bool = true, isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
        self.kind = kind
        self.writable = writable
        self.isDefault = isDefault
    }

    /// Native calendar flag bits (CalendarDatabase): read-only, immutable, subscribed, holiday.
    public static let readOnlyFlag = 0x1
    public static let immutableFlag = 0x4
    public static let subscribedFlag = 0x8
    public static let subscribedHolidayFlag = 0x1000
    public static let syncedHolidayFlag = 0x0100_0000

    public static func kind(sourceType: Int?, flags: Int) -> CalendarKind {
        if flags & (subscribedHolidayFlag | syncedHolidayFlag) != 0 { return .holidays }
        switch sourceType {
        case 5: return .birthdays
        case 4: return .subscribed
        case 1: return .exchange
        case 2: return flags & subscribedFlag != 0 ? .subscribed : .caldav
        case 3: return .icloud
        default: return flags & subscribedFlag != 0 ? .subscribed : .local
        }
    }

    public static func writable(kind: CalendarKind, flags: Int) -> Bool {
        guard flags & (readOnlyFlag | immutableFlag) == 0 else { return false }
        return ![.subscribed, .birthdays, .holidays].contains(kind)
    }
}

public struct CalendarAlertSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let relativeOffsetSeconds: Double?
    public let absoluteDate: Date?
    public let type: Int

    public init(id: String, relativeOffsetSeconds: Double?, absoluteDate: Date?, type: Int) {
        self.id = id
        self.relativeOffsetSeconds = relativeOffsetSeconds
        self.absoluteDate = absoluteDate
        self.type = type
    }
}

public struct CalendarLocationSnapshot: Codable, Sendable, Equatable {
    public let title: String
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(title: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Participant status as stored natively (EKParticipantStatus raw values).
public enum ParticipantStatus: Int, Codable, Sendable {
    case unknown = 0, pending, accepted, declined, tentative, delegated, completed, inProcess

    public var name: String {
        switch self {
        case .unknown: "unknown"
        case .pending: "pending"
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .delegated: "delegated"
        case .completed: "completed"
        case .inProcess: "in_process"
        }
    }
}

public struct CalendarAttendeeSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let email: String?
    public let status: ParticipantStatus
    /// 0 unknown, 1 required, 2 optional, 3 chair, 4 non-participant.
    public let role: Int
    public let isCurrentUser: Bool

    public init(
        id: String, name: String?, email: String?, status: ParticipantStatus, role: Int = 1, isCurrentUser: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.status = status
        self.role = role
        self.isCurrentUser = isCurrentUser
    }
}

/// Native event availability (EKEventAvailability raw values).
public enum EventAvailability: Int, Codable, Sendable, CaseIterable {
    case busy = 0, free = 1, tentative = 2, unavailable = 3

    public var name: String {
        switch self {
        case .busy: "busy"
        case .free: "free"
        case .tentative: "tentative"
        case .unavailable: "unavailable"
        }
    }

    public init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
        self = match
    }
}

/// One event occurrence as read from CalendarDaemon. Dates are absolute instants; all-day
/// events carry their days in `startDay`/`endDay` (inclusive) so no time zone shifts them.
public struct CalendarEventSnapshot: Codable, Sendable, Equatable {
    /// Stable id for this occurrence: the native id, plus `#<epoch>` for an occurrence of a series.
    public let id: String
    /// The native event entity (the series master for an undetached occurrence).
    public let nativeID: String
    public let calendarID: String
    public let calendarTitle: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let startDay: String?
    public let endDay: String?
    public let timeZone: String?
    public let location: CalendarLocationSnapshot?
    public let notes: String?
    public let url: String?
    public let availability: EventAvailability?
    public let travelTimeSeconds: Double?
    public let alerts: [CalendarAlertSnapshot]
    public let recurrence: RecurrenceRule?
    /// The series this occurrence belongs to, when it is part of one (master id).
    public let seriesID: String?
    /// The occurrence's original start, for occurrences of a series.
    public let occurrenceDate: Date?
    public let attendees: [CalendarAttendeeSnapshot]
    public let organizer: CalendarAttendeeSnapshot?
    public let selfStatus: ParticipantStatus?

    public init(
        id: String, nativeID: String? = nil, calendarID: String, calendarTitle: String, title: String, start: Date,
        end: Date, isAllDay: Bool = false, startDay: String? = nil, endDay: String? = nil, timeZone: String? = nil,
        location: CalendarLocationSnapshot? = nil, notes: String? = nil, url: String? = nil,
        availability: EventAvailability? = nil, travelTimeSeconds: Double? = nil, alerts: [CalendarAlertSnapshot] = [],
        recurrence: RecurrenceRule? = nil, seriesID: String? = nil, occurrenceDate: Date? = nil,
        attendees: [CalendarAttendeeSnapshot] = [], organizer: CalendarAttendeeSnapshot? = nil,
        selfStatus: ParticipantStatus? = nil
    ) {
        self.id = id
        self.nativeID = nativeID ?? id
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.startDay = startDay
        self.endDay = endDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.availability = availability
        self.travelTimeSeconds = travelTimeSeconds
        self.alerts = alerts
        self.recurrence = recurrence
        self.seriesID = seriesID
        self.occurrenceDate = occurrenceDate
        self.attendees = attendees
        self.organizer = organizer
        self.selfStatus = selfStatus
    }

    public var isRecurring: Bool { seriesID != nil || recurrence != nil }

    /// Busy for scheduling: not free, not declined by the user.
    public var blocksTime: Bool {
        availability != .free && selfStatus != .declined
    }
}

/// A requested alert: minutes before the start, or an absolute time.
public enum AlertSpec: Sendable, Equatable {
    case before(minutes: Int)
    case at(Date)
}

/// A requested structured location.
public struct LocationInput: Sendable, Equatable {
    public var title: String
    public var address: String?
    public var latitude: Double?
    public var longitude: Double?

    public init(title: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct AttendeeInput: Sendable, Equatable {
    public var email: String
    public var name: String?

    public init(email: String, name: String? = nil) {
        self.email = email
        self.name = name
    }
}

/// Everything a new event can carry. Dates are absolute; for all-day events start/end are
/// midnights of the first and the day after the last day in `timeZone`.
public struct EventDraft: Sendable {
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var timeZone: TimeZone
    public var location: LocationInput?
    public var notes: String?
    public var url: String?
    public var availability: EventAvailability?
    public var travelTimeSeconds: Double?
    public var alerts: [AlertSpec]?
    public var recurrence: RecurrenceRule?
    public var attendees: [AttendeeInput]

    public init(
        calendarID: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
        timeZone: TimeZone = .current, location: LocationInput? = nil, notes: String? = nil, url: String? = nil,
        availability: EventAvailability? = nil, travelTimeSeconds: Double? = nil, alerts: [AlertSpec]? = nil,
        recurrence: RecurrenceRule? = nil, attendees: [AttendeeInput] = []
    ) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.availability = availability
        self.travelTimeSeconds = travelTimeSeconds
        self.alerts = alerts
        self.recurrence = recurrence
        self.attendees = attendees
    }
}

/// A partial change. `nil` keeps the field; empty strings / empty lists clear it.
public struct EventChanges: Sendable {
    public var calendarID: String?
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool?
    public var timeZone: TimeZone?
    public var location: LocationInput?
    public var clearLocation = false
    public var notes: String?
    public var url: String?
    public var availability: EventAvailability?
    public var travelTimeSeconds: Double?
    public var alerts: [AlertSpec]?
    /// `.some(nil)` removes the recurrence.
    public var recurrence: RecurrenceRule??
    public var invite: [AttendeeInput] = []
    public var uninvite: [String] = []

    public init() {}

    public var isEmpty: Bool {
        calendarID == nil && title == nil && start == nil && end == nil && isAllDay == nil && timeZone == nil
            && location == nil && !clearLocation && notes == nil && url == nil && availability == nil
            && travelTimeSeconds == nil && alerts == nil && recurrence == nil && invite.isEmpty && uninvite.isEmpty
    }

    /// Changes that only make sense for the whole series.
    public var touchesRecurrence: Bool { recurrence != nil }
}

/// Which occurrences of a recurring event an edit or delete applies to.
public enum RecurrenceScope: String, Sendable, CaseIterable {
    case this, future, all
}
