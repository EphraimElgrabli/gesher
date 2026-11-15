import GesherPlatform
import Foundation

public struct ReminderAccountSnapshot: Codable, Sendable {
    public let id: String
    public let title: String
    public let isDefault: Bool?

    public init(id: String, title: String, isDefault: Bool?) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}

/// A list or a list group (folder). Groups hold lists but never reminders.
public struct ReminderListSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let accountID: String
    public let isGroup: Bool
    /// The group (folder) containing this list, if any.
    public let groupID: String?
    public let emoji: String?
    public let colorHex: String?
    public let isShared: Bool
    public let isSharedToMe: Bool
    public let sharedOwner: String?
    public let sharees: [ReminderShareeSnapshot]
    public let isPinned: Bool

    public init(
        id: String, title: String, accountID: String, isGroup: Bool = false, groupID: String? = nil,
        emoji: String? = nil, colorHex: String? = nil, isShared: Bool = false, isSharedToMe: Bool = false,
        sharedOwner: String? = nil, sharees: [ReminderShareeSnapshot] = [], isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.accountID = accountID
        self.isGroup = isGroup
        self.groupID = groupID
        self.emoji = emoji
        self.colorHex = colorHex
        self.isShared = isShared
        self.isSharedToMe = isSharedToMe
        self.sharedOwner = sharedOwner
        self.sharees = sharees
        self.isPinned = isPinned
    }
}

public struct ReminderShareeSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let address: String?
    /// ReminderKit sharee status, e.g. pending or accepted.
    public let status: String

    public init(id: String, name: String?, address: String?, status: String) {
        self.id = id
        self.name = name
        self.address = address
        self.status = status
    }
}

public struct ReminderSectionSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let listID: String
    public let title: String

    public init(id: String, listID: String, title: String) {
        self.id = id
        self.listID = listID
        self.title = title
    }
}

/// A due/alarm date as stored: date-only (all-day) values have no time and no time zone.
public struct ReminderDate: Codable, Sendable, Equatable {
    public let date: Date
    public let hasTime: Bool
    /// Present for timed values that carry a zone; nil for floating or date-only values.
    public let timeZone: String?

    public init(date: Date, hasTime: Bool, timeZone: String?) {
        self.date = date
        self.hasTime = hasTime
        self.timeZone = timeZone
    }

    /// `2026-11-05` for date-only values, else ISO 8601 with the user's offset.
    public func text(in zone: TimeZone = .current) -> String {
        hasTime ? DateOutput.iso(date, timeZone: zone) : DateOutput.day(date, timeZone: zone)
    }
}

public enum ReminderLocationProximity: String, Codable, Sendable, CaseIterable {
    case arriving
    case leaving

    public var reminderKitValue: Int {
        switch self {
        case .arriving: 1
        case .leaving: 2
        }
    }

    public init?(reminderKitValue: Int) {
        switch reminderKitValue {
        case 1: self = .arriving
        case 2: self = .leaving
        default: return nil
        }
    }
}

public struct ReminderLocationMutation: Sendable, Equatable {
    public let title: String
    public let address: String?
    public let latitude: Double
    public let longitude: Double
    public let radius: Double
    public let proximity: ReminderLocationProximity

    public init(
        title: String, address: String?, latitude: Double, longitude: Double, radius: Double = 100,
        proximity: ReminderLocationProximity = .arriving
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ReminderCLIError.invalidArgument("Location name cannot be empty.")
        }
        guard (-90...90).contains(latitude) else {
            throw ReminderCLIError.invalidArgument("Latitude must be between -90 and 90.")
        }
        guard (-180...180).contains(longitude) else {
            throw ReminderCLIError.invalidArgument("Longitude must be between -180 and 180.")
        }
        guard radius > 0, radius <= 100_000 else {
            throw ReminderCLIError.invalidArgument("Location radius must be greater than 0 and at most 100000 meters.")
        }
        self.title = normalizedTitle
        self.address = address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.proximity = proximity
    }
}

public enum ReminderAlarmSnapshot: Codable, Sendable, Equatable {
    case date(ReminderDate)
    case location(
        title: String?, address: String?, latitude: Double, longitude: Double, radius: Double, proximity: String)
    /// Seconds relative to the due date.
    case relative(seconds: Double)
}

/// The "Early Reminder" of the Reminders app: an alert at a fixed offset before the due date.
public struct ReminderEarlyAlert: Codable, Sendable, Equatable {
    public enum Unit: Int, Codable, Sendable, CaseIterable {
        case minute = 0
        case hour = 1
        case day = 2
        case week = 3
        case month = 4

