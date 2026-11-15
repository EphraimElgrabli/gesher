import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

/// Fields that can be removed with `clear`.
enum ClearField: String, Decodable, Sendable, CaseIterable {
    case notes, url, due, start, priority, tags, repeats, alarms, earlyAlert, location, section, parent
}

struct LocationInput: Decodable, Sendable {
    var name: String?
    var address: String?
    var latitude: Double
    var longitude: Double
    var radius: Double?
    var proximity: String?

    func mutation() throws -> ReminderLocationMutation {
        let proximity: ReminderLocationProximity
        switch (self.proximity ?? "arriving").lowercased() {
        case "arriving", "arrive", "arrival": proximity = .arriving
        case "leaving", "leave", "departure": proximity = .leaving
        default: throw AgentError.invalid("location.proximity must be 'arriving' or 'leaving'.")
        }
        do {
            return try ReminderLocationMutation(
                title: name ?? address ?? "Location", address: address, latitude: latitude, longitude: longitude,
                radius: radius ?? 100, proximity: proximity)
        } catch let error as ReminderCLIError {
            throw AgentError.invalid(error.localizedDescription)
        }
    }
}

/// Task fields shared by `task_create` and `task_update`, both as top-level parameters and as
/// the keys of each `items` entry. Property names equal parameter names.
struct TaskFields: Decodable, Sendable {
    var title: String?
    var list: String?
    var section: String?
    var due: NaturalDate?
    var start: NaturalDate?
    var notes: String?
    var url: String?
    var priority: Priority?
    var flagged: Bool?
    var tags: [String]?
    var addTags: [String]?
    var removeTags: [String]?
    var parent: String?
    var repeats: String?
    var repeatUntil: NaturalDate?
    var repeatCount: Int?
    var alarms: [NaturalDate]?
    var earlyAlert: String?
    var location: LocationInput?
    var completed: Bool?
    var position: String?
    var before: String?
    var after: String?
    var clear: [ClearField]?

    /// The shared fields of an operation's input object, without its own keys (e.g. `title`
    /// is a list of titles for task_create but a single new title in the fields).
    static func decode(_ decoder: Decoder, excluding keys: Set<String>) throws -> TaskFields {
        guard var object = try JSONValue(from: decoder).objectValue else { return TaskFields() }
        for key in keys { object.removeValue(forKey: key) }
        return try JSONValue.object(object).decode(TaskFields.self)
    }

    var isEmpty: Bool {
        let values: [Any?] = [
            title, list, section, due, start, notes, url, priority, flagged, tags, addTags, removeTags, parent, repeats,
            repeatUntil, repeatCount, alarms, earlyAlert, location, completed, position, before, after, clear,
        ]
        return values.allSatisfy { $0 == nil }
    }

    /// `item` values win over `self` (the shared top-level values).
    func merged(with item: TaskFields) -> TaskFields {
        TaskFields(
            title: item.title ?? title, list: item.list ?? list, section: item.section ?? section,
            due: item.due ?? due, start: item.start ?? start, notes: item.notes ?? notes, url: item.url ?? url,
            priority: item.priority ?? priority, flagged: item.flagged ?? flagged, tags: item.tags ?? tags,
            addTags: item.addTags ?? addTags, removeTags: item.removeTags ?? removeTags, parent: item.parent ?? parent,
            repeats: item.repeats ?? repeats, repeatUntil: item.repeatUntil ?? repeatUntil,
            repeatCount: item.repeatCount ?? repeatCount, alarms: item.alarms ?? alarms,
            earlyAlert: item.earlyAlert ?? earlyAlert, location: item.location ?? location,
            completed: item.completed ?? completed, position: item.position ?? position,
            before: item.before ?? before, after: item.after ?? after, clear: item.clear ?? clear)
    }

    /// Decodes `items` entries, rejecting keys that are not task fields.
    static func items(_ values: [JSONValue]?, allowed: [Param], extra: [String]) throws -> [(JSONValue, TaskFields)] {
        let names = Set(allowed.map(\.name) + extra)
        return try (values ?? []).enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw AgentError.invalid("items[\(index)] must be an object such as {\"title\": \"Buy milk\"}.")
            }
            if let unknown = object.keys.sorted().first(where: { !names.contains($0) }) {
                throw AgentError.invalid(
                    "Unknown key '\(unknown)' in items[\(index)].",
                    hint: "Item keys: " + names.sorted().joined(separator: ", ") + ".")
            }
            do {
                return (value, try value.decode(TaskFields.self))
            } catch let DecodingError.dataCorrupted(context) {
                if let error = context.underlyingError as? AgentError { throw error }
                throw AgentError.invalid("items[\(index)]: \(context.debugDescription)")
            } catch let DecodingError.typeMismatch(_, context) {
                let key = context.codingPath.map(\.stringValue).joined(separator: ".")
                throw AgentError.invalid("items[\(index)].\(key) has the wrong type.")
            }
        }
    }
}

