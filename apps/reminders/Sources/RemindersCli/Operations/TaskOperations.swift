import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

enum TaskView: String, Decodable, Sendable, CaseIterable {
    case open, today, scheduled, overdue, flagged, assigned, completed, all
}

/// Smart views as the Reminders app defines them, applied to a catalog.
struct ViewFilter {
    let now: Date
    let calendar: Calendar

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    var endOfToday: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))! }

    /// Due today or earlier (the app's Today includes overdue tasks).
    func isDueByToday(_ task: ReminderTaskSnapshot) -> Bool {
        guard let due = task.due else { return false }
        return due.date < endOfToday
    }

    func matches(_ task: ReminderTaskSnapshot, view: TaskView) -> Bool {
        switch view {
        case .open, .all: return !task.isCompleted
        case .today: return !task.isCompleted && isDueByToday(task)
        case .scheduled: return !task.isCompleted && task.due != nil
        case .overdue: return task.isOverdue(now: now, calendar: calendar)
        case .flagged: return !task.isCompleted && task.isFlagged
        case .assigned: return !task.isCompleted && task.assigneeID != nil
        case .completed: return task.isCompleted
        }
    }
}

enum ListTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var view: TaskView
        var list: [String]?
        var smartList: String?
        var section: String?
        var tag: [String]?
        var search: String?
        var parent: String?
        var from: NaturalDate?
        var to: NaturalDate?
        var includeCompleted: Bool
        var limit: Int
    }

    static let path = ["tasks"]
    static let summary =
        "Find tasks: smart views (today, scheduled, overdue, flagged, assigned, completed, all), a list or "
        + "section, tags, date range and full-text search."
    static let params: [Param] = [
        .choice(
            "view", TaskView.allCases.map(\.rawValue),
            "open = not completed (default); today = due today or overdue; scheduled = has a due date; overdue; "
                + "flagged; assigned (shared lists); completed; all = open tasks of every list.",
            default: "open"),
        .list("list", "Only these lists or groups (names or ids)."),
        .string("smartList", "Only tasks matching this custom smart list (name or id)."),
        .string("section", "Only this section (needs one list)."),
        .list("tag", "Only tasks with all of these tags."),
        .string("search", "Words to find in titles, notes and tags (any order, accents ignored).", positional: true),
        .string("parent", "Only the subtasks of this task (name or id)."),
        .date("from", "Earliest due date (completion date for view=completed)."),
        .date("to", "Latest due date (completion date for view=completed); a date without a time includes that day."),
        .boolean("includeCompleted", "Also return completed tasks (ignored for view=completed)."),
        .integer("limit", "Maximum tasks to return.", default: 200, min: 1, max: 2000),
    ]
    static let examples = [
        "tasks --view today", "tasks --view scheduled --from today --to 'next friday'", "tasks dentist",
        "tasks --list Groceries", "tasks --smart-list 'Work this week'", "tasks --view completed --from yesterday",
        "tasks --tag errands --view flagged",
    ]

    static func validate(_ input: Input) throws {
        if input.section != nil, input.list?.count != 1 {
            throw AgentError.invalid("section needs exactly one list.", hint: "Add --list <name>.")
        }
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> TasksOutput {
        let lists = try context.catalog(taskLists: [])
        var scope: Set<String>?
        var scopedLists: [ReminderListSnapshot] = []
        if let selectors = input.list {
            scopedLists = try selectors.map { try context.list($0, in: lists, groups: nil) }
            scope = Set(
                scopedLists.flatMap { list in
                    list.isGroup ? lists.lists.filter { $0.groupID == list.id }.map(\.id) : [list.id]
                })
        }
        let catalog = try context.catalog(taskLists: scope)
        let filter = ViewFilter()
        var tasks = catalog.tasks.filter { task in
            if input.view == .completed { return task.isCompleted }
            if filter.matches(task, view: input.view) { return true }
            return input.includeCompleted && task.isCompleted && ViewFilter.withoutCompletion(task, input.view, filter)
        }
        if let selector = input.smartList {
            let smartList = try context.smartList(selector)
            let ids = try context.read.fetchSmartListTaskIDs(
                id: smartList.id, includeCompleted: input.includeCompleted || input.view == .completed)
            let matching = Set(ids)
            tasks = tasks.filter { matching.contains($0.id) }
        }
        if let selector = input.section, let list = scopedLists.first {
            let section = try context.section(selector, list: list, in: catalog)
            tasks = tasks.filter { $0.sectionID == section.id }
        }
        if let tags = input.tag?.map({ TaskMutation.normalizeTag($0).lowercased() }) {
            tasks = tasks.filter { task in
                let own = Set(task.tags.map { $0.lowercased() })
                return tags.allSatisfy(own.contains)
            }
        }
        if let parent = input.parent {
            let resolved = try context.task(parent, in: catalog)
            tasks = tasks.filter { $0.parentID == resolved.id }
        }
        if let search = input.search {
            let words = NameMatcher.normalize(search).split(separator: " ").map(String.init)
            tasks = tasks.filter { task in
                let text = NameMatcher.normalize(
                    [task.title, task.notes ?? "", task.tags.joined(separator: " "), task.url ?? ""].joined(
                        separator: " "))
                return words.allSatisfy(text.contains)
            }
        }
        let from = input.from?.date
        let to = input.to.map { $0.hasTime ? $0.date : filter.calendar.date(byAdding: .day, value: 1, to: $0.date)! }
        if from != nil || to != nil {
            tasks = tasks.filter { task in
                guard let date = input.view == .completed ? task.completionDate : task.due?.date else { return false }
                return (from.map { date >= $0 } ?? true) && (to.map { date < $0 } ?? true)
            }
        }
        let listRank = Dictionary(catalog.lists.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        func manual(_ lhs: ReminderTaskSnapshot, _ rhs: ReminderTaskSnapshot) -> Bool {
            (listRank[lhs.listID] ?? 0, lhs.order) < (listRank[rhs.listID] ?? 0, rhs.order)
        }
        switch input.view {
        case .today, .scheduled, .overdue:
            tasks.sort { lhs, rhs in
                let left = lhs.due?.date ?? .distantFuture
                let right = rhs.due?.date ?? .distantFuture
                return left != right ? left < right : manual(lhs, rhs)
            }
        case .completed:
            tasks.sort { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        default:
            tasks.sort(by: manual)
        }
        let total = tasks.count
        let sections =
            scopedLists.count == 1 && !scopedLists[0].isGroup
            ? catalog.sections.filter { $0.listID == scopedLists[0].id }.map(\.title) : []
        return TasksOutput(
            view: input.view.rawValue, count: min(total, input.limit), total: total > input.limit ? total : nil,
            sections: sections.isEmpty ? nil : sections,
            tasks: tasks.prefix(input.limit).map { TaskItem($0, catalog: catalog) },
            warnings: catalog.warnings.isEmpty ? nil : catalog.warnings)
    }
}

extension ViewFilter {
    /// Whether a completed task would match `view` if it were open (for includeCompleted).
    static func withoutCompletion(_ task: ReminderTaskSnapshot, _ view: TaskView, _ filter: ViewFilter) -> Bool {
        switch view {
        case .today: return filter.isDueByToday(task)
        case .scheduled, .overdue: return task.due != nil
        case .flagged: return task.isFlagged
        case .assigned: return task.assigneeID != nil
        default: return true
        }
    }
}

enum GetTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: [String]
    }

    static let path = ["task", "get"]
    static let summary = "Full details of tasks: subtasks, alarms, recurrence, early alert, attachments, dates."
    static let params: [Param] = [.list("task", "Task names or ids.", required: true, positional: true)]
    static let examples = ["task get 'Pay rent'", "task get REMCDReminder:5F0E2C6A-1111-2222-3333-444455556666"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchResult<TaskDetail> {
        let catalog = try context.catalog()
        return Batch.run(input.task, label: { $0 }) { selector in
            TaskDetail(try context.task(selector, in: catalog), catalog: catalog)
        }
    }
}

enum ListTags: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: [String]?
    }

    static let path = ["tags"]
    static let summary = "All tags (as in the app's sidebar), with how many open and completed tasks carry each."
    static let params: [Param] = [.list("list", "Only count tasks in these lists.")]
    static let examples = ["tags"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> TagsOutput {
        var scope: Set<String>?
        if let selectors = input.list {
            let lists = try context.catalog(taskLists: [])
            scope = Set(try selectors.map { try context.list($0, in: lists).id })
        }
        let catalog = try context.catalog(taskLists: scope)
        var counts: [String: (name: String, open: Int, completed: Int)] = [:]
        for task in catalog.tasks {
            for tag in task.tags {
                var entry = counts[tag.lowercased()] ?? (tag, 0, 0)
                if task.isCompleted { entry.completed += 1 } else { entry.open += 1 }
                counts[tag.lowercased()] = entry
            }
        }
        // Tags the sidebar shows without any current task (scoped requests count tasks only).
        if scope == nil {
            for name in try context.read.fetchTagNames() where counts[name.lowercased()] == nil {
                counts[name.lowercased()] = (name, 0, 0)
            }
        }
        let tags = counts.values.sorted {
            $0.open != $1.open
                ? $0.open > $1.open : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return TagsOutput(
            tags: tags.map { .init(name: $0.name, open: $0.open, completed: $0.completed == 0 ? nil : $0.completed) })
    }
}

/// `task_create` and `task_update` share these field parameters.
private let fieldParams: [Param] = [
    TaskParams.due, TaskParams.start, TaskParams.notes, TaskParams.url, TaskParams.priority, TaskParams.flagged,
    TaskParams.tags,
    TaskParams.parent, TaskParams.repeats, TaskParams.repeatUntil, TaskParams.repeatCount, TaskParams.alarms,
    TaskParams.earlyAlert, TaskParams.location,
]

enum CreateTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var title: [String]?
        var items: [JSONValue]?
        var fields: TaskFields

        enum CodingKeys: String, CodingKey { case title, items }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent([String].self, forKey: .title)
            items = try container.decodeIfPresent([JSONValue].self, forKey: .items)
            fields = try TaskFields.decode(decoder, excluding: ["title", "items"])
        }
    }

    static let path = ["task", "create"]
    static let summary =
        "Create tasks (quick capture or many at once). Titles share the given fields; 'items' give each task its own."
    static let effect = OperationEffect.write
    static let params: [Param] =
        [
            .list("title", "Titles; each gets the shared fields.", positional: true),
            Param(
                "items", .array(.object),
                "Tasks with their own fields (same keys as this tool, title as a string), e.g. "
                    + "[{\"title\":\"Call\",\"due\":\"friday\"}]."),
            .string("list", "List (name or id). Default: config, else the app's default."),
            .string("section", "Section of that list."),
        ] + fieldParams + [TaskParams.position]
    static let examples = [
        "task create 'Buy milk' 'Call the bank' --list Inbox",
        "task create 'Submit report' --due 'friday 17:00' --priority high --early-alert 1d --tags work",
        "task create 'Water plants' --repeats 'every 3 days' --due today",
        "task create --json '{\"items\":[{\"title\":\"Pack\",\"section\":\"Before\"},{\"title\":\"Passport\",\"parent\":\"Pack\"}],\"list\":\"Trip\"}'",
    ]

    static func entries(_ input: Input) throws -> [(JSONValue, TaskFields)] {
        let items =
            try (input.title ?? []).map { (JSONValue.string($0), TaskFields(title: $0)) }
            + TaskFields.items(input.items, allowed: params.filter { $0.name != "items" }, extra: [])
        guard !items.isEmpty else {
            throw AgentError.invalid("Give at least one title, or items.", hint: "Example: task create 'Buy milk'.")
        }
        for (_, item) in items {
            let merged = input.fields.merged(with: item)
            guard merged.title?.trimmingCharacters(in: .whitespaces).isEmpty == false else {
                throw AgentError.invalid("Every item needs a title.")
            }
            try MutationBuilder.validateOffline(merged)
        }
        return items
    }

    static func validate(_ input: Input) throws { _ = try entries(input) }

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchOutput<TaskDetail> {
        let items = try entries(input)
        var catalog = try context.catalog()
        // Items are created in order, so later items may name earlier ones as their parent.
        let batch = Batch.run(Array(items.enumerated()), label: { $0.element.1.title ?? $0.element.0.compactText() }) {
            entry -> TaskDetail in
            var fields = input.fields.merged(with: entry.element.1)
            let title = fields.title!
            let list: ReminderListSnapshot
            if fields.list == nil, let parent = fields.parent {
                let resolved = try context.task(parent, in: catalog)
                list = catalog.list(resolved.listID)!
                fields.parent = resolved.id
            } else {
                list = try context.targetList(fields.list, in: catalog)
            }
            let builder = MutationBuilder(context: context, catalog: catalog)
            let mutation = try builder.mutation(fields, task: nil, list: list)
            let task = try context.write.createTask(listID: list.id, title: title, mutation: mutation)
            catalog = try context.catalog(taskLists: [task.listID]).merging(into: catalog)
            return TaskDetail(task, catalog: catalog)
        }
        return BatchOutput(batch, backup: nil)
    }
}

