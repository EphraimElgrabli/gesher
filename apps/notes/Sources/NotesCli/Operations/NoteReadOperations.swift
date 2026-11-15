import GesherKit
import GesherPlatform
import Foundation
import NotesCore

private let limitParam = Param.integer("limit", "Maximum notes to return.", default: 50, min: 1, max: 500)
private let offsetParam = Param.integer(
    "offset", "Skip this many notes (use nextOffset from the last page).", default: 0, min: 0)

enum ListNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var folder: String?
        var tag: String?
        var pinned: Bool
        var recentlyDeleted: Bool
        var limit: Int
        var offset: Int
    }

    static let path = ["note", "list"]
    static let summary =
        "List notes newest first (title, folder, snippet), optionally in one folder, with a #tag, or pinned only."
    static let params: [Param] = [
        .string("folder", "Folder name, path or id.", positional: true),
        .string("tag", "Only notes with this hashtag, e.g. '#recipes'."),
        .boolean("pinned", "Only pinned notes."),
        .boolean("recentlyDeleted", "List the notes in Recently Deleted instead."),
        limitParam, offsetParam,
    ]
    static let examples = [
        "note list", "note list Recipes --limit 10", "note list --tag '#travel'", "note list --pinned",
        "note list --recently-deleted",
    ]

    static func run(_ input: Input, _ context: NotesContext) throws -> NotePage {
        var notes: [NoteSummarySnapshot]
        if let tag = input.tag {
            notes = try context.read.fetchNotes(tag: tag, includeTrash: input.recentlyDeleted)
            if let selector = input.folder {
                let folder = try context.folder(selector)
                notes = notes.filter { $0.folderID == folder.id }
            }
        } else {
            notes = try context.notes(folder: input.folder, includeTrash: input.recentlyDeleted)
        }
        if input.recentlyDeleted { notes = notes.filter(\.isInRecentlyDeleted) }
        if input.pinned { notes = notes.filter(\.isPinned) }
        return NotePage(notes.map { NoteItem($0) }, offset: input.offset, limit: input.limit)
    }

    static func pretty(_ output: NotePage) -> String? {
        let lines = output.notes.map { note in
            (note.pinned == true ? "* " : "- ") + note.title + "  [\(note.folder)]"
                + (note.locked == true ? " (locked)" : "") + "  " + (note.modified ?? "")
        }
        return
            (lines + [
                "\(output.notes.count) of \(output.total)" + (output.nextOffset.map { ", next offset \($0)" } ?? "")
            ])
            .joined(separator: "\n")
    }
}

enum GetNote: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var folder: String?
        var content: String
    }

    static let path = ["note", "get"]
    static let summary =
        "Read one note: Markdown (default), plain text or the rich document JSON, plus tags, attachments and the revision for safe edits."
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true, positional: true),
        .string("folder", "Look for the note in this folder only (disambiguates equal titles)."),
        .choice(
            "content", ["markdown", "text", "document", "none"],
            "Body format. 'document' is the paragraph/run JSON accepted by note create/append.", default: "markdown"),
    ]
    static let examples = ["note get 'Shopping list'", "note get Packing --folder Travel --content document"]

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteOut {
        let notes = try context.notes(folder: input.folder, includeTrash: true)
        // Prefer notes outside Recently Deleted when titles collide.
        let live = notes.filter { !$0.isInRecentlyDeleted }
        let summary: NoteSummarySnapshot
        if let match = try? context.note(input.note, in: live) {
            summary = match
        } else {
            summary = try context.note(input.note, in: notes)
        }
        return NoteOut(try context.read.fetchNoteDetail(id: summary.id), content: input.content)
    }

    static func pretty(_ output: NoteOut) -> String? {
        output.markdown ?? output.text ?? (output.locked == true ? output.title + " (locked)" : nil)
    }
}

