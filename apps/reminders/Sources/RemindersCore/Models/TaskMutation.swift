import Foundation

/// A value to set, or an explicit removal.
public enum FieldChange<Value: Sendable & Equatable>: Sendable, Equatable {
    case set(Value)
    case clear
}

public struct RecurrenceMutation: Sendable, Equatable {
    public enum Frequency: String, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly

        /// ReminderKit / iCalendar frequency code.
        public var code: Int {
            switch self {
            case .daily: 0
            case .weekly: 1
            case .monthly: 2
            case .yearly: 3
            }
        }

        public init?(code: Int) {
            guard let match = Self.allCases.first(where: { $0.code == code }) else { return nil }
            self = match
        }
    }

    public let frequency: Frequency
    public let interval: Int
    /// 1 = Sunday ... 7 = Saturday.
    public let weekdays: [Int]
    public let daysOfMonth: [Int]
    public let endDate: Date?
    public let count: Int?

    public init(
        frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], daysOfMonth: [Int] = [], endDate: Date? = nil,
        count: Int? = nil
    ) throws {
        guard (1...999).contains(interval) else {
            throw ReminderCLIError.invalidArgument("Recurrence interval must be between 1 and 999.")
        }
        guard weekdays.allSatisfy({ (1...7).contains($0) }) else {
            throw ReminderCLIError.invalidArgument("Recurrence weekdays must be 1 (Sunday) to 7 (Saturday).")
        }
        guard daysOfMonth.allSatisfy({ (1...31).contains($0) || (-31 ... -1).contains($0) }) else {
            throw ReminderCLIError.invalidArgument("Recurrence days of the month must be 1...31 (or -1 for the last).")
        }
        guard endDate == nil || count == nil else {
            throw ReminderCLIError.invalidArgument("A recurrence ends either on a date or after a count, not both.")
        }
        if let count, !(1...999).contains(count) {
            throw ReminderCLIError.invalidArgument("Recurrence count must be between 1 and 999.")
        }
        self.frequency = frequency
        self.interval = interval
        self.weekdays = Array(Set(weekdays)).sorted()
        self.daysOfMonth = Array(Set(daysOfMonth)).sorted()
        self.endDate = endDate
        self.count = count
    }
}

/// Where to place a task within its list (or among its siblings).
public enum TaskPosition: Sendable, Equatable {
    case top
    case bottom
    case before(taskID: String)
    case after(taskID: String)
}

/// Field changes for creating or updating a reminder. `nil` leaves a field unchanged.
public struct TaskMutation: Sendable, Equatable {
    public var title: String?
    public var notes: FieldChange<String>?
    public var url: FieldChange<String>?
    public var due: FieldChange<ReminderDate>?
    public var start: FieldChange<ReminderDate>?
    public var priority: Int?
    public var flagged: Bool?
    public var completed: Bool?
    /// Replace all tags.
    public var tags: [String]?
    public var addTags: [String]
    public var removeTags: [String]
    public var recurrence: FieldChange<RecurrenceMutation>?
    /// Time alarms to add; `clearAlarms` removes existing time and location alarms first.
    public var alarms: [ReminderDate]
    public var clearAlarms: Bool
    public var location: FieldChange<ReminderLocationMutation>?
    public var earlyAlert: FieldChange<ReminderEarlyAlert>?
    /// Move to another list (same account).
    public var listID: String?
    public var section: FieldChange<String>?
    /// Make a subtask of this task, or `.clear` to make it a top-level task again.
    public var parent: FieldChange<String>?
    public var position: TaskPosition?

    public init(
        title: String? = nil, notes: FieldChange<String>? = nil, url: FieldChange<String>? = nil,
        due: FieldChange<ReminderDate>? = nil, start: FieldChange<ReminderDate>? = nil, priority: Int? = nil,
        flagged: Bool? = nil, completed: Bool? = nil,
        tags: [String]? = nil, addTags: [String] = [], removeTags: [String] = [],
        recurrence: FieldChange<RecurrenceMutation>? = nil, alarms: [ReminderDate] = [], clearAlarms: Bool = false,
        location: FieldChange<ReminderLocationMutation>? = nil, earlyAlert: FieldChange<ReminderEarlyAlert>? = nil,
        listID: String? = nil, section: FieldChange<String>? = nil, parent: FieldChange<String>? = nil,
        position: TaskPosition? = nil
    ) {
        self.title = title
        self.notes = notes
        self.url = url
        self.due = due
        self.start = start
        self.priority = priority
        self.flagged = flagged
        self.completed = completed
        self.tags = tags
        self.addTags = addTags
        self.removeTags = removeTags
        self.recurrence = recurrence
        self.alarms = alarms
        self.clearAlarms = clearAlarms
        self.location = location
        self.earlyAlert = earlyAlert
        self.listID = listID
        self.section = section
        self.parent = parent
        self.position = position
    }

    public var hasChanges: Bool { self != TaskMutation() }

    /// Normalized tag name as Reminders stores it: no leading '#', no spaces.
    public static func normalizeTag(_ raw: String) -> String {
        var tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") { tag.removeFirst() }
        return tag.split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    /// The tag set after applying `tags`, `addTags` and `removeTags` to `current`.
    public func resultingTags(from current: [String]) -> [String] {
        var result = tags.map { $0.map(Self.normalizeTag) } ?? current
        for tag in addTags.map(Self.normalizeTag)
        where !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            result.append(tag)
        }
        let removed = Set(removeTags.map { Self.normalizeTag($0).lowercased() })
        result.removeAll { removed.contains($0.lowercased()) }
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public var changesTags: Bool { tags != nil || !addTags.isEmpty || !removeTags.isEmpty }
}
