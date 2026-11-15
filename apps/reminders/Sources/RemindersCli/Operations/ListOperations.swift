import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

enum ListLists: AgentOperation {
    struct Input: Decodable, Sendable {
        var sections: Bool
        var completed: Bool
    }

    static let path = ["lists"]
    static let summary =
        "The Reminders sidebar: smart-view counts (today, scheduled, overdue, flagged, all), groups, and lists "
        + "with open-task counts, color, emoji and sharing."
    static let params: [Param] = [
        .boolean("sections", "Include each list's sections with open-task counts."),
        .boolean("completed", "Include completed-task counts per list."),
    ]
    static let examples = ["lists", "lists --sections"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> ListsOutput {
        let catalog = try context.catalog()
        let filter = ViewFilter()
        let open = catalog.tasks.filter { !$0.isCompleted }
        let byList = Dictionary(grouping: catalog.tasks, by: \.listID)
        func count(_ view: TaskView) -> Int { catalog.tasks.filter { filter.matches($0, view: view) }.count }
        let assigned = count(.assigned)
        let views = ListsOutput.Views(
            today: count(.today), scheduled: count(.scheduled), overdue: count(.overdue), flagged: count(.flagged),
            all: open.count, assigned: assigned == 0 ? nil : assigned, completed: count(.completed))
        let groups = catalog.lists.filter(\.isGroup).map { group in
            GroupItem(
                id: group.id, name: group.title,
                lists: catalog.lists.filter { $0.groupID == group.id }.map(\.title))
        }
        let lists = catalog.lists.filter { !$0.isGroup }.map { list -> ListItem in
            let tasks = byList[list.id] ?? []
            let openTasks = tasks.filter { !$0.isCompleted }
            let overdue = openTasks.filter { $0.isOverdue() }.count
            let flagged = openTasks.filter(\.isFlagged).count
            let completed = tasks.count - openTasks.count
            let sections =
                input.sections
                ? catalog.sections.filter { $0.listID == list.id }.map { section in
                    ListItem.Section(
                        id: section.id, name: section.title,
                        open: openTasks.filter { $0.sectionID == section.id }.count)
                } : nil
            let sharees = list.sharees.compactMap { $0.name ?? $0.address }
            return ListItem(
                id: list.id, name: list.title, group: list.groupID.flatMap { catalog.list($0)?.title },
                open: openTasks.count, overdue: overdue == 0 ? nil : overdue, flagged: flagged == 0 ? nil : flagged,
                completed: input.completed ? completed : nil, color: list.colorHex, emoji: list.emoji,
                shared: list.isShared ? true : nil, owner: list.isSharedToMe ? list.sharedOwner : nil,
                sharedWith: sharees.isEmpty ? nil : sharees, sections: sections)
        }
        let defaultList = (try? context.targetList(nil, in: catalog))?.title
        return ListsOutput(
            views: views, defaultList: defaultList, groups: groups.isEmpty ? nil : groups, lists: lists,
            warnings: catalog.warnings.isEmpty ? nil : catalog.warnings)
    }
}

private let colorParam = Param.string("color", "Hex color, e.g. #FF9500 (names are not accepted).")
private let emojiParam = Param.string("emoji", "One emoji, or a Reminders symbol name such as 'cart'.")

enum CreateList: AgentOperation {
    enum Kind: String, Decodable, Sendable { case list, group }

    struct Input: Decodable, Sendable {
        var name: String
        var kind: Kind
        var group: String?
        var color: String?
        var emoji: String?
        var lists: [String]?
    }

    static let path = ["list", "create"]
    static let summary = "Create a list (optionally inside a group), or a group (folder) of lists."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("name", "Name of the new list or group.", required: true, positional: true),
        .choice("kind", ["list", "group"], "What to create.", default: "list"),
        .string("group", "Put the new list in this group."),
        colorParam, emojiParam,
        .list("lists", "For kind=group: existing lists to move into the new group."),
    ]
    static let examples = [
        "list create Groceries --emoji 🛒 --color '#34C759'", "list create Home --kind group --lists Groceries",
        "list create 'Trip to Rome' --group Personal",
    ]