extension ReminderCatalog {
    /// `self` (a fresh read of some lists) replacing those lists' content in `older`.
    func merging(into older: ReminderCatalog) -> ReminderCatalog {
        let fresh = Set(tasks.map(\.listID) + sections.map(\.listID))
        return ReminderCatalog(
            accounts: accounts, lists: lists,
            sections: older.sections.filter { !fresh.contains($0.listID) } + sections,
            tasks: older.tasks.filter { !fresh.contains($0.listID) } + tasks, warnings: warnings)
    }
}

enum UpdateTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: [String]?
        var items: [JSONValue]?
        var fields: TaskFields

        enum CodingKeys: String, CodingKey { case task, items }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            task = try container.decodeIfPresent([String].self, forKey: .task)
            items = try container.decodeIfPresent([JSONValue].self, forKey: .items)
            fields = try TaskFields.decode(decoder, excluding: ["task", "items"])
        }
    }

    static let path = ["task", "update"]
    static let summary =
        "Change tasks: rename, dates, notes, priority, flag, tags, recurrence, alerts; move to another list, "
        + "section or parent (indent/outdent) and reorder. Same changes for every 'task', or per-task 'items'."
    static let effect = OperationEffect.write
    static let params: [Param] =
        [
            .list("task", "Tasks (names or ids); each gets the shared changes.", positional: true),
            Param(
                "items", .array(.object),
                "Per-task changes (same keys as this tool, task as a string), e.g. "
                    + "[{\"task\":\"Gym\",\"flagged\":true}]."),
            .string("title", "New title (one task)."),
            .string("list", "Move to this list."),
            .string("section", "Move to this section."),
        ] + fieldParams + [
            .list("addTags", "Tags to add."),
            .list("removeTags", "Tags to remove."),
            Param("completed", .boolean, "Completed or not."),
            TaskParams.position, TaskParams.before, TaskParams.after,
            .list(
                "clear", "Fields to remove (section = out of its section, parent = outdent).",
                of: .choice(ClearField.allCases.map(\.rawValue))),
        ]
    static let examples = [
        "task update 'Pay rent' --due 'monday 9:00' --flagged",
        "task update 'Buy milk' 'Buy eggs' --list Groceries --section Dairy",
        "task update Passport --parent Pack", "task update Passport --clear parent --position top",
        "task update 'Old idea' --add-tags someday --clear due",
        "task update --json '{\"items\":[{\"task\":\"A\",\"due\":\"today\"},{\"task\":\"B\",\"priority\":\"high\"}]}'",
    ]

    static func validate(_ input: Input) throws { _ = try entries(input) }

    static func entries(_ input: Input) throws -> [(String, TaskFields)] {
        var items = (input.task ?? []).map { ($0, TaskFields()) }
        for (value, fields) in try TaskFields.items(
            input.items, allowed: params.filter { $0.name != "items" }, extra: [])
        {
            guard let selector = value["task"]?.stringValue else {
                throw AgentError.invalid("Every item needs 'task' (a name or id).")
            }
            items.append((selector, fields))
        }
        guard !items.isEmpty else { throw AgentError.invalid("Give at least one task, or items.") }
        if input.fields.title != nil, items.count > 1 {
            throw AgentError.invalid("title renames a single task; use items to rename several.")
        }
        for (selector, fields) in items {
            let merged = input.fields.merged(with: fields)
            try MutationBuilder.validateOffline(merged)
            if merged.isEmpty {
                throw AgentError.invalid(
                    "Nothing to change for '\(selector)'.", hint: "Give at least one field, e.g. --due friday.")
            }
        }
        return items
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchOutput<TaskDetail> {
        let items = try entries(input)
        let catalog = try context.catalog()
        let resolved = items.map { selector, fields in
            (selector, fields, Result { try context.task(selector, in: catalog) })
        }
        let backup = try BulkBackup.saveIfNeeded(
            "update", resolved.compactMap { try? $0.2.get() }, catalog: catalog, context: context)
        let batch = Batch.run(resolved, label: { $0.0 }) { selector, item, task -> TaskDetail in
            let task = try task.get()
            let fields = input.fields.merged(with: item)
            let target = try fields.list.map { try context.list($0, in: catalog) } ?? catalog.list(task.listID)!
            let mutation = try MutationBuilder(context: context, catalog: catalog).mutation(
                fields, task: task, list: target)
            // Asking for the current state (e.g. moving to the list it is already in) is a no-op.
            guard mutation.hasChanges else { return TaskDetail(task, catalog: catalog) }
            let result = try context.write.updateTask(id: task.id, mutation: mutation)
            let fresh = try context.catalog(taskLists: [task.listID, result.task.listID])
            return TaskDetail(result.task, catalog: fresh)
        }
        return BatchOutput(batch, backup: backup)
    }
}