enum SearchNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var query: String
        var folder: String?
        var recentlyDeleted: Bool
        var limit: Int
        var offset: Int
    }

    static let path = ["note", "search"]
    static let summary =
        "Full-text search of note titles and bodies (all words must appear; case and accents ignored), with a match excerpt."
    static let params: [Param] = [
        .string("query", "Words to find.", required: true, positional: true),
        .string("folder", "Search only this folder."),
        .boolean("recentlyDeleted", "Also search Recently Deleted."),
        .integer("limit", "Maximum notes to return.", default: 20, min: 1, max: 500), offsetParam,
    ]
    static let examples = ["note search 'olive oil'", "note search 'קניות' --folder Home --limit 5"]

    static func run(_ input: Input, _ context: NotesContext) throws -> NotePage {
        let folder = try input.folder.map { try context.folder($0) }
        let hits = try context.read.searchNotes(input.query, folderID: folder?.id, includeTrash: input.recentlyDeleted)
        return NotePage(
            hits.map { NoteItem($0.summary, excerpt: $0.excerpt) }, offset: input.offset, limit: input.limit)
    }

    static func pretty(_ output: NotePage) -> String? { ListNotes.pretty(output) }
}

enum ListTags: AgentOperation {
    static let path = ["tag", "list"]
    static let summary = "List the #tags used in notes with how many notes use each, most used first."
    static let params: [Param] = []
    static let examples = ["tag list"]

    static func run(_ input: NoInput, _ context: NotesContext) throws -> [String: [TagOut]] {
        ["tags": try context.read.fetchTags().map { TagOut(name: $0.name, notes: $0.noteCount) }]
    }
}

enum ListAttachments: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
    }

    static let path = ["attachment", "list"]
    static let summary =
        "List a note's attachments (images, PDFs, audio, drawings, links, files) with their local file path when stored."
    static let params: [Param] = [.string("note", "Note title or id.", required: true, positional: true)]
    static let examples = ["attachment list 'Trip receipts'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> [String: [AttachmentOut]] {
        let note = try context.note(input.note, in: context.notes(includeTrash: true))
        return ["attachments": try context.read.fetchNoteDetail(id: note.id).attachments.map { AttachmentOut($0) }]
    }
}

/// Copies an attachment's stored file out of the Notes container; Notes itself is not changed.
enum ExportAttachment: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var attachment: String
        var to: String
    }

    static let path = ["attachment", "export"]
    static let summary =
        "Copy an attachment's file to a directory (Notes is not changed). Existing files are not overwritten."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true, positional: true),
        .string("attachment", "Attachment id or name from attachment list.", required: true),
        .string("to", "Destination directory (created if missing).", required: true),
    ]
    static let examples = ["attachment export 'Trip receipts' --attachment receipt.pdf --to ~/Downloads"]

    static func validate(_ input: Input) throws { _ = try LocalFilePolicy.exportDirectory(input.to) }

    static func run(_ input: Input, _ context: NotesContext) throws -> [String: String] {
        let note = try context.note(input.note, in: context.notes(includeTrash: true))
        let attachments = try context.read.fetchNoteDetail(id: note.id).attachments
        let attachment = try EntityResolver.resolve(
            input.attachment, in: attachments, type: "attachment", id: \.id, name: { $0.name ?? $0.kind },
            detail: \.kind)
        guard let source = attachment.path else {
            throw AgentError(
                code: "no_file", message: "This attachment has no stored file (\(attachment.kind)).",
                hint: attachment.url.map { "It is a link: \($0)" }
                    ?? "Only images, PDFs, audio and files can be exported.")
        }
        let directory = try LocalFilePolicy.exportDirectory(input.to)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name =
            (attachment.name.flatMap { $0.contains("/") ? nil : $0 } ?? URL(fileURLWithPath: source).lastPathComponent)
        var destination = directory.appendingPathComponent(name)
        if (destination.pathExtension.isEmpty) {
            destination.appendPathExtension(URL(fileURLWithPath: source).pathExtension)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw AgentError(
                code: "file_exists", message: "\(destination.path) already exists.",
                hint: "Choose another directory or remove the file first.")
        }
        try FileManager.default.copyItem(atPath: source, toPath: destination.path)
        return ["path": destination.path]
    }
}