    static func validate(_ input: Input) throws {
        if let color = input.color { _ = try ReminderColor.agentValidated(color) }
        if input.kind == .group, input.group != nil {
            throw AgentError.invalid("Groups cannot be nested.", hint: "Drop --group, or use --kind list.")
        }
        if input.kind == .list, input.lists != nil {
            throw AgentError.invalid("lists applies to --kind group.")
        }
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> ListResult {
        let catalog = try context.catalog(taskLists: [])
        let group = try input.group.map { try context.list($0, in: catalog, groups: true) }
        let members = try (input.lists ?? []).map { try context.list($0, in: catalog) }
        let account =
            group?.accountID ?? catalog.accounts.first(where: { $0.isDefault == true })?.id
            ?? catalog.accounts.first?.id
        guard let account else { throw AgentError(code: "not_found", message: "No Reminders account is available.") }
        let created = try context.write.createList(
            accountID: account, name: input.name, emoji: input.emoji, colorHex: input.color, groupID: group?.id,
            isGroup: input.kind == .group)
        for member in members { _ = try context.write.updateList(id: member.id, group: .set(created.id)) }
        return ListResult(created, catalog: try context.catalog(taskLists: []))
    }
}

extension ReminderColor {
    static func agentValidated(_ text: String) throws -> ReminderColor {
        do { return try ReminderColor(text) } catch { throw AgentError.invalid(error.localizedDescription) }
    }
}

enum UpdateList: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: String
        var name: String?
        var color: String?
        var emoji: String?
        var group: String?
        var ungroup: Bool
    }

    static let path = ["list", "update"]
    static let summary = "Rename or restyle a list or group, or move a list into a group (or out with ungroup)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("list", "List or group (name or id).", required: true, positional: true),
        .string("name", "New name."),
        colorParam, emojiParam,
        .string("group", "Move the list into this group."),
        .boolean("ungroup", "Move the list out of its group."),
    ]
    static let examples = [
        "list update Groceries --name Shopping", "list update Shopping --color '#FF2D55' --emoji 🛍️",
        "list update Shopping --group Home", "list update Shopping --ungroup",
    ]

    static func validate(_ input: Input) throws {
        if let color = input.color { _ = try ReminderColor.agentValidated(color) }
        guard input.group == nil || !input.ungroup else { throw AgentError.invalid("Use group or ungroup, not both.") }
        guard input.name != nil || input.color != nil || input.emoji != nil || input.group != nil || input.ungroup
        else {
            throw AgentError.invalid("Nothing to change.", hint: "Give name, color, emoji, group or ungroup.")
        }
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> ListResult {
        let catalog = try context.catalog(taskLists: [])
        let list = try context.list(input.list, in: catalog, groups: nil)
        let group = try input.group.map { try context.list($0, in: catalog, groups: true) }
        if list.isGroup, group != nil || input.ungroup { throw AgentError.invalid("Groups cannot be nested.") }
        let change: FieldChange<String>? = group.map { .set($0.id) } ?? (input.ungroup ? .clear : nil)
        let updated = try context.write.updateList(
            id: list.id, name: input.name, emoji: input.emoji, colorHex: input.color,
            group: list.groupID == group?.id && group != nil ? nil : change)
        return ListResult(updated, catalog: try context.catalog(taskLists: []))
    }
}

struct ListDeletion: Encodable, Sendable {
    let id: String
    let name: String
    let kind: String
    let deletedTasks: Int?
    let ungroupedLists: [String]?
    let backup: String?
}

