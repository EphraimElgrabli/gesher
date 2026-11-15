import GesherPlatform
import Foundation
import RemindersCore

/// Agent-facing output models. Absent values are omitted; booleans appear only when true;
/// dates are ISO 8601 in the user's zone (`2026-11-05` for date-only values).

enum Priority: String, Codable, Sendable, CaseIterable {
    case none, low, medium, high

    init(native: Int) {
        switch native {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var native: Int {
        switch self {
        case .none: 0
        case .low: 9
        case .medium: 5
        case .high: 1
        }
    }
}

private let weekdayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

/// "every 2 weeks on Mon, Wed, until 2027-01-02" style text for a native rule.
func recurrenceText(_ rule: ReminderRecurrenceSnapshot) -> String {
    let units = ["daily": "day", "weekly": "week", "monthly": "month", "yearly": "year"]
    var text: String
    if rule.interval == 1 {
        text = rule.frequency
        if rule.frequency == "weekly", rule.weekdays == [2, 3, 4, 5, 6] { text = "weekdays" }
    } else {
        text = "every \(rule.interval) \(units[rule.frequency] ?? rule.frequency)s"
    }
    if !rule.weekdays.isEmpty, text != "weekdays" {
        text += " on " + rule.weekdays.map { weekdayNames[min(max($0, 0), 7)] }.joined(separator: ", ")
    }
    if !rule.daysOfMonth.isEmpty {
        text += " on day " + rule.daysOfMonth.map { $0 == -1 ? "last" : String($0) }.joined(separator: ", ")
    }
    if let end = rule.endDate { text += ", until " + DateOutput.day(end) }
    if let count = rule.count { text += ", \(count) times" }
    return text
}

/// One task as tools return it in lists of tasks.
struct TaskItem: Encodable, Sendable {
    let id: String
    let title: String
    let list: String
    let section: String?
    let due: String?
    let overdue: Bool?
    let priority: Priority?
    let flagged: Bool?
    let tags: [String]?
    let parent: String?
    let subtasks: Int?
    let completed: Bool?
    let completedAt: String?
    let repeats: String?
    let earlyAlert: String?
    let alarms: Int?
    let location: String?
    let notes: String?
    let url: String?
    let assigned: Bool?

    init(_ task: ReminderTaskSnapshot, catalog: ReminderCatalog, notesLimit: Int? = 300, now: Date = Date()) {
        id = task.id
        title = task.title
        list = catalog.list(task.listID)?.title ?? task.listID
        section = task.sectionID.flatMap { catalog.section($0)?.title }
        due = task.due?.text()
        overdue = task.isOverdue(now: now) ? true : nil
        let priority = Priority(native: task.priority)
        self.priority = priority == .none ? nil : priority
        flagged = task.isFlagged ? true : nil
        tags = task.tags.isEmpty ? nil : task.tags
        parent = task.parentID
        subtasks = task.subtaskIDs.isEmpty ? nil : task.subtaskIDs.count
        completed = task.isCompleted ? true : nil
        completedAt = task.isCompleted ? task.completionDate.map { DateOutput.iso($0) } : nil
        repeats = task.recurrence.map(recurrenceText)
        earlyAlert = task.earlyAlert.map { "\($0.text) before" }
        let timeAlarms = task.alarms.filter {
            if case .location = $0 { return false }
            return true
        }
        alarms = timeAlarms.isEmpty ? nil : timeAlarms.count
        location =
            task.alarms.lazy.compactMap { alarm -> String? in
                if case .location(let title, let address, _, _, _, let proximity) = alarm {
                    return "\(proximity == "leaving" ? "leaving" : "arriving at") \(title ?? address ?? "a place")"
                }
                return nil
            }.first
        if let notes = task.notes, let notesLimit, notes.count > notesLimit {
            self.notes = String(notes.prefix(notesLimit)) + "…"
        } else {
            notes = task.notes
        }
        url = task.url
        assigned = task.assigneeID != nil ? true : nil
    }
}

/// A task with every detail, for `task_get` and write results.
struct TaskDetail: Encodable, Sendable {
    struct Subtask: Encodable, Sendable {
        let id: String
        let title: String
        let completed: Bool?
    }
    struct Alarm: Encodable, Sendable {
        let at: String?
        let location: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let radius: Double?
        let proximity: String?
        let secondsFromDue: Double?
    }
    struct Recurrence: Encodable, Sendable {
        let text: String
        let frequency: String
        let interval: Int
        let weekdays: [String]?
        let daysOfMonth: [Int]?
        let until: String?
        let count: Int?
    }
    struct Attachment: Encodable, Sendable {
        let id: String?
        let kind: String
        let size: Int?
        let url: String?
        let type: String?
        let width: Int?
        let height: Int?
    }

    let id: String
    let title: String
    let list: String
    let listId: String
    let section: String?
    let sectionId: String?
    let due: String?
    let allDay: Bool?
    let overdue: Bool?
    let start: String?
    let priority: Priority?
    let flagged: Bool?
    let tags: [String]?
    let parent: String?
    let parentTitle: String?
    let subtasks: [Subtask]?
    let completed: Bool?
    let completedAt: String?
    let notes: String?
    let url: String?
    let recurrence: Recurrence?
    let earlyAlert: String?
    let alarms: [Alarm]?
    let attachments: [Attachment]?
    let assignedTo: String?
    let urgent: Bool?
    let created: String?
    let modified: String?

    init(_ task: ReminderTaskSnapshot, catalog: ReminderCatalog, now: Date = Date()) {
        let item = TaskItem(task, catalog: catalog, notesLimit: nil, now: now)
        id = task.id
        title = task.title
        list = item.list
        listId = task.listID
        section = item.section
        sectionId = task.sectionID
        due = item.due
        allDay = task.due.map { !$0.hasTime } == true ? true : nil
        overdue = item.overdue
        start = task.start?.text()
        priority = item.priority
        flagged = item.flagged
        tags = item.tags
        parent = task.parentID
        parentTitle = task.parentID.flatMap { catalog.task($0)?.title }
        let subtasks = task.subtaskIDs.compactMap { id in
            catalog.task(id).map { Subtask(id: $0.id, title: $0.title, completed: $0.isCompleted ? true : nil) }
        }
        self.subtasks = subtasks.isEmpty ? nil : subtasks
        completed = item.completed
        completedAt = item.completedAt
        notes = task.notes
        url = task.url
        recurrence = task.recurrence.map { rule in
            Recurrence(
                text: recurrenceText(rule), frequency: rule.frequency, interval: rule.interval,
                weekdays: rule.weekdays.isEmpty ? nil : rule.weekdays.map { weekdayNames[min(max($0, 0), 7)] },
                daysOfMonth: rule.daysOfMonth.isEmpty ? nil : rule.daysOfMonth,
                until: rule.endDate.map { DateOutput.day($0) }, count: rule.count)
        }
        earlyAlert = item.earlyAlert
        let alarms = task.alarms.map { alarm -> Alarm in
            switch alarm {
            case .date(let date):
                return Alarm(
                    at: date.text(), location: nil, address: nil, latitude: nil, longitude: nil, radius: nil,
                    proximity: nil, secondsFromDue: nil)
            case .location(let title, let address, let latitude, let longitude, let radius, let proximity):
                return Alarm(
                    at: nil, location: title, address: address, latitude: latitude, longitude: longitude,
                    radius: radius, proximity: proximity, secondsFromDue: nil)
            case .relative(let seconds):
                return Alarm(
                    at: nil, location: nil, address: nil, latitude: nil, longitude: nil, radius: nil, proximity: nil,
                    secondsFromDue: seconds)
            }
        }
        self.alarms = alarms.isEmpty ? nil : alarms
        let attachments = task.attachments.map {
            Attachment(
                id: $0.id, kind: $0.kind, size: $0.size, url: $0.url,
                type: $0.uti, width: $0.width, height: $0.height)
        }
        self.attachments = attachments.isEmpty ? nil : attachments
        let list = catalog.list(task.listID)
        assignedTo = task.assigneeID.map { id in list?.sharees.first { $0.id == id }?.name ?? id }
        urgent = task.isUrgent ? true : nil
        created = task.creationDate.map { DateOutput.iso($0) }
        modified = task.modifiedDate.map { DateOutput.iso($0) }
    }
}

struct TasksOutput: Encodable, Sendable {
    let view: String
    let count: Int
    /// Present when `limit` cut the result: the number of matching tasks.
    let total: Int?
    let sections: [String]?
    let tasks: [TaskItem]
    let warnings: [String]?
}

struct ListItem: Encodable, Sendable {
    struct Section: Encodable, Sendable {
        let id: String
        let name: String
        let open: Int
    }
    let id: String
    let name: String
    let group: String?
    let open: Int
    let overdue: Int?
    let flagged: Int?
    let completed: Int?
    let color: String?
    let emoji: String?
    let shared: Bool?
    let owner: String?
    let sharedWith: [String]?
    let sections: [Section]?
}

struct GroupItem: Encodable, Sendable {
    let id: String
    let name: String
    let lists: [String]
}

struct ListsOutput: Encodable, Sendable {
    struct Views: Encodable, Sendable {
        let today: Int
        let scheduled: Int
        let overdue: Int
        let flagged: Int
        let all: Int
        let assigned: Int?
        let completed: Int
    }
    let views: Views
    let defaultList: String?
    let groups: [GroupItem]?
    let lists: [ListItem]
    let warnings: [String]?
}

struct ListResult: Encodable, Sendable {
    let id: String
    let name: String
    let kind: String
    let group: String?
    let color: String?
    let emoji: String?

    init(_ list: ReminderListSnapshot, catalog: ReminderCatalog?) {
        id = list.id
        name = list.title
        kind = list.isGroup ? "group" : "list"
        group = list.groupID.map { id in catalog?.list(id)?.title ?? id }
        color = list.colorHex
        emoji = list.emoji
    }
}

struct SectionResult: Encodable, Sendable {
    let id: String
    let name: String
    let list: String
    let position: Int?
}

struct DeletedItem: Encodable, Sendable {
    let id: String
    let title: String
    let deleted: Bool
}

/// A batch result plus the backup written before a bulk change, if any.
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

struct TagsOutput: Encodable, Sendable {
    struct Tag: Encodable, Sendable {
        let name: String
        let open: Int
        let completed: Int?
    }
    let tags: [Tag]
}