/// Parameters shared by `task_create` and `task_update`.
enum TaskParams {
    static let due = Param.date("due", "Due; without a time it is all-day.")
    static let start = Param.date("start", "Start date.")
    static let notes = Param.string("notes", "Notes (replaces).")
    static let url = Param.string("url", "Link (absolute URL).")
    static let priority = Param.choice("priority", Priority.allCases.map(\.rawValue), "Priority.")
    static let flagged = Param("flagged", .boolean, "Flag or unflag.")
    static let tags = Param.list("tags", "Tags without '#' (replaces).")
    static let parent = Param.string("parent", "Parent task (name or id) to make this a subtask.")
    static let repeats = Param.string(
        "repeats",
        "daily|weekly|monthly|yearly|weekdays|weekends|'every 2 weeks'|'weekly on mon,thu'|"
            + "'monthly on 1,15,last'|none.")
    static let repeatUntil = Param.date("repeatUntil", "Recurrence end date.")
    static let repeatCount = Param.integer("repeatCount", "Recurrence occurrences.", min: 1, max: 999)
    static let alarms = Param.list("alarms", "Alert times.", of: .date)
    static let earlyAlert = Param.string("earlyAlert", "Before due: 15m|1h|1d|1w|1mo|none.")
    static let location = Param(
        "location", .object,
        "Location alert {name,latitude,longitude,radius?,proximity?:arriving|leaving,address?}.")
    static let position = Param.choice("position", ["top", "bottom"], "First or last among siblings.")
    static let before = Param.string("before", "Place before this task.")
    static let after = Param.string("after", "Place after this task.")
}

/// Builds native mutations from task fields, resolving every selector against one catalog.
struct MutationBuilder {
    let context: RemindersContext
    let catalog: ReminderCatalog
    let input: DateInput = DateInput()

    static func recurrence(_ text: String?, until: NaturalDate?, count: Int?) throws -> FieldChange<RecurrenceMutation>?
    {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else {
            guard until == nil, count == nil else {
                throw AgentError.invalid("repeatUntil and repeatCount need repeats, e.g. repeats: weekly.")
            }
            return nil
        }
        if ["none", "never", "no", "off"].contains(text) { return .clear }
        var words = text.replacingOccurrences(of: ",", with: " , ").split(separator: " ").map(String.init)
        var frequency: RecurrenceMutation.Frequency?
        var interval = 1
        var weekdays: [Int] = []
        var days: [Int] = []
        let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        func weekday(_ word: String) -> Int? {
            dayNames.firstIndex { word.hasPrefix($0) }.map { $0 + 1 }
        }
        if words.first == "every" {
            words.removeFirst()
            if let first = words.first, let number = Int(first) {
                interval = number
                words.removeFirst()
            }
            guard let unit = words.first else { throw invalidRepeat(text) }
            words.removeFirst()
            switch unit {
            case "day", "days": frequency = .daily
            case "week", "weeks": frequency = .weekly
            case "month", "months": frequency = .monthly
            case "year", "years": frequency = .yearly
            case "weekday", "weekdays":
                frequency = .weekly
                weekdays = [2, 3, 4, 5, 6]
            default:
                guard let day = weekday(unit) else { throw invalidRepeat(text) }
                frequency = .weekly
                weekdays = [day]
            }
        } else if let first = words.first {
            words.removeFirst()
            switch first {
            case "daily": frequency = .daily
            case "weekly": frequency = .weekly
            case "monthly": frequency = .monthly
            case "yearly", "annually": frequency = .yearly
            case "weekdays":
                frequency = .weekly
                weekdays = [2, 3, 4, 5, 6]
            case "weekends":
                frequency = .weekly
                weekdays = [1, 7]
            default: throw invalidRepeat(text)
            }
        }
        if words.first == "on" {
            words.removeFirst()
            for word in words where word != "," && word != "and" && word != "day" {
                if let day = weekday(word), frequency == .weekly {
                    weekdays.append(day)
                } else if let number = Int(word.replacingOccurrences(of: "last", with: "-1")), frequency == .monthly {
                    days.append(number)
                } else if word == "last", frequency == .monthly {
                    days.append(-1)
                } else {
                    throw invalidRepeat(text)
                }
            }
        } else if !words.isEmpty {
            throw invalidRepeat(text)
        }
        guard let frequency else { throw invalidRepeat(text) }
        do {
            return .set(
                try RecurrenceMutation(
                    frequency: frequency, interval: interval, weekdays: weekdays, daysOfMonth: days,
                    endDate: until.map { $0.hasTime ? $0.date : $0.date.addingTimeInterval(86_399) }, count: count))
        } catch let error as ReminderCLIError {
            throw AgentError.invalid(error.localizedDescription)
        }
    }