enum DeleteList: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: String
    }

    static let path = ["list", "delete"]
    static let summary =
        "Delete a list with all its tasks (backed up first for task_restore), or a group (its lists are kept and ungrouped)."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [.string("list", "Exact list or group name, or id.", required: true, positional: true)]
    static let examples = ["list delete 'Old project'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> ListDeletion {
        let lists = try context.catalog(taskLists: [])
        let list = try context.list(input.list, in: lists, policy: .exactName, groups: nil)
        if list.isGroup {
            let members = lists.lists.filter { $0.groupID == list.id }.map(\.title)
            try context.write.deleteList(id: list.id)
            return ListDeletion(
                id: list.id, name: list.title, kind: "group", deletedTasks: nil,
                ungroupedLists: members.isEmpty ? nil : members, backup: nil)
        }
        let catalog = try context.catalog(taskLists: [list.id])
        let tasks = catalog.tasks.filter { $0.listID == list.id }
        let backup = try BulkBackup.saveIfNeeded(
            "list-delete", tasks, catalog: catalog, context: context, force: !tasks.isEmpty)
        try context.write.deleteList(id: list.id)
        return ListDeletion(
            id: list.id, name: list.title, kind: "list", deletedTasks: tasks.count, ungroupedLists: nil,
            backup: backup)
    }
}

enum CreateSections: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: String
        var name: [String]
    }

    static let path = ["section", "create"]
    static let summary = "Add sections to a list, in the given order."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("list", "List (name or id).", required: true),
        .list("name", "Section names.", required: true, positional: true),
    ]
    static let examples = ["section create --list 'Trip to Rome' Packing 'Before leaving'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchResult<SectionResult> {
        let catalog = try context.catalog(taskLists: [])
        let list = try context.list(input.list, in: catalog)
        return Batch.run(input.name, label: { $0 }) { name in
            let section = try context.write.createSection(listID: list.id, name: name)
            return SectionResult(id: section.id, name: section.title, list: list.title, position: nil)
        }
    }
}

enum UpdateSection: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: String
        var section: String
        var name: String?
        var position: Int?
    }

    static let path = ["section", "update"]
    static let summary = "Rename a section, or move it to a position among the list's sections (1 = first)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("list", "List (name or id).", required: true),
        .string("section", "Section (name or id).", required: true, positional: true),
        .string("name", "New name."),
        .integer("position", "New position, 1 = first.", min: 1),
    ]
    static let examples = [
        "section update --list 'Trip to Rome' Packing --name 'Pack bags'",
        "section update --list 'Trip to Rome' 'Before leaving' --position 1",
    ]

    static func validate(_ input: Input) throws {
        guard input.name != nil || input.position != nil else {
            throw AgentError.invalid("Nothing to change.", hint: "Give name or position.")
        }
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> SectionResult {
        let catalog = try context.catalog(taskLists: nil)
        let list = try context.list(input.list, in: catalog)
        let section = try context.section(input.section, list: list, in: catalog)
        var result = section
        if let name = input.name {
            result = try context.write.renameSection(listID: list.id, id: section.id, name: name)
        }
        var position: Int?
        if let wanted = input.position {
            var order = catalog.sections.filter { $0.listID == list.id }.map(\.id).filter { $0 != section.id }
            order.insert(section.id, at: min(wanted - 1, order.count))
            let sections = try context.write.reorderSections(listID: list.id, orderedIDs: order)
            position = sections.firstIndex { $0.id == section.id }.map { $0 + 1 }
        }
        return SectionResult(id: result.id, name: result.title, list: list.title, position: position)
    }
}

enum DeleteSections: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: String
        var section: [String]
    }

    static let path = ["section", "delete"]
    static let summary = "Delete sections by exact name or id; their tasks stay in the list, outside any section."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("list", "List (name or id).", required: true),
        .list("section", "Exact section names or ids.", required: true, positional: true),
    ]
    static let examples = ["section delete --list 'Trip to Rome' Packing"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchResult<DeletedItem> {
        let catalog = try context.catalog(taskLists: [])
        let list = try context.list(input.list, in: catalog)
        let sections = try context.catalog(taskLists: [list.id])
        return Batch.run(input.section, label: { $0 }) { selector in
            let section = try context.section(selector, list: list, in: sections, policy: .exactName)
            try context.write.deleteSection(listID: list.id, id: section.id)
            return DeletedItem(id: section.id, title: section.title, deleted: true)
        }
    }
}
