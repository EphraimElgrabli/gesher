import GesherKit
import GesherPlatform
import Foundation
import NotesCore

private let markdownParam = Param.string(
    "markdown",
    "Body as Markdown: # headings, - bullets, 1. lists, - [ ] checklists, > quotes, ``` code, | tables |, **bold**, *italic*, ~~strike~~, [links](https://...).",
    positional: true)
private let documentParam = Param(
    "document", .object,
    "Rich body instead of markdown: {\"paragraphs\":[{\"style\":\"heading|subheading|body|monospaced|bullet|dashed|numbered|checklist\",\"runs\":[{\"text\":\"...\",\"bold\":true,\"italic\":true,\"underline\":true,\"strikethrough\":true,\"link\":\"https://...\",\"highlight\":1-5}],\"checked\":false,\"indent\":0-8,\"quote\":true,\"table\":[[\"a\",\"b\"],[\"c\",\"d\"]]}]}. Same shape as note get --content document."
)
private let ifRevisionParam = Param.string(
    "ifRevision", "Fail with revision_conflict if the note changed since this revision (from note get).")

/// Markdown or document input, never both.
func noteDocument(markdown: String?, document: JSONValue?, required: Bool = true) throws -> NoteDocument? {
    switch (markdown, document) {
    case (let markdown?, nil): return try NoteMarkdown.parse(markdown).document
    case (nil, let document?):
        guard let data = document.compactText().data(using: .utf8) else { return nil }
        return try NoteDocumentDecoder.decode(from: data)
    case (nil, nil):
        if required {
            throw AgentError.invalid("Provide markdown or document.", hint: "Example: --markdown '- [ ] eggs'")
        }
        return nil
    default: throw AgentError.invalid("Provide markdown or document, not both.")
    }
}

extension NotesContext {
    func ref(_ note: NoteSnapshot) -> NoteRef {
        NoteRef(note, folder: try? read.fetchFolder(id: note.folderID))
    }

    func writableNote(_ selector: String) throws -> NoteSummarySnapshot {
        try note(selector, in: notes(), policy: .exactName)
    }
}

enum CreateNote: AgentOperation {
    struct Input: Decodable, Sendable {
        var markdown: String?
        var title: String?
        var document: JSONValue?
        var folder: String?
        var pinned: Bool
    }

    static let path = ["note", "create"]
    static let summary =
        "Create a note from Markdown (a leading '# Title' line becomes the title) or a rich document, in a folder."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        markdownParam,
        .string("title", "Note title. Default: the Markdown's leading '# Title' line."),
        documentParam,
        .string("folder", "Folder name, path or id. Default: configured notes.folder, else the default Notes folder."),
        .boolean("pinned", "Pin the new note."),
    ]
    static let examples = [
        "note create '- [ ] milk' --title Groceries --folder Home",
        "note create 'Call the plumber on Monday' --title 'To do'",
    ]

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        var title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        var document: NoteDocument?
        if let markdown = input.markdown, input.document == nil {
            let parsed = try NoteMarkdown.parse(markdown, extractTitle: true)
            if let heading = parsed.title {
                if title == nil || title == heading {
                    title = heading
                } else {
                    // An explicit, different title keeps the Markdown heading as content.
                    document = try NoteMarkdown.parse(markdown).document
                }
            }
            if document == nil, !parsed.document.paragraphs.isEmpty { document = parsed.document }
        } else {
            document = try noteDocument(markdown: input.markdown, document: input.document, required: false)
        }
        guard let title, !title.isEmpty else {
            throw AgentError.invalid(
                "The note needs a title.", hint: "Pass title, or start the Markdown with a '# Title' line.")
        }
        let folder = try context.destinationFolder(input.folder)
        var note = try context.write.createNote(folderID: folder?.id, title: title, document: document)
        if input.pinned { note = try context.write.setPinned(id: note.id, pinned: true) }
        return context.ref(note)
    }
}

enum AppendToNote: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var markdown: String?
        var document: JSONValue?
        var ifRevision: String?
    }

    static let path = ["note", "append"]
    static let summary =
        "Add Markdown or document paragraphs at the end of a note; existing content, formatting and attachments are kept."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true),
        markdownParam, documentParam, ifRevisionParam,
    ]
    static let examples = ["note append --note Journal '## Friday'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        let note = try context.writableNote(input.note)
        let document = try noteDocument(markdown: input.markdown, document: input.document)!
        return context.ref(
            try context.write.insertContent(id: note.id, document: document, at: .end, ifRevision: input.ifRevision))
    }
}

