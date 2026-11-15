import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

struct DeletedTaskItem: Encodable, Sendable {
    let id: String
    let title: String
    let completed: Bool?
    let modified: String?

    init(_ task: ReminderDeletedTaskSnapshot) {
        id = task.id
        title = task.title
        completed = task.isCompleted ? true : nil
        modified = task.modifiedDate.map { DateOutput.iso($0) }
    }
}

enum ListDeletedTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var search: String?
        var limit: Int
    }

    struct Output: Encodable, Sendable {
        let count: Int
        let total: Int?
        let tasks: [DeletedTaskItem]
    }

    static let path = ["deleted-tasks"]
    static let summary = "Tasks in Recently Deleted (kept about 30 days); task_purge erases them for good."
    static let params: [Param] = [
        .string("search", "Words to find in titles.", positional: true),
        .integer("limit", "Maximum tasks to return.", default: 200, min: 1, max: 2000),
    ]
    static let examples = ["deleted-tasks", "deleted-tasks dentist"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> Output {
        var tasks = try context.read.fetchRecentlyDeletedTasks()
        if let search = input.search {
            let words = NameMatcher.normalize(search).split(separator: " ").map(String.init)
            tasks = tasks.filter { task in words.allSatisfy(NameMatcher.normalize(task.title).contains) }
        }
        return Output(
            count: min(tasks.count, input.limit), total: tasks.count > input.limit ? tasks.count : nil,
            tasks: tasks.prefix(input.limit).map(DeletedTaskItem.init))
    }
}

enum PurgeTasks: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: [String]
    }

    static let path = ["task", "purge"]
    static let summary = "Erase tasks from Recently Deleted for good (exact titles or ids from deleted_tasks)."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("task", "Deleted tasks (exact titles or ids).", required: true, positional: true)
    ]
    static let examples = ["task purge 'Old idea'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> BatchOutput<DeletedItem> {
        let deleted = try context.read.fetchRecentlyDeletedTasks()
        let resolved = input.task.map { selector in
            (
                selector,
                Result {
                    try EntityResolver.resolve(
                        selector, in: deleted, type: "recently deleted task", id: \.id, name: \.title,
                        policy: .exactName)
                }
            )
        }
        let targets = resolved.compactMap { try? $0.1.get() }
        var failure: Error?
        if !targets.isEmpty {
            do { try context.write.purgeDeletedTasks(ids: Array(Set(targets.map(\.id)))) } catch { failure = error }
        }
        let batch = Batch.run(resolved, label: { $0.0 }) { _, task -> DeletedItem in
            let task = try task.get()
            if let failure { throw failure }
            return DeletedItem(id: task.id, title: task.title, deleted: true)
        }
        return BatchOutput(batch, backup: nil)
    }
}