enum BulkBackup {
    /// Saves a backup when more than `BackupStore.bulkThreshold` tasks are about to change.
    static func saveIfNeeded(
        _ operation: String, _ tasks: [ReminderTaskSnapshot], catalog: ReminderCatalog, context: RemindersContext,
        force: Bool = false
    ) throws -> String? {
        guard force || tasks.count > BackupStore.bulkThreshold else { return nil }
        let ids = Set(tasks.map(\.id))
        // Include subtasks: deleting or moving a parent affects them too.
        let affected = catalog.tasks.filter { ids.contains($0.id) || $0.parentID.map(ids.contains) == true }
        return try context.backups.save(operation: operation, tasks: affected, catalog: catalog)
    }
}

struct CompletionResult: Encodable, Sendable {
    let id: String
    let title: String
    let list: String
    let completed: Bool
    /// For recurring tasks: the next due date the series moved to.
    let nextDue: String?
}

enum CompleteTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: [String]
        var undo: Bool
    }

    static let path = ["task", "complete"]
    static let summary =
        "Mark tasks completed (recurring tasks move to their next date, as in the app), or not completed with undo."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .list("task", "Tasks (names or ids).", required: true, positional: true),
        .boolean("undo", "Mark the tasks not completed instead."),
    ]
    static let examples = ["task complete 'Buy milk' 'Call the bank'", "task complete 'Buy milk' --undo"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchOutput<CompletionResult> {
        let catalog = try context.catalog()
        let resolved = context.tasks(input.task, in: catalog)
        let backup = try BulkBackup.saveIfNeeded(
            input.undo ? "uncomplete" : "complete", resolved.compactMap { try? $0.1.get() }, catalog: catalog,
            context: context)
        let batch = Batch.run(resolved, label: { $0.0 }) { _, task -> CompletionResult in
            let task = try task.get()
            let write = try context.write.updateTask(id: task.id, mutation: TaskMutation(completed: !input.undo))
            return CompletionResult(
                id: task.id, title: task.title, list: catalog.list(task.listID)?.title ?? task.listID,
                completed: !input.undo, nextDue: write.advancedRecurrence ? write.task.due?.text() : nil)
        }
        return BatchOutput(batch, backup: backup)
    }
}