enum PrependToNote: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var markdown: String?
        var document: JSONValue?
        var ifRevision: String?
    }

    static let path = ["note", "prepend"]
    static let summary = "Insert Markdown or document paragraphs right below a note's title; the rest is kept."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true),
        markdownParam, documentParam, ifRevisionParam,
    ]
    static let examples = ["note prepend --note Inbox '- [ ] Renew passport'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        let note = try context.writableNote(input.note)
        let document = try noteDocument(markdown: input.markdown, document: input.document)!
        return context.ref(
            try context.write.insertContent(
                id: note.id, document: document, at: .afterTitle, ifRevision: input.ifRevision))
    }
}

enum UpdateNote: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var title: String?
        var markdown: String?
        var document: JSONValue?
        var replaceBody: Bool
        var ifRevision: String?
    }

    static let path = ["note", "update"]
    static let summary =
        "Change a note's title, or replace its whole body (needs replaceBody and ifRevision; prefer append/prepend)."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true, positional: true),
        .string("title", "New title."),
        .string("markdown", "New body as Markdown (replaces everything below the title)."),
        documentParam,
        .boolean(
            "replaceBody",
            "Confirm that the whole body is replaced; formatting and attachments not in the new body are lost."),
        ifRevisionParam,
    ]
    static let examples = [
        "note update 'Old name' --title 'New name'",
        "note update Draft --markdown 'Final text' --replace-body --if-revision 3f2a",
    ]

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        let document = try noteDocument(markdown: input.markdown, document: input.document, required: false)
        if document != nil {
            guard input.replaceBody else {
                throw AgentError.invalid(
                    "Replacing a note body needs replaceBody: true.",
                    hint: "To add content use note append or note prepend instead.")
            }
            guard input.ifRevision != nil else {
                throw AgentError.invalid(
                    "Replacing a note body needs ifRevision.",
                    hint: "Read the note with note get and pass its revision.")
            }
        } else if input.replaceBody {
            throw AgentError.invalid("replaceBody needs markdown or document.")
        }
        guard input.title != nil || document != nil else {
            throw AgentError.invalid("Nothing to change.", hint: "Pass title, or markdown/document with replaceBody.")
        }
        let note = try context.writableNote(input.note)
        return context.ref(
            try context.write.updateNote(
                id: note.id, mutation: .init(title: input.title), document: document, ifRevision: input.ifRevision))
    }
}

enum MoveNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: [String]
        var folder: String
    }

    static let path = ["note", "move"]
    static let summary = "Move notes to another folder of the same account."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .list("note", "Note titles or ids.", required: true, positional: true),
        .string("folder", "Destination folder name, path or id.", required: true),
    ]
    static let examples = ["note move 'Paris trip' 'Rome trip' --folder Travel"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<NoteRef> {
        let folder = try context.folder(input.folder)
        return try context.eachNote(input.note) { note in
            context.ref(try context.write.moveNote(id: note.id, folderID: folder.id))
        }
    }
}

enum PinNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: [String]
    }

    static let path = ["note", "pin"]
    static let summary = "Pin notes to the top of their folder."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [.list("note", "Note titles or ids.", required: true, positional: true)]
    static let examples = ["note pin 'Shopping list'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<NoteRef> {
        try context.eachNote(input.note) { context.ref(try context.write.setPinned(id: $0.id, pinned: true)) }
    }
}

enum UnpinNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: [String]
    }

    static let path = ["note", "unpin"]
    static let summary = "Unpin notes."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [.list("note", "Note titles or ids.", required: true, positional: true)]
    static let examples = ["note unpin 'Shopping list'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<NoteRef> {
        try context.eachNote(input.note) { context.ref(try context.write.setPinned(id: $0.id, pinned: false)) }
    }
}

/// Batch, destructive: exact titles or ids. Default moves to Recently Deleted (restorable).
enum DeleteNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: [String]
        var permanent: Bool
    }

    static let path = ["note", "delete"]
    static let summary =
        "Delete notes by exact title or id: they move to Recently Deleted. permanent: true erases notes already there."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("note", "Note titles or ids.", required: true, positional: true),
        .boolean("permanent", "Erase notes that are already in Recently Deleted (cannot be undone)."),
    ]
    static let examples = ["note delete 'Old draft'", "note delete 'Old draft' --permanent"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<DeletedNote> {
        let all = try context.notes(includeTrash: true)
        let candidates = all.filter { $0.isInRecentlyDeleted == input.permanent }
        return Batch.run(input.note, label: { $0 }) { selector in
            let note = try context.note(selector, in: candidates, policy: .exactName)
            if input.permanent {
                try context.write.deleteNotePermanently(id: note.id)
                return DeletedNote(id: note.id, title: note.title, deleted: "permanently")
            }
            _ = try context.write.trashNote(id: note.id)
            return DeletedNote(id: note.id, title: note.title, deleted: "recently_deleted")
        }
    }
}

