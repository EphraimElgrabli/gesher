import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

@main
enum RemindersCli {
    static func main() { RemindersApp.make().main() }
}

/// The Reminders app: its operations, defaults and shared dependencies. See AGENTS.md.
enum RemindersApp {
    static func make(context: @escaping () throws -> RemindersContext = { RemindersContext() })
        -> AgentApp<RemindersContext>
    {
        AgentApp(
            name: "reminders",
            summary: "Apple Reminders: lists, groups, sections, tasks, tags and smart views.",
            instructions: """
                Lists, sections and tasks accept a name or an id (names match ignoring case, accents and emoji; \
                ambiguous names fail with candidates — retry with an id). Start with `lists` for the sidebar \
                and counts, `tasks` for any view or search. Dates are natural ('today', 'friday 18:00', \
                '2026-11-05'); a date without a time makes an all-day due date. Several tasks can be created, \
                updated, completed or deleted in one call; each item reports its own result. Bulk changes of \
                more than 5 tasks save a backup first (see `backup` in the result; `task_restore` undoes).
                """,
            permission: .reminders,
            operations: [
                AnyOperation(ListLists.self),
                AnyOperation(ListTasks.self),
                AnyOperation(GetTasks.self),
                AnyOperation(ListTags.self),
                AnyOperation(CreateTasks.self),
                AnyOperation(UpdateTasks.self),
                AnyOperation(CompleteTasks.self),
                AnyOperation(DeleteTasks.self),
                AnyOperation(RestoreTasks.self),
                AnyOperation(ListDeletedTasks.self),
                AnyOperation(PurgeTasks.self),
                AnyOperation(CreateList.self),
                AnyOperation(UpdateList.self),
                AnyOperation(DeleteList.self),
                AnyOperation(CreateSections.self),
                AnyOperation(UpdateSection.self),
                AnyOperation(DeleteSections.self),
                AnyOperation(AddAttachments.self),
                AnyOperation(RemoveAttachment.self),
                AnyOperation(ExportAttachments.self),
                AnyOperation(ListSmartLists.self),
                AnyOperation(CreateSmartList.self),
                AnyOperation(UpdateSmartList.self),
                AnyOperation(DeleteSmartList.self),
                AnyOperation(ListTemplates.self),
                AnyOperation(CreateTemplate.self),
                AnyOperation(ApplyTemplate.self),
                AnyOperation(DeleteTemplate.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Reminders operation for the life of the process (or MCP
/// session). Repositories re-read native state on every call; nothing here caches user data.
final class RemindersContext {
    let read: ReminderReadRepository
    let write: ReminderWriteRepository
    let config: UserConfig
    let backups: BackupStore

    init(config: UserConfig = .load(), backups: BackupStore = BackupStore()) {
        let runtime = ReminderKitRuntime()
        read = ReminderReadRepository(runtime: runtime)
        write = ReminderWriteRepository(runtime: runtime, readRepository: read)
        self.config = config
        self.backups = backups
    }

    init(read: ReminderReadRepository, write: ReminderWriteRepository, config: UserConfig, backups: BackupStore) {
        self.read = read
        self.write = write
        self.config = config
        self.backups = backups
    }

    func catalog(taskLists: Set<String>? = nil) throws -> ReminderCatalog {
        try read.fetchCatalog(taskLists: taskLists)
    }

    // MARK: - Selectors

    func list(
        _ selector: String, in catalog: ReminderCatalog, policy: MatchPolicy = .fuzzy, groups: Bool? = false
    ) throws -> ReminderListSnapshot {
        let candidates = catalog.lists.filter { groups == nil || $0.isGroup == groups }
        return try EntityResolver.resolve(
            selector, in: candidates, type: groups == true ? "group" : "list", id: \.id, name: \.title,
            detail: { list in list.groupID.flatMap { catalog.list($0)?.title }.map { "in \($0)" } }, policy: policy)
    }

    /// Explicit list > configured `reminders.list` > the native default list > the first list.
    func targetList(_ selector: String?, in catalog: ReminderCatalog) throws -> ReminderListSnapshot {
        if let selector { return try list(selector, in: catalog) }
        if let configured = config.value("reminders", "list") { return try list(configured, in: catalog) }
        if let id = try read.fetchDefaultListID(), let native = catalog.list(id), !native.isGroup { return native }
        guard let first = catalog.lists.first(where: { !$0.isGroup }) else {
            throw AgentError(
                code: "not_found", message: "There are no Reminders lists.", hint: "Create one with list_create.")
        }
        return first
    }

    func section(
        _ selector: String, list: ReminderListSnapshot, in catalog: ReminderCatalog, policy: MatchPolicy = .fuzzy
    ) throws -> ReminderSectionSnapshot {
        try EntityResolver.resolve(
            selector, in: catalog.sections.filter { $0.listID == list.id }, type: "section in \(list.title)",
            id: \.id, name: \.title, policy: policy)
    }

    /// Resolves a task name or id. Names prefer open tasks, then completed ones.
    func task(
        _ selector: String, in catalog: ReminderCatalog, scope: ReminderListSnapshot? = nil,
        policy: MatchPolicy = .fuzzy
    ) throws -> ReminderTaskSnapshot {
        let scoped = catalog.tasks.filter { scope == nil || $0.listID == scope!.id }
        if let exact = scoped.first(where: { $0.id == selector }) { return exact }
        let detail: (ReminderTaskSnapshot) -> String? = { task in
            let list = catalog.list(task.listID)?.title ?? ""
            return task.isCompleted ? "\(list), completed" : list
        }
        do {
            return try EntityResolver.resolve(
                selector, in: scoped.filter { !$0.isCompleted }, type: "task", id: \.id, name: \.title, detail: detail,
                policy: policy)
        } catch let error as AgentError where error.code == "not_found" {
            return try EntityResolver.resolve(
                selector, in: scoped, type: "task", id: \.id, name: \.title, detail: detail, policy: policy)
        }
    }

    /// Tasks for many selectors: a name or id per entry, resolved against one catalog read.
    func tasks(_ selectors: [String], in catalog: ReminderCatalog, policy: MatchPolicy = .fuzzy) -> [(
        String, Result<ReminderTaskSnapshot, Error>
    )] {
        selectors.map { selector in
            (selector, Result { try task(selector, in: catalog, policy: policy) })
        }
    }
}