        public var name: String {
            switch self {
            case .minute: "m"
            case .hour: "h"
            case .day: "d"
            case .week: "w"
            case .month: "mo"
            }
        }
    }

    public let unit: Unit
    /// How many units before the due date (positive).
    public let count: Int

    public init(unit: Unit, count: Int) {
        self.unit = unit
        self.count = count
    }

    /// Parses `15m`, `1h`, `2d`, `1w`, `1mo` (an amount before the due date).
    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " before", with: "").replacingOccurrences(of: " ", with: "")
        let digits = trimmed.prefix { $0.isNumber }
        let suffix = String(trimmed.dropFirst(digits.count))
        let units: [String: Unit] = [
            "m": .minute, "min": .minute, "mins": .minute, "minute": .minute, "minutes": .minute,
            "h": .hour, "hr": .hour, "hour": .hour, "hours": .hour,
            "d": .day, "day": .day, "days": .day,
            "w": .week, "week": .week, "weeks": .week,
            "mo": .month, "month": .month, "months": .month,
        ]
        guard let count = Int(digits), count > 0, count <= 1000, let unit = units[suffix] else {
            throw ReminderCLIError.invalidArgument(
                "Early alert must be an amount before the due date such as 15m, 1h, 2d, 1w or 1mo; got '\(text)'.")
        }
        self.init(unit: unit, count: count)
    }

    public var text: String { "\(count)\(unit.name)" }
}

public struct ReminderRecurrenceSnapshot: Codable, Sendable, Equatable {
    /// daily, weekly, monthly, yearly.
    public let frequency: String
    public let interval: Int
    /// 1 = Sunday ... 7 = Saturday.
    public let weekdays: [Int]
    public let daysOfMonth: [Int]
    public let endDate: Date?
    public let count: Int?

    public init(
        frequency: String, interval: Int, weekdays: [Int] = [], daysOfMonth: [Int] = [], endDate: Date? = nil,
        count: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.daysOfMonth = daysOfMonth
        self.endDate = endDate
        self.count = count
    }
}

public struct ReminderAttachmentSnapshot: Codable, Sendable, Equatable {
    /// Native attachment id (REMCDURLAttachment/REMCDImageAttachment/REMCDFileAttachment:UUID).
    public let id: String?
    /// url, image or file.
    public let kind: String
    public let url: String?
    public let uti: String?
    public let width: Int?
    public let height: Int?
    /// Bytes, for images and files.
    public let size: Int?
    /// The local file holding an image or file attachment, when ReminderKit has it on disk.
    public let fileURL: URL?

    public init(
        id: String? = nil, kind: String, url: String?, uti: String?, width: Int? = nil, height: Int? = nil,
        size: Int? = nil, fileURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.uti = uti
        self.width = width
        self.height = height
        self.size = size
        self.fileURL = fileURL
    }
}

public struct ReminderTaskSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let listID: String
    public var sectionID: String?
    public let title: String
    public let notes: String?
    public let isCompleted: Bool
    public let completionDate: Date?
    public let creationDate: Date?
    public let modifiedDate: Date?
    /// ReminderKit priority: 0 none, 1-4 high, 5 medium, 6-9 low.
    public let priority: Int
    public let isFlagged: Bool
    public let due: ReminderDate?
    public let start: ReminderDate?
    public let url: String?
    public let alarms: [ReminderAlarmSnapshot]
    public let earlyAlert: ReminderEarlyAlert?
    public let tags: [String]
    public let parentID: String?
    public var subtaskIDs: [String]
    public let recurrence: ReminderRecurrenceSnapshot?
    public let attachments: [ReminderAttachmentSnapshot]
    /// Sharee id of the current assignee, for shared lists.
    public let assigneeID: String?
    public let isUrgent: Bool
    /// Position in the list as the app displays it (section order, then manual order).
    public var order: Int

    public init(
        id: String, listID: String, sectionID: String? = nil, title: String, notes: String? = nil,
        isCompleted: Bool = false, completionDate: Date? = nil, creationDate: Date? = nil, modifiedDate: Date? = nil,
        priority: Int = 0, isFlagged: Bool = false, due: ReminderDate? = nil, start: ReminderDate? = nil,
        url: String? = nil, alarms: [ReminderAlarmSnapshot] = [], earlyAlert: ReminderEarlyAlert? = nil,
        tags: [String] = [], parentID: String? = nil, subtaskIDs: [String] = [],
        recurrence: ReminderRecurrenceSnapshot? = nil, attachments: [ReminderAttachmentSnapshot] = [],
        assigneeID: String? = nil, isUrgent: Bool = false, order: Int = 0
    ) {
        self.id = id
        self.listID = listID
        self.sectionID = sectionID
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.creationDate = creationDate
        self.modifiedDate = modifiedDate
        self.priority = priority
        self.isFlagged = isFlagged
        self.due = due
        self.start = start
        self.url = url
        self.alarms = alarms
        self.earlyAlert = earlyAlert
        self.tags = tags
        self.parentID = parentID
        self.subtaskIDs = subtaskIDs
        self.recurrence = recurrence
        self.attachments = attachments
        self.assigneeID = assigneeID
        self.isUrgent = isUrgent
        self.order = order
    }

    /// Overdue as the Reminders app shows it: a timed due date in the past, or a date-only due
    /// date before today.
    public func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let due else { return false }
        return due.hasTime ? due.date < now : due.date < calendar.startOfDay(for: now)
    }
}

