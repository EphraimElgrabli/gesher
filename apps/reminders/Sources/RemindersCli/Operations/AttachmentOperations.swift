import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

enum AddAttachments: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: String
        var file: [String]
        var confirmShared: Bool
    }

    static let path = ["attachment", "add"]
    static let summary = "Attach images or files (local paths) to a task; images show as pictures, as in the app."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("task", "Task (name or id).", required: true),
        .list(
            "file", "Paths of the images or files to attach. Hidden, system and key files are refused.",
            required: true, positional: true),
        .boolean(
            "confirmShared",
            "The user confirmed attaching files in a list shared with other people (they will see them)."),
    ]
    static let examples = ["attachment add --task 'Fix the sink' ~/Desktop/leak.jpg"]

    static func files(_ input: Input) throws -> [URL] {
        try input.file.map { try LocalFilePolicy.attachable($0) }
    }

    static func validate(_ input: Input) throws { _ = try files(input) }

    static func run(_ input: Input, _ context: RemindersContext) throws -> TaskDetail {
        let catalog = try context.catalog()
        let task = try context.task(input.task, in: catalog)
        if let list = catalog.list(task.listID), list.isShared || list.isSharedToMe, !input.confirmShared {
            throw AgentError(
                code: "confirmation_required",
                message: "'\(list.title)' is a shared list; files attached to its tasks reach everyone in it.",
                hint:
                    "Ask the user whether to share these files with the list's members, then retry with confirmShared.")
        }
        let updated = try context.write.addAttachments(taskID: task.id, files: try files(input))
        return TaskDetail(updated, catalog: try context.catalog(taskLists: [task.listID]))
    }
}

/// The attachment of `task` named by id or 1-based number (task_get order), or nothing when it has one.
private func attachment(_ selector: String?, of task: ReminderTaskSnapshot, files: Bool) throws
    -> ReminderAttachmentSnapshot
{
    let candidates = task.attachments.filter { !files || $0.kind != "url" }
    guard let selector else {
        guard candidates.count == 1 else {
            throw AgentError.invalid(
                "'\(task.title)' has \(candidates.count) attachments; say which.",
                hint: "Pass attachment: an id from task_get, or its number (1 = first).")
        }
        return candidates[0]
    }
    if let number = Int(selector), candidates.indices.contains(number - 1) { return candidates[number - 1] }
    guard let match = candidates.first(where: { $0.id == selector }) else {
        throw AgentError(
            code: "not_found", message: "'\(task.title)' has no attachment '\(selector)'.",
            hint: "Use an id from task_get, or a number from 1 to \(candidates.count).",
            candidates: candidates.compactMap { $0.id.map { Candidate(id: $0, name: $0) } })
    }
    return match
}

enum RemoveAttachment: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: String
        var attachment: String?
    }

    static let path = ["attachment", "remove"]
    static let summary = "Remove an image, file or link attachment from a task."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("task", "Task (name or id).", required: true),
        .string(
            "attachment", "Attachment id or number (see task_get). Optional if the task has one.", positional: true),
    ]
    static let examples = ["attachment remove --task 'Fix the sink' 1"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> TaskDetail {
        let catalog = try context.catalog()
        let task = try context.task(input.task, in: catalog)
        let target = try attachment(input.attachment, of: task, files: false)
        guard let id = target.id else { throw AgentError(code: "not_found", message: "The attachment has no id.") }
        let updated = try context.write.removeAttachment(taskID: task.id, attachmentID: id)
        return TaskDetail(updated, catalog: try context.catalog(taskLists: [task.listID]))
    }
}

enum ExportAttachments: AgentOperation {
    struct Input: Decodable, Sendable {
        var task: String
        var attachment: String?
        var to: String
    }

    struct Output: Encodable, Sendable {
        struct File: Encodable, Sendable {
            let id: String?
            let path: String
            let size: Int?
        }
        let files: [File]
    }

    static let path = ["attachment", "export"]
    static let summary = "Copy a task's image or file attachments to a folder (existing files are not overwritten)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("task", "Task (name or id).", required: true),
        .string("attachment", "Attachment id or number. Default: all images and files.", positional: true),
        .string("to", "Destination folder.", required: true),
    ]
    static let examples = ["attachment export --task 'Fix the sink' --to ~/Downloads"]

    static func validate(_ input: Input) throws { _ = try LocalFilePolicy.exportDirectory(input.to) }

    static func run(_ input: Input, _ context: RemindersContext) throws -> Output {
        let catalog = try context.catalog()
        let task = try context.task(input.task, in: catalog)
        let targets =
            try input.attachment.map { [try attachment($0, of: task, files: true)] }
            ?? task.attachments.filter { $0.kind != "url" }
        guard !targets.isEmpty else {
            throw AgentError(code: "not_found", message: "'\(task.title)' has no image or file attachments.")
        }
        let folder = try LocalFilePolicy.exportDirectory(input.to)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return Output(
            files: try targets.map { target in
                guard let source = target.fileURL, FileManager.default.isReadableFile(atPath: source.path) else {
                    throw AgentError(
                        code: "not_available",
                        message: "The file of attachment \(target.id ?? "?") is not on this Mac (not downloaded yet).",
                        hint: "Open the task in Reminders so iCloud downloads it, then retry.")
                }
                // ReminderKit names files by content hash; name copies by kind and id instead.
                let short = (target.id?.split(separator: ":").last.map(String.init) ?? UUID().uuidString).prefix(8)
                let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension
                var destination = folder.appendingPathComponent("\(target.kind)-\(short)\(ext)")
                var counter = 2
                while FileManager.default.fileExists(atPath: destination.path) {
                    destination = folder.appendingPathComponent("\(target.kind)-\(short) \(counter)\(ext)")
                    counter += 1
                }
                try FileManager.default.copyItem(at: source, to: destination)
                return Output.File(id: target.id, path: destination.path, size: target.size)
            })
    }
}