enum RestoreNotes: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: [String]
        var folder: String?
    }

    static let path = ["note", "restore"]
    static let summary = "Restore notes from Recently Deleted into a folder (default: the account's Notes folder)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .list("note", "Titles or ids of notes in Recently Deleted.", required: true, positional: true),
        .string("folder", "Destination folder name, path or id. Default: the account's default folder."),
    ]
    static let examples = ["note restore 'Old draft' --folder Work"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<NoteRef> {
        let folder = try input.folder.map { try context.folder($0) }
        let deleted = try context.notes(includeTrash: true).filter(\.isInRecentlyDeleted)
        return Batch.run(input.note, label: { $0 }) { selector in
            let note = try context.note(selector, in: deleted, policy: .exactName)
            return context.ref(try context.write.moveNote(id: note.id, folderID: folder?.id))
        }
    }
}

// MARK: - Tables

enum SetTableCell: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var table: Int
        var row: Int
        var column: Int
        var text: String
        var ifRevision: String
    }

    static let path = ["table", "set-cell"]
    static let summary =
        "Change the text of one table cell (1-based table, row and column); the rest of the note is kept."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true, positional: true),
        .integer("table", "Which table in the note, in body order.", default: 1, min: 1),
        .integer("row", "Row number (1 = first row).", required: true, min: 1),
        .integer("column", "Column number (1 = first column).", required: true, min: 1),
        .string("text", "New cell text.", required: true),
        .string("ifRevision", "Revision from note get; required.", required: true),
    ]
    static let examples = ["table set-cell Budget --row 2 --column 3 --text 120 --if-revision 3f2a"]

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        let note = try context.writableNote(input.note)
        let tables = try context.read.fetchNote(id: note.id).tables ?? []
        guard input.table <= tables.count else {
            throw AgentError.invalid("The note has \(tables.count) table(s).", hint: "Read it with note get.")
        }
        return context.ref(
            try context.write.editTableCell(
                id: note.id, tableID: tables[input.table - 1].id, row: input.row - 1, column: input.column - 1,
                text: input.text, ifRevision: input.ifRevision))
    }
}

enum AddTags: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var tag: [String]
        var ifRevision: String?
    }

    static let path = ["tag", "add"]
    static let summary = "Add real #tags to a note (a line of tags at the end, as typed in Notes)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true),
        .list("tag", "Tags, with or without '#' (letters, digits, '-', '_').", required: true, positional: true),
        ifRevisionParam,
    ]
    static let examples = ["tag add --note 'Paris trip' travel ideas"]

    static func validate(_ input: Input) throws {
        for tag in input.tag where !NoteMarkdown.isTagName(tag.hasPrefix("#") ? String(tag.dropFirst()) : tag) {
            throw AgentError.invalid(
                "'\(tag)' is not a valid tag.", hint: "Use letters, digits, '-' or '_', starting with a letter.")
        }
    }

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        let note = try context.writableNote(input.note)
        var runs: [NoteDocument.Run] = []
        for (index, tag) in input.tag.enumerated() {
            if index > 0 { runs.append(.init(text: " ")) }
            runs.append(.init(text: tag, tag: true))
        }
        let document = NoteDocument(paragraphs: [.init(style: .body, runs: runs)])
        return context.ref(
            try context.write.insertContent(id: note.id, document: document, at: .end, ifRevision: input.ifRevision))
    }
}

enum AddAttachments: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var file: [String]
        var ifRevision: String?
        var confirmShared: Bool
    }

    static let path = ["attachment", "add"]
    static let summary = "Attach images or files (local paths) at the end of a note, each on its own line."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("note", "Note title or id.", required: true),
        .list(
            "file", "Paths of the images or files. Hidden, system and key files are refused.", required: true,
            positional: true),
        ifRevisionParam,
        .boolean(
            "confirmShared",
            "The user confirmed attaching files to a note shared with other people (they will see them)."),
    ]
    static let examples = ["attachment add --note 'Trip receipts' ~/Desktop/receipt.pdf"]

    static func files(_ input: Input) throws -> [URL] {
        try input.file.map { try LocalFilePolicy.attachable($0) }
    }

    static func validate(_ input: Input) throws { _ = try files(input) }

    static func run(_ input: Input, _ context: NotesContext) throws -> NoteRef {
        let note = try context.writableNote(input.note)
        return context.ref(
            try context.write.addAttachments(
                id: note.id, files: try files(input), ifRevision: input.ifRevision, confirmShared: input.confirmShared))
    }
}