/// Everything one read returns: lists and groups, sections, and the reminders of the lists
/// that were loaded. Sections and membership come from the native sectioned data view.
public struct ReminderCatalog: Sendable {
    public let accounts: [ReminderAccountSnapshot]
    /// Lists and groups in sidebar order (groups precede their lists).
    public let lists: [ReminderListSnapshot]
    public let sections: [ReminderSectionSnapshot]
    public let tasks: [ReminderTaskSnapshot]
    /// Lists whose section membership could not be read; their tasks have no section.
    public let warnings: [String]

    public init(
        accounts: [ReminderAccountSnapshot], lists: [ReminderListSnapshot], sections: [ReminderSectionSnapshot],
        tasks: [ReminderTaskSnapshot], warnings: [String] = []
    ) {
        self.accounts = accounts
        self.lists = lists
        self.sections = sections
        self.tasks = tasks
        self.warnings = warnings
    }

    public func list(_ id: String) -> ReminderListSnapshot? { lists.first { $0.id == id } }
    public func section(_ id: String) -> ReminderSectionSnapshot? { sections.first { $0.id == id } }
    public func task(_ id: String) -> ReminderTaskSnapshot? { tasks.first { $0.id == id } }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public enum ReminderCLIError: CLIErrorCodeProviding, LocalizedError, Sendable {
    case frameworkLoadFailed([String])
    case missingClass(String)
    case missingSelector(className: String, selector: String)
    case storeInitializationFailed
    case fetchFailed(String)
    case objectNotFound(type: String, id: String)
    case invalidArgument(String)
    case unsupportedPrivateAPI(selector: String, reason: String)
    case saveFailed(String)
    case permissionDenied(String)

    public var errorDescription: String? {
        switch self {
        case .frameworkLoadFailed(let paths):
            return "Could not load ReminderKit private framework from: \(paths.joined(separator: ", "))"
        case .missingClass(let name):
            return "ReminderKit private class is missing: \(name)"
        case .missingSelector(let className, let selector):
            return "ReminderKit private selector is missing: \(className).\(selector)"
        case .storeInitializationFailed:
            return "Could not initialize REMStore."
        case .fetchFailed(let message):
            return message
        case .objectNotFound(let type, let id):
            return "\(type) not found: \(id)"
        case .invalidArgument(let message):
            return message
        case .unsupportedPrivateAPI(let selector, let reason):
            return "Unsupported private API selector \(selector): \(reason)"
        case .saveFailed(let message):
            return message
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        }
    }

    public var code: String {
        switch self {
        case .frameworkLoadFailed: "framework_load_failed"
        case .missingClass: "missing_class"
        case .missingSelector: "missing_selector"
        case .storeInitializationFailed: "store_initialization_failed"
        case .fetchFailed: "fetch_failed"
        case .objectNotFound: "not_found"
        case .invalidArgument: "invalid_argument"
        case .unsupportedPrivateAPI: "unsupported_private_api"
        case .saveFailed: "save_failed"
        case .permissionDenied: "permission_denied"
        }
    }

    public var details: [String: String] {
        switch self {
        case .frameworkLoadFailed(let paths): ["paths": paths.joined(separator: ",")]
        case .missingClass(let name): ["class": name]
        case .missingSelector(let className, let selector): ["class": className, "selector": selector]
        case .objectNotFound(let type, let id): ["type": type, "id": id]
        case .unsupportedPrivateAPI(let selector, let reason): ["selector": selector, "reason": reason]
        case .permissionDenied(let message): ["reason": message]
        default: [:]
        }
    }
}
