import GesherKit
import GesherPlatform
import Foundation
import NotesCore

/// Agent-facing output models: stable ids, user fields, local ISO dates. Flags that are false
/// and values that are absent are omitted.

func flag(_ value: Bool) -> Bool? { value ? true : nil }

func iso(_ date: Date?) -> String? { date.map { DateOutput.iso($0) } }

struct AccountOut: Encodable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool?

    init(_ account: NoteAccountSnapshot) {
        id = account.id
        name = account.title
        isDefault = flag(account.isDefault)
    }
}

struct FolderOut: Encodable, Sendable {
    let id: String
    let name: String
    /// "Parent/Child" for nested folders.
    let path: String?
    let account: String
    let notes: Int?
    let smart: Bool?
    let recentlyDeleted: Bool?
    /// Smart folder filter, as Notes describes it.
    let filter: String?

    init(_ folder: NoteFolderSnapshot, paths: FolderPaths? = nil) {
        id = folder.id
        name = folder.title
        path = folder.parentID == nil ? nil : paths?.path(folder)
        account = folder.accountTitle
        notes = folder.noteCount
        smart = flag(folder.isSmart)
        recentlyDeleted = flag(folder.isRecentlyDeleted)
        filter = folder.smartDescription
    }
}

struct NoteItem: Encodable, Sendable {
    let id: String
    let title: String
    let folder: String
    let modified: String?
    let pinned: Bool?
    let locked: Bool?
    let recentlyDeleted: Bool?
    let snippet: String?
    /// Search only: text around the first match.
    let excerpt: String?

    init(_ note: NoteSummarySnapshot, snippet includeSnippet: Bool = true, excerpt: String? = nil) {
        id = note.id
        title = note.title
        folder = note.folderTitle
        modified = iso(note.modificationDate)
        pinned = flag(note.isPinned)
        locked = flag(note.isLocked)
        recentlyDeleted = flag(note.isInRecentlyDeleted)
        let text = note.snippet?.trimmingCharacters(in: .whitespacesAndNewlines)
        snippet = includeSnippet && excerpt == nil && text?.isEmpty == false ? text : nil
        self.excerpt = excerpt
    }
}

struct NotePage: Encodable, Sendable {
    let notes: [NoteItem]
    let total: Int
    let nextOffset: Int?

    init(_ items: [NoteItem], offset: Int, limit: Int) {
        notes = Array(items.dropFirst(offset).prefix(limit))
        total = items.count
        nextOffset = offset + notes.count < items.count ? offset + notes.count : nil
    }
}

struct AttachmentOut: Encodable, Sendable {
    let id: String
    let kind: String
    let name: String?
    let url: String?
    let path: String?
    let bytes: Int?

    init(_ attachment: NoteAttachmentSnapshot, includePath: Bool = true) {
        id = attachment.id
        kind = attachment.kind
        name = attachment.name
        url = attachment.url
        path = includePath ? attachment.path : nil
        bytes = attachment.byteCount
    }
}

/// One note as read by `note get`. Exactly one of markdown, text or document is set unless
/// the note is locked (then none, and `locked` is true).
struct NoteOut: Encodable, Sendable {
    let id: String
    let title: String
    let folder: String
    let created: String?
    let modified: String?
    let pinned: Bool?
    let locked: Bool?
    let recentlyDeleted: Bool?
    let revision: String?
    let tags: [String]?
    let markdown: String?
    let text: String?
    let document: NoteContent?
    let attachments: [AttachmentOut]?

    init(_ note: NoteDetailSnapshot, content: String) {
        id = note.summary.id
        title = note.title
        folder = note.summary.folderTitle
        created = iso(note.summary.creationDate)
        modified = iso(note.summary.modificationDate)
        pinned = flag(note.summary.isPinned)
        locked = flag(note.summary.isLocked)
        recentlyDeleted = flag(note.summary.isInRecentlyDeleted)
        revision = note.revision
        tags = note.tags.isEmpty ? nil : note.tags
        markdown = content == "markdown" ? note.content?.markdown() : nil
        text = content == "text" ? note.content?.plainText() : nil
        document = content == "document" ? note.content : nil
        attachments = note.attachments.isEmpty ? nil : note.attachments.map { AttachmentOut($0, includePath: false) }
    }
}

/// Result of a note write: enough to confirm what changed and to chain the next edit.
struct NoteRef: Encodable, Sendable {
    let id: String
    let title: String
    let folder: String
    let revision: String?
    let pinned: Bool?
    let recentlyDeleted: Bool?
    let modified: String?

    init(_ note: NoteSnapshot, folder: NoteFolderSnapshot? = nil) {
        id = note.id
        title = note.title
        self.folder = folder?.title ?? note.folderTitle
        revision = note.revision
        pinned = flag(note.isPinned)
        recentlyDeleted = flag(folder?.isRecentlyDeleted ?? false)
        modified = note.modificationDate.flatMap(DateOutput.parse).map { DateOutput.iso($0) }
    }
}

struct DeletedNote: Encodable, Sendable {
    let id: String
    let title: String
    /// "recently_deleted" (restorable with note restore) or "permanently".
    let deleted: String
}

struct DeletedFolder: Encodable, Sendable {
    let id: String
    let name: String
    let notesMovedToRecentlyDeleted: Int
}

struct ChecklistItemOut: Encodable, Sendable {
    /// 1-based position among the note's checklist items.
    let number: Int
    let text: String
    let checked: Bool
}

struct ChecklistOut: Encodable, Sendable {
    let note: String
    let title: String
    let revision: String?
    let items: [ChecklistItemOut]
}

struct TagOut: Encodable, Sendable {
    let name: String
    let notes: Int
}
