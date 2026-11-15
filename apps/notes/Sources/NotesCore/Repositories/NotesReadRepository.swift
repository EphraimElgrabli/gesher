import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport

public final class NotesReadRepository {
    let runtime: NotesRuntime

    public init(runtime: NotesRuntime) {
        self.runtime = runtime
    }

    public func fetchAccounts() throws -> [NoteAccountSnapshot] {
        let context = try runtime.obtainContext()
        let accountObjects = try runtime.fetchAccounts(context: context)
        let accountClass: AnyClass = try runtime.requireClass("ICAccount")
        let defaultAccount =
            ObjCSendIdIdArg(accountClass, NSSelectorFromString("defaultAccountInContext:"), context) as AnyObject?
        let defaultID = defaultAccount.map { runtime.objectIDString(from: $0) }
        return accountObjects.map { account in
            let id = runtime.objectIDString(from: account)
            let title =
                runtime.stringValue(from: account, selectors: ["name", "accountName", "localizedName"])
                ?? "Default Account"
            return NoteAccountSnapshot(id: id, title: title, isDefault: id == defaultID)
        }
    }

    public func fetchFolders() throws -> [NoteFolderSnapshot] {
        let context = try runtime.obtainContext()
        return try runtime.fetchFolders(context: context).map(folderSnapshot)
    }

    func folderSnapshot(_ folder: AnyObject) throws -> NoteFolderSnapshot {
        let id = runtime.objectIDString(from: folder)
        let title = runtime.stringValue(from: folder, selectors: ["title", "localizedTitle", "name"]) ?? "Notes"
        guard let accountObj = runtime.objectValue(from: folder, selectors: ["account"]) else {
            throw PlatformError.fetchFailed("Folder is missing its native account relation.")
        }
        let isSmart = runtime.boolValue(from: folder, selectors: ["isSmartFolder"]) == true
        return NoteFolderSnapshot(
            id: id,
            title: title,
            accountID: runtime.objectIDString(from: accountObj),
            accountTitle: runtime.stringValue(from: accountObj, selectors: ["name", "accountName"]) ?? "Account",
            noteCount: isSmart ? nil : runtime.intValue(from: folder, selectors: ["visibleNotesCount", "notesCount"]),
            parentID: runtime.objectValue(from: folder, selectors: ["parentFolder"]).map {
                runtime.objectIDString(from: $0)
            },
            isSmart: isSmart,
            isRecentlyDeleted: runtime.boolValue(from: folder, selectors: ["isTrashFolder"]) == true,
            isDeletable: runtime.boolValue(from: folder, selectors: ["isDeletable"]) == true,
            smartDescription: isSmart
                ? runtime.stringValue(
                    from: folder, selectors: ["smartFolderDescriptionObjC", "smartFolderDescription"])
                : nil)
    }

    /// Exact folder id (used for write readback).
    public func fetchFolder(id: String) throws -> NoteFolderSnapshot {
        guard let folder = try fetchFolders().first(where: { $0.id == id }) else {
            throw PlatformError.objectNotFound(type: "folder", id: id)
        }
        return folder
    }

    // MARK: Notes

    func summary(_ note: AnyObject) throws -> NoteSummarySnapshot {
        guard let folder = runtime.objectValue(from: note, selectors: ["folder"]) else {
            throw PlatformError.fetchFailed("Note is missing its native folder relation.")
        }
        guard let account = runtime.objectValue(from: note, selectors: ["account"]) else {
            throw PlatformError.fetchFailed("Note is missing its native account relation.")
        }
        guard let isLocked = runtime.boolValue(from: note, selectors: ["isPasswordProtected"]) else {
            throw PlatformError.fetchFailed("Native note lock state is unavailable; body access was refused.")
        }
        guard let isPinned = runtime.boolValue(from: note, selectors: ["isPinned"]) else {
            throw PlatformError.fetchFailed("Native note pinned state is unavailable.")
        }
        return NoteSummarySnapshot(
            id: runtime.objectIDString(from: note),
            title: runtime.stringValue(from: note, selectors: ["title", "trimmedTitle"]) ?? "",
            snippet: isLocked ? nil : runtime.stringValue(from: note, selectors: ["snippet"]),
            folderID: runtime.objectIDString(from: folder),
            folderTitle: runtime.stringValue(from: folder, selectors: ["title", "localizedTitle"]) ?? "Notes",
            accountID: runtime.objectIDString(from: account),
            isLocked: isLocked, isPinned: isPinned,
            isInRecentlyDeleted: runtime.boolValue(from: folder, selectors: ["isTrashFolder"]) == true,
            creationDate: runtime.objectValue(from: note, selectors: ["creationDate"]) as? Date,
            modificationDate: runtime.objectValue(from: note, selectors: ["modificationDate"]) as? Date)
    }

