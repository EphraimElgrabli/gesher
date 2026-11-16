import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport

public final class NotesWriteRepository {
    let runtime: NotesRuntime
    let readRepository: NotesReadRepository

    public init(runtime: NotesRuntime, readRepository: NotesReadRepository) {
        self.runtime = runtime
        self.readRepository = readRepository
    }

    func title(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
            throw PlatformError.invalidArgument("Title must be a nonempty single line.")
        }
        return trimmed
    }

    func find(_ id: String, in objects: [AnyObject], type: String) throws -> AnyObject {
        if let exact = objects.first(where: { runtime.objectIDString(from: $0) == id }) { return exact }
        let matches = objects.filter {
            runtime.stringValue(from: $0, selectors: ["title", "name"])?.localizedCaseInsensitiveCompare(id)
                == .orderedSame
        }
        guard matches.count <= 1 else {
            throw PlatformError.invalidArgument("Ambiguous \(type) name; use its ID.")
        }
        guard let object = matches.first else { throw PlatformError.objectNotFound(type: type, id: id) }
        return object
    }

    func folder(_ id: String?, context: NSManagedObjectContext) throws -> AnyObject {
        if let id {
            guard
                let folder = try runtime.fetchFolders(context: context).first(where: {
                    runtime.objectIDString(from: $0) == id
                })
            else { throw PlatformError.objectNotFound(type: "folder", id: id) }
            return folder
        }
        let cls: AnyClass = try runtime.requireClass("ICFolder")
        guard let folder = ObjCSendIdIdArg(cls, NSSelectorFromString("defaultFolderInContext:"), context) else {
            throw PlatformError.objectNotFound(type: "folder", id: "default")
        }
        return folder as AnyObject
    }

    /// A note that may be edited: not locked, not in Recently Deleted (unless `includeTrash`).
    func note(_ id: String, context: NSManagedObjectContext, includeTrash: Bool = false) throws -> AnyObject {
        guard let note = try runtime.fetchNote(id: id, includeTrash: true, context: context) else {
            throw PlatformError.objectNotFound(type: "note", id: id)
        }
        guard runtime.boolValue(from: note, selectors: ["isPasswordProtected"]) != true else {
            throw AgentError(
                code: "note_locked", message: "The note is locked; its content cannot be read or changed.",
                hint: "Ask the user to unlock or edit it in Notes.")
        }
        if !includeTrash, runtime.isInTrash(note) {
            throw AgentError(
                code: "note_in_recently_deleted", message: "The note is in Recently Deleted.",
                hint: "Restore it with note restore before editing.")
        }
        return note
    }

    func prepareForEditing(_ note: AnyObject) throws {
        try runtime.requireSelectors(
            note,
            [
                "currentReplicaID", "setCurrentReplicaID:", "mergeableString", "didChangeNoteText", "saveNoteData",
                "updateChangeCountWithReason:",
            ])
        if runtime.objectValue(from: note, selectors: ["currentReplicaID"]) == nil {
            // A fresh replica avoids reusing another client's logical edit clock.
            ObjCSendVoidId(note, NSSelectorFromString("setCurrentReplicaID:"), NSUUID())
        }
        // An edited note moves to the top of its folder in the app, as after typing in it.
        if note.responds(to: NSSelectorFromString("setModificationDate:")) {
            ObjCSendVoidId(note, NSSelectorFromString("setModificationDate:"), Date() as NSDate)
        }
    }

    func setContent(_ content: NSAttributedString, note: AnyObject) throws {
        guard let mergeable = runtime.objectValue(from: note, selectors: ["mergeableString"]),
            mergeable.responds(to: NSSelectorFromString("replaceCharactersInRange:withAttributedString:")),
            note.responds(to: NSSelectorFromString("saveNoteData"))
        else {
            throw PlatformError.unsupportedPrivateAPI(
                selector: "mergeableString", reason: "Native text editing is unavailable.")
        }
        try runtime.replaceText(content, in: mergeable)
        ObjCSendVoid(note, NSSelectorFromString("didChangeNoteText"))
        guard ObjCSendBool(note, NSSelectorFromString("saveNoteData")) else {
            throw PlatformError.saveFailed("Native note text serialization failed.")
        }
        ObjCSendVoidId(note, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
    }

    func validateDocumentTitle(_ document: NoteDocument?, title: String) throws {
        guard let first = document?.paragraphs.first, first.style == .title else { return }
        guard first.runs.map(\.text).joined() == title else {
            throw PlatformError.invalidArgument(
                "A leading title paragraph must match the note title. Omit it to have the CLI add the title automatically."
            )
        }
    }

    func content(title: String, body: String?, document: NoteDocument?, note: AnyObject? = nil) throws
        -> NSAttributedString
    {
        if body != nil && document != nil {
            throw PlatformError.invalidArgument("Use body or document, not both.")
        }
        if let document, let first = document.paragraphs.first, first.style == .title {
            try validateDocumentTitle(document, title: title)
            return try document.attributedString(runtime: runtime, note: note)
        }
        let heading = NoteDocument(paragraphs: [.init(style: .title, runs: [.init(text: title)])])
        let result = NSMutableAttributedString(attributedString: try heading.attributedString(runtime: runtime))
        if let document {
            result.append(try document.attributedString(runtime: runtime, note: note))
        } else if let body {
            let paragraphs = body.components(separatedBy: .newlines).map {
                NoteDocument.Paragraph(style: .body, runs: [.init(text: $0)])
            }
            result.append(try NoteDocument(paragraphs: paragraphs).attributedString(runtime: runtime))
        }
        return result
    }

    public func createFolder(title: String, accountID: String? = nil, parentID: String? = nil) throws
        -> NoteFolderSnapshot
    {
        let name = try self.title(title)
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let parent = try parentID.map { try folder($0, context: context) }
        let account: AnyObject
        if let parent {
            guard let found = runtime.objectValue(from: parent, selectors: ["account"]) else {
                throw PlatformError.fetchFailed("Parent folder has no account.")
            }
            account = found
            if let accountID {
                let requested = try find(accountID, in: runtime.fetchAccounts(context: context), type: "account")
                guard runtime.objectIDString(from: requested) == runtime.objectIDString(from: account) else {
                    throw PlatformError.invalidArgument("Parent and account must belong to the same account.")
                }
            }
        } else if let accountID {
            account = try find(accountID, in: runtime.fetchAccounts(context: context), type: "account")
        } else {
            let accounts = try runtime.fetchAccounts(context: context)
            if let defaultFolder = try? folder(nil, context: context),
                let found = runtime.objectValue(from: defaultFolder, selectors: ["account"])
            {
                account = found
            } else if accounts.count == 1 {
                account = accounts[0]
            } else {
                throw PlatformError.objectNotFound(type: "account", id: "default")
            }
        }
        let cls: AnyClass = try runtime.requireClass("ICFolder")
        let selector = parent == nil ? "newFolderInAccount:" : "newFolderInParentFolder:"
        guard (cls as AnyObject).responds(to: NSSelectorFromString(selector)),
            let created = ObjCSendIdIdArg(cls, NSSelectorFromString(selector), parent ?? account)
        else {
            throw PlatformError.saveFailed("Native folder creation failed.")
        }
        ObjCSendVoidId(created, NSSelectorFromString("setTitle:"), name as NSString)
        try runtime.save(context: context)
        let result = try MutationVerification.readback(
            type: "folder", id: runtime.objectIDString(from: created as AnyObject)
        ) { try readRepository.fetchFolder(id: runtime.objectIDString(from: created as AnyObject)) }
        guard result.title == name, result.parentID == parent.map({ runtime.objectIDString(from: $0) }) else {
            throw PlatformError.mutationUnverified(
                type: "folder", id: result.id,
                reason: "Created folder \(result.id) has unexpected parent; inspect before retrying.")
        }
        return result
    }

    public func renameFolder(id: String, title: String) throws -> NoteFolderSnapshot {
        let name = try self.title(title)
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try folder(id, context: context)
        ObjCSendVoidId(target, NSSelectorFromString("setTitle:"), name as NSString)
        ObjCSendVoidId(target, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
        try runtime.save(context: context)
        let result = try MutationVerification.readback(type: "folder", id: runtime.objectIDString(from: target)) {
            try readRepository.fetchFolder(id: runtime.objectIDString(from: target))
        }
        guard result.title == name else {
            throw PlatformError.mutationUnverified(
                type: "folder", id: result.id, reason: "Folder \(result.id) title did not round-trip.")
        }
        return result
    }

    public func createNote(folderID: String? = nil, title: String, body: String? = nil, document: NoteDocument? = nil)
        throws -> NoteSnapshot
    {
        let name = try self.title(title)
        try document?.validate()
        try validateDocumentTitle(document, title: name)
        if body != nil && document != nil {
            throw PlatformError.invalidArgument("Use body or document, not both.")
        }
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let destination = try folder(folderID, context: context)
        try requireNoteDestination(destination)
        let cls: AnyClass = try runtime.requireClass("ICNote")
        guard let created = ObjCSendIdIdArg(cls, NSSelectorFromString("newEmptyNoteInFolder:"), destination) else {
            throw PlatformError.saveFailed("Native note creation failed.")
        }
        try prepareForEditing(created as AnyObject)
        let text = try content(title: name, body: body, document: document, note: created as AnyObject)
        try setContent(text, note: created as AnyObject)
        try runtime.save(context: context)
        let result = try MutationVerification.readback(
            type: "note", id: runtime.objectIDString(from: created as AnyObject)
        ) { try readRepository.fetchNote(id: runtime.objectIDString(from: created as AnyObject)) }
        guard result.body == text.string else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id, reason: "Saved note \(result.id) body did not round-trip.")
        }
        try verifyTables(document: document, note: result)
        try verifyFormatting(NoteTextRun.extract(from: text, runtime: runtime), note: result)
        return result
    }

    public func editTableCell(id: String, tableID: String, row: Int, column: Int, text: String, ifRevision: String)
        throws -> NoteSnapshot
    {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        guard try runtime.revision(of: target) == ifRevision else {
            throw AgentError(
                code: "revision_conflict", message: "The note changed since it was read.",
                hint: "Read the note again (note get) and retry with its current revision.")
        }
        let before = try readRepository.fetchNote(id: runtime.objectIDString(from: target))
        guard let tables = before.tables, let selected = tables.firstIndex(where: { $0.id == tableID }),
            row >= 0, row < tables[selected].cells.count, column >= 0, column < tables[selected].cells[row].count
        else {
            throw PlatformError.invalidArgument(
                "Choose an existing table ID and zero-based cell indices from note get.")
        }
        var cells = tables[selected].cells
        cells[row][column] = text
        var expected = tables
        expected[selected] = NoteTableSnapshot(id: tableID, cells: cells)
        try prepareForEditing(target)
        try NoteTable.updateCell(id: tableID, row: row, column: column, text: text, note: target, runtime: runtime)
        ObjCSendVoid(target, NSSelectorFromString("didChangeNoteText"))
        guard ObjCSendBool(target, NSSelectorFromString("saveNoteData")) else {
            throw PlatformError.saveFailed("Native table serialization failed.")
        }
        ObjCSendVoidId(target, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
        try runtime.save(context: context)
        let after = try readRepository.fetchNote(id: runtime.objectIDString(from: target))
        guard after.tables == expected, after.body == before.body, after.formatting == before.formatting else {
            throw PlatformError.mutationUnverified(
                type: "note", id: id, reason: "Table edit did not round-trip; inspect before retrying.")
        }
        return after
    }

    /// Inserts a row or column into an existing table at `index` (0-based; nil appends), filled with
    /// `values`. Tables stay within the limits Notes tables are created with (100 rows, 20 columns).
    public func insertTableLine(
        id: String, tableID: String, axis: NoteTableAxis, index: Int?, values: [String], ifRevision: String
    ) throws -> NoteSnapshot {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        guard try runtime.revision(of: target) == ifRevision else {
            throw AgentError(
                code: "revision_conflict", message: "The note changed since it was read.",
                hint: "Read the note again (note get) and retry with its current revision.")
        }
        let before = try readRepository.fetchNote(id: runtime.objectIDString(from: target))
        guard let tables = before.tables, let selected = tables.firstIndex(where: { $0.id == tableID }) else {
            throw PlatformError.invalidArgument("Choose an existing table ID from note get.")
        }
        let expectedCells = try NoteTableEdit.inserting(
            axis, at: index, values: values, into: tables[selected].cells)
        var expected = tables
        expected[selected] = NoteTableSnapshot(id: tableID, cells: expectedCells)
        let rows = tables[selected].cells.count
        let columns = tables[selected].cells.first?.count ?? 0
        try prepareForEditing(target)
        try NoteTable.insertLine(
            id: tableID, axis: axis, index: index ?? (axis == .row ? rows : columns), values: values, note: target,
            runtime: runtime)
        ObjCSendVoid(target, NSSelectorFromString("didChangeNoteText"))
        guard ObjCSendBool(target, NSSelectorFromString("saveNoteData")) else {
            throw PlatformError.saveFailed("Native table serialization failed.")
        }
        ObjCSendVoidId(target, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
        try runtime.save(context: context)
        let after = try readRepository.fetchNote(id: runtime.objectIDString(from: target))
        guard after.tables == expected, after.body == before.body, after.formatting == before.formatting else {
            throw PlatformError.mutationUnverified(
                type: "note", id: id, reason: "Table edit did not round-trip; inspect before retrying.")
        }
        return after
    }

    public func updateNote(id: String, mutation: NoteMutation, document: NoteDocument? = nil, ifRevision: String? = nil)
        throws -> NoteSnapshot
    {
        let name = try mutation.title.map { try title($0) }
        try document?.validate()
        if mutation.body != nil && document != nil {
            throw PlatformError.invalidArgument("Use body or document, not both.")
        }
        guard mutation.title != nil || mutation.body != nil || mutation.folderID != nil || document != nil else {
            throw PlatformError.invalidArgument("Provide at least one note update field.")
        }
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        if let ifRevision, try runtime.revision(of: target) != ifRevision {
            throw AgentError(
                code: "revision_conflict", message: "The note changed since it was read.",
                hint: "Read the note again (note get) and retry with its current revision.")
        }
        try validateDocumentTitle(
            document, title: name ?? fullTitle(of: target))
        try prepareForEditing(target)
        // Resolve the destination before making changes.
        let destination = try mutation.folderID.map { try folder($0, context: context) }
        if let destination {
            try requireNoteDestination(destination)
            let sourceAccount = runtime.objectValue(from: target, selectors: ["account"])
            let destinationAccount = runtime.objectValue(from: destination, selectors: ["account"])
            guard
                sourceAccount.map({ runtime.objectIDString(from: $0) })
                    == destinationAccount.map({ runtime.objectIDString(from: $0) })
            else {
                throw PlatformError.invalidArgument("Moving notes between accounts is not supported.")
            }
        }
        var expectedBody: String?
        var expectedFormatting: [NoteTextRun]?
        if mutation.body != nil || document != nil {
            let currentTitle = name ?? fullTitle(of: target)
            let text = try content(title: currentTitle, body: mutation.body, document: document, note: target)
            expectedBody = text.string
            expectedFormatting = NoteTextRun.extract(from: text, runtime: runtime)
            try setContent(text, note: target)
        } else if let name {
            guard
                let existing = runtime.objectValue(from: target, selectors: ["attributedString"]) as? NSAttributedString
            else {
                throw PlatformError.fetchFailed("Cannot read existing formatted body.")
            }
            let text = NSMutableAttributedString(attributedString: existing)
            let range = (text.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            text.replaceCharacters(in: range, with: try content(title: name, body: nil, document: nil))
            expectedBody = text.string
            expectedFormatting = NoteTextRun.extract(from: text, runtime: runtime)
            try setContent(text, note: target)
        }
        if let destination {
            ObjCSendVoidId(target, NSSelectorFromString("setFolder:"), destination)
            ObjCSendVoidId(target, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
        }
        try runtime.save(context: context)
        let result = try MutationVerification.readback(type: "note", id: runtime.objectIDString(from: target)) {
            try readRepository.fetchNote(id: runtime.objectIDString(from: target))
        }
        guard expectedBody == nil || result.body == expectedBody else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id,
                reason: "Saved note \(result.id) did not preserve the requested body; inspect it before retrying.")
        }
        if let destination, result.folderID != runtime.objectIDString(from: destination) {
            throw PlatformError.mutationUnverified(
                type: "folder", id: result.id, reason: "Saved note \(result.id) did not move to the requested folder.")
        }
        if let name, result.title != name {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id, reason: "Note \(result.id) title did not round-trip.")
        }
        try verifyTables(document: document, note: result)
        if let expectedFormatting { try verifyFormatting(expectedFormatting, note: result) }
        return result
    }

    func fullTitle(of note: AnyObject) -> String {
        if let text = runtime.objectValue(from: note, selectors: ["attributedString"]) as? NSAttributedString {
            return NotesRuntime.fullTitle(from: text.string)
        }
        return runtime.stringValue(from: note, selectors: ["title"]) ?? "Untitled"
    }

    func verifyFormatting(_ expected: [NoteTextRun], note: NoteSnapshot) throws {
        guard expected == note.formatting else {
            throw PlatformError.mutationUnverified(
                type: "note", id: note.id,
                reason: "Note \(note.id) formatting did not round-trip. Inspect before retrying.")
        }
    }

    func verifyTables(document: NoteDocument?, note: NoteSnapshot) throws {
        guard let document else { return }
        let expected = document.paragraphs.compactMap(\.table)
        let actual = (note.tables ?? []).map(\.cells)
        guard expected == actual else {
            throw PlatformError.mutationUnverified(
                type: "note", id: note.id,
                reason: "Note \(note.id) table cells did not round-trip. Inspect before retrying.")
        }
    }
}