    private static func invalidRepeat(_ text: String) -> AgentError {
        AgentError.invalid(
            "Unrecognized recurrence '\(text)'.",
            hint: "Use daily, weekly, monthly, yearly, weekdays, weekends, 'every 2 weeks', 'weekly on mon,thu', "
                + "'monthly on 1,15' or none.")
    }

    /// Validates field syntax that does not need the store (so bad input fails before it opens).
    static func validateOffline(_ fields: TaskFields) throws {
        _ = try recurrence(fields.repeats, until: fields.repeatUntil, count: fields.repeatCount)
        if let early = fields.earlyAlert, !["none", "off"].contains(early.lowercased()) {
            do { _ = try ReminderEarlyAlert(parsing: early) } catch {
                throw AgentError.invalid(error.localizedDescription)
            }
        }
        _ = try fields.location?.mutation()
        if let url = fields.url, URL(string: url)?.scheme == nil {
            throw AgentError.invalid("url must be absolute, e.g. https://example.com.")
        }
        if let title = fields.title, title.trimmingCharacters(in: .whitespaces).isEmpty {
            throw AgentError.invalid("title cannot be empty.")
        }
        let placements = [fields.position != nil, fields.before != nil, fields.after != nil].filter { $0 }.count
        if placements > 1 { throw AgentError.invalid("Use only one of position, before and after.") }
    }

    func date(_ value: NaturalDate) -> ReminderDate {
        ReminderDate(date: value.date, hasTime: value.hasTime, timeZone: nil)
    }

    /// The mutation for `fields`, applied to `task` (nil when creating in `list`).
    func mutation(_ fields: TaskFields, task: ReminderTaskSnapshot?, list: ReminderListSnapshot) throws -> TaskMutation
    {
        try Self.validateOffline(fields)
        let clear = Set(fields.clear ?? [])
        var mutation = TaskMutation()
        mutation.title = task == nil ? nil : fields.title
        if clear.contains(.notes) {
            mutation.notes = .clear
        } else if let notes = fields.notes {
            mutation.notes = .set(notes)
        }
        if clear.contains(.url) { mutation.url = .clear } else if let url = fields.url { mutation.url = .set(url) }
        if clear.contains(.due) {
            mutation.due = .clear
        } else if let due = fields.due {
            mutation.due = .set(date(due))
        }
        if clear.contains(.start) {
            mutation.start = .clear
        } else if let start = fields.start {
            mutation.start = .set(date(start))
        }
        if clear.contains(.priority) {
            mutation.priority = 0
        } else if let priority = fields.priority {
            mutation.priority = priority.native
        }
        mutation.flagged = fields.flagged
        mutation.completed = fields.completed
        if clear.contains(.tags) { mutation.tags = [] } else { mutation.tags = fields.tags }
        mutation.addTags = fields.addTags ?? []
        mutation.removeTags = fields.removeTags ?? []
        if clear.contains(.repeats) {
            mutation.recurrence = .clear
        } else {
            mutation.recurrence = try Self.recurrence(
                fields.repeats, until: fields.repeatUntil, count: fields.repeatCount)
        }
        mutation.alarms = (fields.alarms ?? []).map(date)
        mutation.clearAlarms = clear.contains(.alarms)
        if clear.contains(.location) {
            mutation.location = .clear
        } else if let location = fields.location {
            mutation.location = .set(try location.mutation())
        }
        if clear.contains(.earlyAlert) {
            mutation.earlyAlert = .clear
        } else if let early = fields.earlyAlert {
            mutation.earlyAlert =
                ["none", "off"].contains(early.lowercased()) ? .clear : .set(try ReminderEarlyAlert(parsing: early))
        }
        if case .set? = mutation.earlyAlert {
            let due: Bool
            switch mutation.due {
            case .set?: due = true
            case .clear?: due = false
            case nil: due = task?.due != nil
            }
            guard due else { throw AgentError.invalid("An early alert needs a due date; set due as well.") }
        }
        if list.id != task?.listID { mutation.listID = list.id }
        if task == nil { mutation.listID = nil }
        if clear.contains(.section) {
            mutation.section = .clear
        } else if let section = fields.section {
            if task?.parentID != nil, !clear.contains(.parent), fields.parent == nil {
                throw AgentError.invalid(
                    "Subtasks are shown in their parent's section.",
                    hint: "Move the parent task instead, or add clear: [parent] to make this a top-level task.")
            }
            mutation.section = .set(try context.section(section, list: list, in: catalog).id)
        }
        if clear.contains(.parent) {
            mutation.parent = .clear
        } else if let parent = fields.parent {
            let resolved = try context.task(parent, in: catalog, scope: list)
            mutation.parent = .set(resolved.id)
        }
        if let position = fields.position {
            mutation.position = position == "top" ? .top : .bottom
        } else if let before = fields.before {
            mutation.position = .before(taskID: try context.task(before, in: catalog, scope: list).id)
        } else if let after = fields.after {
            mutation.position = .after(taskID: try context.task(after, in: catalog, scope: list).id)
        }
        return mutation
    }
}