    /// Note summaries, newest first. `folderID` limits to one folder; `includeTrash` adds notes in
    /// Recently Deleted (always included when `folderID` is the Recently Deleted folder).
    public func fetchNoteSummaries(folderID: String? = nil, includeTrash: Bool = false) throws
        -> [NoteSummarySnapshot]
    {
        let context = try runtime.obtainContext()
        let objects = try runtime.fetchNotes(includeTrash: includeTrash || folderID != nil, context: context)
        return try sorted(
            objects.map(summary).filter { note in
                if let folderID { return note.folderID == folderID }
                return includeTrash || !note.isInRecentlyDeleted
            })
    }

    func sorted(_ notes: [NoteSummarySnapshot]) -> [NoteSummarySnapshot] {
        notes.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    func noteObject(id: String, includeTrash: Bool = true) throws -> AnyObject {
        let context = try runtime.obtainContext()
        guard let note = try runtime.fetchNote(id: id, includeTrash: includeTrash, context: context) else {
            throw PlatformError.objectNotFound(type: "note", id: id)
        }
        return note
    }

    /// One note with its body as paragraphs, tags and attachments. Locked notes return only
    /// the summary.
    public func fetchNoteDetail(id: String) throws -> NoteDetailSnapshot {
        let note = try noteObject(id: id)
        let summary = try summary(note)
        guard !summary.isLocked,
            let text = runtime.objectValue(from: note, selectors: ["attributedString"]) as? NSAttributedString
        else {
            return NoteDetailSnapshot(
                summary: summary, title: summary.title, content: nil, revision: nil, tags: [], attachments: [])
        }
        let content = try NoteContentReader.read(text, note: note, runtime: runtime)
        return NoteDetailSnapshot(
            summary: summary, title: NotesRuntime.fullTitle(from: text.string), content: content,
            revision: try runtime.revision(of: note), tags: runtime.tags(of: note),
            attachments: attachments(of: note, text: text))
    }

    func attachments(of note: AnyObject, text: NSAttributedString) -> [NoteAttachmentSnapshot] {
        var result: [NoteAttachmentSnapshot] = []
        text.enumerateAttribute(.init("NSAttachment"), in: NSRange(location: 0, length: text.length)) { value, _, _ in
            guard let value = value as AnyObject?, value.responds(to: NSSelectorFromString("attachmentUTI")),
                let uti = runtime.stringValue(from: value, selectors: ["attachmentUTI"]),
                !uti.hasPrefix(NoteContentReader.inlinePrefix), uti != NoteContentReader.tableUTI,
                let id = runtime.stringValue(from: value, selectors: ["attachmentIdentifier"]),
                !result.contains(where: { $0.id == id })
            else { return }
            let attachment =
                ObjCSendIdIdArg(note, NSSelectorFromString("attachmentWithIdentifier:"), id as NSString) as AnyObject?
            let media = attachment.flatMap { runtime.objectValue(from: $0, selectors: ["media"]) }
            let file = media.flatMap { runtime.objectValue(from: $0, selectors: ["mediaURL"]) as? URL }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let size = file.flatMap {
                (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size]) as? NSNumber
            }
            result.append(
                NoteAttachmentSnapshot(
                    id: id, kind: NoteContentReader.kind(uti),
                    name: attachment.flatMap { NoteContentReader.name(of: $0, runtime: runtime) },
                    url: attachment.flatMap { runtime.stringValue(from: $0, selectors: ["urlString"]) },
                    path: file?.path, byteCount: size?.intValue))
        }
        return result
    }

    /// Notes containing a hashtag (case-insensitive, with or without `#`).
    public func fetchNotes(tag: String, includeTrash: Bool = false) throws -> [NoteSummarySnapshot] {
        let wanted = NameMatcher.normalize(tag.hasPrefix("#") ? String(tag.dropFirst()) : tag)
        let context = try runtime.obtainContext()
        return try sorted(
            runtime.fetchNotes(includeTrash: includeTrash, context: context).filter { note in
                runtime.tags(of: note).contains { NameMatcher.normalize(String($0.dropFirst())) == wanted }
            }.map(summary).filter { includeTrash || !$0.isInRecentlyDeleted })
    }

    /// Every hashtag used in visible notes with its note count, most used first.
    public func fetchTags() throws -> [NoteTagSnapshot] {
        let context = try runtime.obtainContext()
        var counts: [String: (name: String, count: Int)] = [:]
        for note in try runtime.fetchNotes(includeTrash: false, context: context) where !runtime.isInTrash(note) {
            for tag in runtime.tags(of: note) {
                let key = NameMatcher.normalize(tag)
                counts[key] = (counts[key]?.name ?? tag, (counts[key]?.count ?? 0) + 1)
            }
        }
        return counts.values.map { NoteTagSnapshot(name: $0.name, noteCount: $0.count) }
            .sorted { $0.noteCount != $1.noteCount ? $0.noteCount > $1.noteCount : $0.name < $1.name }
    }