enum DeleteTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: [String]
    }

    static let path = ["task", "delete"]
    static let summary =
        "Delete tasks (with their subtasks) by exact name or id. More than 5 tasks are backed up first for task_restore."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [.list("task", "Tasks (exact names or ids).", required: true, positional: true)]
    static let examples = ["task delete 'Old idea'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchOutput<DeletedItem> {
        let catalog = try context.catalog()
        let resolved = context.tasks(input.task, in: catalog, policy: .exactName)
        let backup = try BulkBackup.saveIfNeeded(
            "delete", resolved.compactMap { try? $0.1.get() }, catalog: catalog, context: context)
        // Parents first: deleting a parent deletes its subtasks, which then need no call of their own.
        let ordered = resolved.sorted { lhs, rhs in
            ((try? lhs.1.get().parentID) == nil ? 0 : 1) < ((try? rhs.1.get().parentID) == nil ? 0 : 1)
        }
        var deleted = Set<String>()
        let batch = Batch.run(ordered, label: { $0.0 }) { _, task -> DeletedItem in
            let task = try task.get()
            if let parent = task.parentID, deleted.contains(parent) {
                return DeletedItem(id: task.id, title: task.title, deleted: true)
            }
            try context.write.deleteTask(id: task.id)
            deleted.insert(task.id)
            return DeletedItem(id: task.id, title: task.title, deleted: true)
        }
        return BatchOutput(batch, backup: backup)
    }
}

