import GesherKit
import GesherPlatform
import Foundation
import NotesCore

@main
enum NotesCli {
    static func main() { NotesApp.make().main() }
}

/// The Notes app: its operations, defaults and shared dependencies. See AGENTS.md.
enum NotesApp {
    static func make(context: @escaping () throws -> NotesContext = { NotesContext() }) -> AgentApp<NotesContext> {
        AgentApp(
            name: "notes",
            summary: "Capture, find, organize and edit Apple Notes: folders, notes, checklists, tags and attachments.",
            instructions: """
                Notes and folders accept a title/name (case, accents and Hebrew niqqud ignored) or an id; on \
                'ambiguous' retry with a candidate id. Bodies are Markdown by default (note get --content \
                markdown|text|document). Prefer note append/prepend and checklist operations over replacing a \
                body; replacing needs replaceBody and the ifRevision from note get. Deleting moves notes to \
                Recently Deleted (note restore brings them back). Locked notes are reported as locked and never \
                opened.
                """,
            permission: .fullDiskAccess,
            operations: [
                AnyOperation(ListAccounts.self),
                AnyOperation(ListFolders.self),
                AnyOperation(CreateFolders.self),
                AnyOperation(RenameFolder.self),
                AnyOperation(MoveFolder.self),
                AnyOperation(DeleteFolders.self),
                AnyOperation(ListNotes.self),
                AnyOperation(GetNote.self),
                AnyOperation(SearchNotes.self),
                AnyOperation(CreateNote.self),
                AnyOperation(AppendToNote.self),
                AnyOperation(PrependToNote.self),
                AnyOperation(UpdateNote.self),
                AnyOperation(MoveNotes.self),
                AnyOperation(PinNotes.self),
                AnyOperation(UnpinNotes.self),
                AnyOperation(DeleteNotes.self),
                AnyOperation(RestoreNotes.self),
                AnyOperation(ListChecklist.self),
                AnyOperation(AddChecklistItems.self),
                AnyOperation(CheckChecklistItems.self),
                AnyOperation(UncheckChecklistItems.self),
                AnyOperation(SetTableCell.self),
                AnyOperation(AddTableRow.self),
                AnyOperation(AddTableColumn.self),
                AnyOperation(ListTags.self),
                AnyOperation(AddTags.self),
                AnyOperation(CreateSmartFolder.self),
                AnyOperation(AddAttachments.self),
                AnyOperation(ListAttachments.self),
                AnyOperation(ExportAttachment.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Notes operation for the life of the process (or MCP session).
/// Repositories re-read native state on every call; nothing here caches user data.
final class NotesContext {
    let runtime: NotesRuntime
    let read: NotesReadRepository
    let write: NotesWriteRepository
    let config: UserConfig

    init(config: UserConfig = .load()) {
        runtime = NotesRuntime()
        read = NotesReadRepository(runtime: runtime)
        write = NotesWriteRepository(runtime: runtime, readRepository: read)
        self.config = config
    }

    /// For tests: inject repositories backed by an in-memory native store.
    init(runtime: NotesRuntime, read: NotesReadRepository, write: NotesWriteRepository, config: UserConfig) {
        self.runtime = runtime
        self.read = read
        self.write = write
        self.config = config
    }

    // MARK: Selectors

    func folder(_ selector: String, policy: MatchPolicy = .fuzzy) throws -> NoteFolderSnapshot {
        let folders = try read.fetchFolders()
        let paths = FolderPaths(folders)
        if selector.contains("/"),
            let match = folders.first(where: {
                NameMatcher.normalize(paths.path($0)) == NameMatcher.normalize(selector)
            })
        {
            return match
        }
        return try EntityResolver.resolve(
            selector, in: folders, type: "folder", id: \.id, name: \.title,
            detail: { folder in
                [paths.parentPath(folder), folder.accountTitle].compactMap { $0 }.joined(separator: " · ")
            },
            policy: policy)
    }

    /// Explicit folder > configured `notes.folder` > the account's default folder (nil).
    func destinationFolder(_ selector: String?) throws -> NoteFolderSnapshot? {
        guard let selector = selector ?? config.value("notes", "folder") else { return nil }
        return try folder(selector)
    }

    func notes(folder: String? = nil, includeTrash: Bool = false) throws -> [NoteSummarySnapshot] {
        let resolved = try folder.map { try self.folder($0) }
        // Smart folders own no notes: they show the notes their native query matches.
        if let resolved, resolved.isSmart { return try read.fetchSmartFolderNoteSummaries(folderID: resolved.id) }
        return try read.fetchNoteSummaries(folderID: resolved?.id, includeTrash: includeTrash)
    }

    func note(_ selector: String, in notes: [NoteSummarySnapshot], policy: MatchPolicy = .fuzzy) throws
        -> NoteSummarySnapshot
    {
        try EntityResolver.resolve(
            selector, in: notes, type: "note", id: \.id, name: \.title,
            detail: { note in
                note.folderTitle + (note.modificationDate.map { " · " + DateOutput.day($0) } ?? "")
            }, policy: policy)
    }

    /// Resolves each selector independently (batch) against one snapshot of the notes.
    func eachNote<T: Encodable & Sendable>(
        _ selectors: [String], includeTrash: Bool = false, policy: MatchPolicy = .exactName,
        _ body: (NoteSummarySnapshot) throws -> T
    ) throws -> BatchResult<T> {
        let all = try notes(includeTrash: includeTrash)
        return Batch.run(selectors, label: { $0 }) { selector in try body(try note(selector, in: all, policy: policy)) }
    }
}

/// Folder paths ("Parent/Child") for display and selection.
struct FolderPaths {
    let byID: [String: NoteFolderSnapshot]

    init(_ folders: [NoteFolderSnapshot]) {
        byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func path(_ folder: NoteFolderSnapshot) -> String {
        (parentPath(folder).map { $0 + "/" } ?? "") + folder.title
    }

    func parentPath(_ folder: NoteFolderSnapshot) -> String? {
        var names: [String] = []
        var current = folder.parentID.flatMap { byID[$0] }
        while let parent = current, names.count < 32 {
            names.insert(parent.title, at: 0)
            current = parent.parentID.flatMap { byID[$0] }
        }
        return names.isEmpty ? nil : names.joined(separator: "/")
    }
}