    /// Full-text search over titles and bodies (all words must appear; case, diacritics and
    /// width are ignored). Locked notes match on title only.
    public func searchNotes(_ query: String, folderID: String? = nil, includeTrash: Bool = false) throws
        -> [NoteSearchHit]
    {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { throw PlatformError.invalidArgument("The search query is empty.") }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let context = try runtime.obtainContext()
        var hits: [NoteSearchHit] = []
        for note in try runtime.fetchNotes(includeTrash: includeTrash || folderID != nil, context: context) {
            let summary = try summary(note)
            if let folderID, summary.folderID != folderID { continue }
            if folderID == nil, !includeTrash, summary.isInRecentlyDeleted { continue }
            let text =
                summary.isLocked
                ? nil : runtime.objectValue(from: note, selectors: ["attributedString"]) as? NSAttributedString
            var body = text?.string ?? summary.title
            if let text, body.contains("\u{FFFC}") {
                // Table cells live in attachments; search them too.
                let cells = (try? NoteTable.read(from: text, note: note, runtime: runtime)) ?? []
                body += cells.flatMap { $0.cells.map { "\n" + $0.joined(separator: " | ") } }.joined()
            }
            guard words.allSatisfy({ body.range(of: $0, options: options) != nil }) else { continue }
            hits.append(NoteSearchHit(summary: summary, excerpt: Self.excerpt(body, word: words[0], options: options)))
        }
        return hits.sorted {
            ($0.summary.modificationDate ?? .distantPast) > ($1.summary.modificationDate ?? .distantPast)
        }
    }

    static func excerpt(_ body: String, word: String, options: String.CompareOptions) -> String? {
        guard let range = body.range(of: word, options: options) else { return nil }
        let start = body.index(range.lowerBound, offsetBy: -60, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: 80, limitedBy: body.endIndex) ?? body.endIndex
        let text = body[start..<end].replacingOccurrences(of: "\u{FFFC}", with: "")
            .split(whereSeparator: \.isNewline).joined(separator: " / ")
        return (start > body.startIndex ? "…" : "") + text + (end < body.endIndex ? "…" : "")
    }

    // MARK: Verification snapshot

    /// Body, formatting runs, tables and revision; used to verify writes.
    public func fetchNote(id: String) throws -> NoteSnapshot {
        try snapshot(noteObject(id: id))
    }

    func snapshot(_ note: AnyObject) throws -> NoteSnapshot {
        let summary = try summary(note)
        let text =
            summary.isLocked
            ? nil : runtime.objectValue(from: note, selectors: ["attributedString"]) as? NSAttributedString
        return NoteSnapshot(
            id: summary.id,
            title: text.map { NotesRuntime.fullTitle(from: $0.string) } ?? summary.title,
            snippet: summary.snippet,
            displayTitle: summary.title,
            body: text?.string,
            formatting: text.map { NoteTextRun.extract(from: $0, runtime: runtime) },
            tables: try text.map { try NoteTable.read(from: $0, note: note, runtime: runtime) },
            folderID: summary.folderID,
            folderTitle: summary.folderTitle,
            accountID: summary.accountID,
            isPasswordProtected: summary.isLocked,
            isPinned: summary.isPinned,
            creationDate: summary.creationDate.map { ISO8601DateFormatter().string(from: $0) },
            modificationDate: summary.modificationDate.map { ISO8601DateFormatter().string(from: $0) },
            revision: summary.isLocked ? nil : try runtime.revision(of: note)
        )
    }

    /// Notes with summaries and optional bodies (kept for in-memory tests).
    public func fetchNotes(folderID: String? = nil, includeBody: Bool = true) throws -> [NoteSnapshot] {
        let context = try runtime.obtainContext()
        let objects = try runtime.fetchNotes(includeTrash: false, context: context)
        return try objects.compactMap { note -> NoteSnapshot? in
            let summary = try summary(note)
            if let folderID, summary.folderID != folderID { return nil }
            guard includeBody else {
                return NoteSnapshot(
                    id: summary.id, title: summary.title, snippet: summary.snippet, folderID: summary.folderID,
                    folderTitle: summary.folderTitle, accountID: summary.accountID,
                    isPasswordProtected: summary.isLocked, isPinned: summary.isPinned)
            }
            return try snapshot(note)
        }
    }
}