struct RestoredItem: Encodable, Sendable {
    let id: String
    let title: String
    let list: String
    /// restored = recreated (new id); reverted = existing task set back to the backup's values.
    let action: String
    let previousId: String?
}

enum RestoreTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var backup: String
    }

    static let path = ["task", "restore"]
    static let summary =
        "Undo a bulk change from its backup: recreate deleted tasks, set changed tasks back to their saved values."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("backup", "Backup path from a result's 'backup' field, or 'latest'.", required: true, positional: true)
    ]
    static let examples = ["task restore latest"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchOutput<RestoredItem> {
        let (_, file) = try context.backups.load(input.backup)
        var catalog = try context.catalog()
        var newIDs: [String: String] = [:]
        // Parents first, so recreated subtasks can attach to recreated parents.
        let entries = file.tasks.sorted { ($0.task.parentID == nil ? 0 : 1) < ($1.task.parentID == nil ? 0 : 1) }
        let batch = Batch.run(entries, label: { $0.task.title }) { entry -> RestoredItem in
            let saved = entry.task
            let list = try catalog.list(saved.listID) ?? context.list(entry.list, in: catalog, policy: .exactName)
            let section =
                catalog.section(saved.sectionID ?? "")
                ?? entry.section.flatMap { try? context.section($0, list: list, in: catalog, policy: .exactName) }
            var mutation = TaskMutation(
                notes: saved.notes.map(FieldChange.set) ?? .clear, url: saved.url.map(FieldChange.set) ?? .clear,
                due: saved.due.map(FieldChange.set) ?? .clear, priority: saved.priority, flagged: saved.isFlagged,
                completed: saved.isCompleted, tags: saved.tags)
            if let existing = catalog.task(saved.id) {
                mutation.title = saved.title
                if existing.listID != list.id { mutation.listID = list.id }
                if existing.sectionID != section?.id, saved.parentID == nil {
                    mutation.section = section.map { .set($0.id) } ?? .clear
                }
                let result = try context.write.updateTask(id: saved.id, mutation: mutation)
                return RestoredItem(
                    id: saved.id, title: result.task.title, list: list.title, action: "reverted", previousId: nil)
            }
            mutation.completed = saved.isCompleted ? true : nil
            if let rule = saved.recurrence, let frequency = RecurrenceMutation.Frequency(rawValue: rule.frequency) {
                mutation.recurrence = .set(
                    try RecurrenceMutation(
                        frequency: frequency, interval: rule.interval, weekdays: rule.weekdays,
                        daysOfMonth: rule.daysOfMonth, endDate: rule.endDate, count: rule.count))
            }
            mutation.earlyAlert = saved.earlyAlert.map(FieldChange.set)
            for alarm in saved.alarms {
                switch alarm {
                case .date(let date): mutation.alarms.append(date)
                case .location(let title, let address, let latitude, let longitude, let radius, let proximity):
                    mutation.location = .set(
                        try ReminderLocationMutation(
                            title: title ?? address ?? "Location", address: address, latitude: latitude,
                            longitude: longitude, radius: radius,
                            proximity: ReminderLocationProximity(rawValue: proximity) ?? .arriving))
                case .relative: break
                }
            }
            if let parent = saved.parentID {
                mutation.parent = .set(newIDs[parent] ?? parent)
            } else if let section {
                mutation.section = .set(section.id)
            }
            let created = try context.write.createTask(listID: list.id, title: saved.title, mutation: mutation)
            newIDs[saved.id] = created.id
            catalog = try context.catalog(taskLists: [list.id]).merging(into: catalog)
            return RestoredItem(
                id: created.id, title: created.title, list: list.title, action: "restored", previousId: saved.id)
        }
        return BatchOutput(batch, backup: nil)
    }
}
