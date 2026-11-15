import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport

/// Where `insertContent` adds paragraphs.
public enum NoteInsertPosition: String, Sendable {
    /// After the last paragraph.
    case end
    /// Directly below the title paragraph.
    case afterTitle
}

public struct ChecklistItemSnapshot: Sendable, Equatable {
    /// Zero-based paragraph index in the note body (title = 0).
    public let paragraph: Int
    public let text: String
    public let checked: Bool
}

extension NotesWriteRepository {
    private func touch(_ object: AnyObject) {
        ObjCSendVoidId(object, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
    }

    private func checkRevision(_ note: AnyObject, _ ifRevision: String?) throws {
        if let ifRevision, try runtime.revision(of: note) != ifRevision {
            throw AgentError(
                code: "revision_conflict", message: "The note changed since it was read.",
                hint: "Read the note again (note get) and retry with its current revision.")
        }
    }

    func requireNoteDestination(_ folder: AnyObject) throws {
        guard runtime.boolValue(from: folder, selectors: ["isSmartFolder"]) != true,
            runtime.boolValue(from: folder, selectors: ["isTrashFolder"]) != true,
            runtime.boolValue(from: folder, selectors: ["canMoveAddOrDeleteContents"]) != false
        else {
            throw PlatformError.invalidArgument(
                "The destination folder does not accept notes (smart folder, Recently Deleted or read-only).")
        }
    }

    private func readback(_ note: AnyObject) throws -> NoteSnapshot {
        let id = runtime.objectIDString(from: note)
        return try MutationVerification.readback(type: "note", id: id) { try readRepository.fetchNote(id: id) }
    }

    // MARK: Content

    /// Inserts paragraphs at the end or below the title. Only the inserted range of the native
    /// mergeable text changes; existing formatting, tables and attachments are untouched.
    public func insertContent(
        id: String, document: NoteDocument, at position: NoteInsertPosition, ifRevision: String? = nil
    ) throws -> NoteSnapshot {
        try document.validate()
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        try checkRevision(target, ifRevision)
        guard let existing = runtime.objectValue(from: target, selectors: ["attributedString"]) as? NSAttributedString,
            let mergeable = runtime.objectValue(from: target, selectors: ["mergeableString"])
        else { throw PlatformError.fetchFailed("Cannot read the existing formatted body.") }
        let previousTables = try NoteTable.read(from: existing, note: target, runtime: runtime)
        let string = existing.string as NSString
        var location = string.length
        if position == .afterTitle, string.length > 0 {
            location = NSMaxRange(string.paragraphRange(for: NSRange(location: 0, length: 0)))
        }
        let addition = NSMutableAttributedString()
        if location > 0, ![10, 13, 0x2029].contains(string.character(at: location - 1)) {
            addition.append(NSAttributedString(string: "\n"))
        }
        try prepareForEditing(target)
        addition.append(try document.attributedString(runtime: runtime, note: target))
        let expected = NSMutableAttributedString(attributedString: existing)
        expected.insert(addition, at: location)
        try runtime.insertText(addition, at: location, in: mergeable)
        ObjCSendVoid(target, NSSelectorFromString("didChangeNoteText"))
        guard ObjCSendBool(target, NSSelectorFromString("saveNoteData")) else {
            throw PlatformError.saveFailed("Native note text serialization failed.")
        }
        touch(target)
        try runtime.save(context: context)
        let result = try readback(target)
        let tables = result.tables ?? []
        let added = document.paragraphs.compactMap(\.table)
        guard result.body == expected.string, tables.count == previousTables.count + added.count,
            previousTables.allSatisfy({ tables.contains($0) })
        else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id,
                reason: "Inserted content did not round-trip; read the note before retrying.")
        }
        return result
    }

    /// Kept for callers of the previous API: append plain text lines or a document at the end.
    public func appendNote(id: String, text: String?, document: NoteDocument? = nil, ifRevision: String? = nil) throws
        -> NoteSnapshot
    {
        guard (text == nil) != (document == nil) else {
            throw PlatformError.invalidArgument("Provide exactly one of text or document.")
        }
        if let text, text.isEmpty { throw PlatformError.invalidArgument("Append text cannot be empty.") }
        let appended =
            document
            ?? NoteDocument(
                paragraphs: (text ?? "").components(separatedBy: .newlines).map {
                    .init(style: .body, runs: [.init(text: $0)])
                })
        return try insertContent(id: id, document: appended, at: .end, ifRevision: ifRevision)
    }

    // MARK: Checklists

    /// Checklist paragraphs of a note in body order.
    public func checklistItems(id: String) throws -> [ChecklistItemSnapshot] {
        let context = try runtime.obtainContext()
        let target = try note(id, context: context, includeTrash: true)
        guard let text = runtime.objectValue(from: target, selectors: ["attributedString"]) as? NSAttributedString
        else {
            throw PlatformError.fetchFailed("Cannot read the formatted body.")
        }
        return checklist(in: text)
    }

    func checklist(in text: NSAttributedString) -> [ChecklistItemSnapshot] {
        let string = text.string as NSString
        var items: [ChecklistItemSnapshot] = []
        var offset = 0
        var index = 0
        while offset < string.length {
            let range = string.paragraphRange(for: NSRange(location: offset, length: 0))
            if let style = text.attribute(.init("TTStyle"), at: range.location, effectiveRange: nil) as AnyObject?,
                let todo = runtime.objectValue(from: style, selectors: ["todo"])
            {
                let line = string.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
                    .trimmingCharacters(in: .newlines)
                items.append(
                    .init(
                        paragraph: index, text: line,
                        checked: runtime.boolValue(from: todo, selectors: ["done"]) ?? false))
            }
            offset = NSMaxRange(range)
            index += 1
        }
        return items
    }

    /// Sets the checked state of several checklist paragraphs in one save.
    public func setChecklist(id: String, states: [Int: Bool], ifRevision: String? = nil) throws -> NoteSnapshot {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        try checkRevision(target, ifRevision)
        guard let existing = runtime.objectValue(from: target, selectors: ["attributedString"]) as? NSAttributedString
        else { throw PlatformError.fetchFailed("Cannot read the formatted body.") }
        let previousTables = try NoteTable.read(from: existing, note: target, runtime: runtime)
        guard let mergeable = runtime.objectValue(from: target, selectors: ["mergeableString"]) else {
            throw PlatformError.fetchFailed("Cannot obtain the native note text.")
        }
        var edits: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        for (index, checked) in states {
            let range = try NoteParagraphEdit.range(in: existing.string as NSString, index: index)
            guard
                let style = existing.attribute(.init("TTStyle"), at: range.location, effectiveRange: nil) as AnyObject?,
                let todo = runtime.objectValue(from: style, selectors: ["todo"]),
                let copy = ObjCSendId(style, NSSelectorFromString("mutableCopy")),
                let updated = ObjCSendIdBool(todo, NSSelectorFromString("todoWithDone:"), checked)
            else { throw PlatformError.invalidArgument("Paragraph \(index) is not a checklist item.") }
            ObjCSendVoidId(copy, NSSelectorFromString("setTodo:"), updated)
            // Only the paragraph style attribute changes; runs keep their own attributes.
            existing.enumerateAttributes(in: range) { attributes, subrange, _ in
                var changed = attributes
                changed[.init("TTStyle")] = copy
                edits.append((subrange, changed))
            }
        }
        try prepareForEditing(target)
        // Attribute-only edits of the mergeable string: the text, and concurrent edits elsewhere, are untouched.
        try runtime.setAttributes(edits, in: mergeable)
        ObjCSendVoid(target, NSSelectorFromString("didChangeNoteText"))
        guard ObjCSendBool(target, NSSelectorFromString("saveNoteData")) else {
            throw PlatformError.saveFailed("Native note text serialization failed.")
        }
        touch(target)
        try runtime.save(context: context)
        let result = try readback(target)
        let saved = try readRepository.noteObject(id: result.id)
        let items =
            (runtime.objectValue(from: saved, selectors: ["attributedString"]) as? NSAttributedString)
            .map(checklist) ?? []
        guard result.body == existing.string, result.tables == previousTables,
            states.allSatisfy({ index, checked in items.contains { $0.paragraph == index && $0.checked == checked } })
        else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id,
                reason: "Checklist change did not round-trip; read the note before retrying.")
        }
        return result
    }

    // MARK: Pin, move, delete, restore

    public func setPinned(id: String, pinned: Bool) throws -> NoteSnapshot {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        if runtime.boolValue(from: target, selectors: ["isPinned"]) == pinned { return try readback(target) }
        guard runtime.boolValue(from: target, selectors: ["isPinnable"]) != false else {
            throw PlatformError.invalidArgument("This note cannot be pinned.")
        }
        ObjCSendVoidBool(target, try NativeProperty.selector(target, "setIsPinned:"), pinned)
        touch(target)
        try runtime.save(context: context)
        let result = try readback(target)
        guard result.isPinned == pinned else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id, reason: "Pinned state did not round-trip.")
        }
        return result
    }

    /// Moves a note to another folder of the same account. Notes in Recently Deleted are restored
    /// this way; `folderID` nil means the account's default folder.
    public func moveNote(id: String, folderID: String?) throws -> NoteSnapshot {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context, includeTrash: true)
        let destination: AnyObject
        if let folderID {
            destination = try folder(folderID, context: context)
        } else {
            guard let account = runtime.objectValue(from: target, selectors: ["account"]),
                let fallback = runtime.objectValue(from: account, selectors: ["defaultFolder"])
            else { throw PlatformError.objectNotFound(type: "folder", id: "default") }
            destination = fallback
        }
        try requireNoteDestination(destination)
        let source = runtime.objectValue(from: target, selectors: ["account"]).map(runtime.objectIDString)
        let goal = runtime.objectValue(from: destination, selectors: ["account"]).map(runtime.objectIDString)
        guard source == goal else {
            throw PlatformError.invalidArgument("Moving notes between accounts is not supported.")
        }
        let destinationID = runtime.objectIDString(from: destination)
        if runtime.objectValue(from: target, selectors: ["folder"]).map(runtime.objectIDString) != destinationID {
            ObjCSendVoidId(target, try NativeProperty.selector(target, "setFolder:"), destination)
            touch(target)
            try runtime.save(context: context)
        }
        let result = try readback(target)
        guard result.folderID == destinationID else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id, reason: "The note did not move to the requested folder.")
        }
        return result
    }

    /// Moves a note to its account's Recently Deleted folder (restorable, like deleting in Notes).
    public func trashNote(id: String) throws -> NoteSnapshot {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context, includeTrash: true)
        if runtime.isInTrash(target) {
            throw AgentError(
                code: "already_deleted", message: "The note is already in Recently Deleted.",
                hint: "Use permanent: true to delete it for good, or note restore to bring it back.")
        }
        let trash = try runtime.trashFolder(of: target)
        ObjCSendVoidId(target, try NativeProperty.selector(target, "setFolder:"), trash)
        touch(target)
        try runtime.save(context: context)
        let result = try readback(target)
        guard result.folderID == runtime.objectIDString(from: trash) else {
            throw PlatformError.mutationUnverified(
                type: "note", id: result.id, reason: "The note did not move to Recently Deleted.")
        }
        return result
    }

    /// Permanently deletes a note that is already in Recently Deleted.
    public func deleteNotePermanently(id: String) throws {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context, includeTrash: true)
        guard runtime.isInTrash(target) else {
            throw PlatformError.invalidArgument(
                "Only notes in Recently Deleted can be deleted permanently; delete it normally first.")
        }
        let resolvedID = runtime.objectIDString(from: target)
        let account = runtime.objectValue(from: target, selectors: ["account"])
        let tags = runtime.hashtagContents(of: target)
        let cls: AnyClass = try runtime.requireClass("ICNote")
        ObjCSendVoidId(cls, try NativeProperty.selector(cls as AnyObject, "deleteNote:"), target)
        // Like the app, a tag that no remaining note uses (Recently Deleted included) goes away too.
        if let account { try runtime.deleteUnusedHashtags(tags, account: account) }
        try runtime.save(context: context)
        try MutationVerification.absence(id: resolvedID, type: "note") { try readRepository.fetchNote(id: resolvedID) }
    }

    /// Kept for in-memory tests: permanently deletes a note wherever it is.
    public func deleteNote(id: String) throws {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context, includeTrash: true)
        let resolvedID = runtime.objectIDString(from: target)
        let account = runtime.objectValue(from: target, selectors: ["account"])
        let tags = runtime.hashtagContents(of: target)
        let cls: AnyClass = try runtime.requireClass("ICNote")
        ObjCSendVoidId(cls, try NativeProperty.selector(cls as AnyObject, "deleteNote:"), target)
        // Like the app, a tag that no remaining note uses (Recently Deleted included) goes away too.
        if let account { try runtime.deleteUnusedHashtags(tags, account: account) }
        try runtime.save(context: context)
        try MutationVerification.absence(id: resolvedID, type: "note") { try readRepository.fetchNote(id: resolvedID) }
    }

    // MARK: Folders

    /// Moves a folder under another folder of the same account, or to the top level (nil).
    public func moveFolder(id: String, parentID: String?) throws -> NoteFolderSnapshot {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try folder(id, context: context)
        guard runtime.boolValue(from: target, selectors: ["isDeletable"]) == true,
            runtime.boolValue(from: target, selectors: ["isSmartFolder"]) != true
        else { throw PlatformError.invalidArgument("System and smart folders cannot be moved.") }
        let parent = try parentID.map { try folder($0, context: context) }
        if let parent {
            try requireNoteDestination(parent)
            var ancestor: AnyObject? = parent
            while let current = ancestor {
                guard runtime.objectIDString(from: current) != id else {
                    throw PlatformError.invalidArgument("A folder cannot be moved inside itself.")
                }
                ancestor = runtime.objectValue(from: current, selectors: ["parentFolder"])
            }
            let source = runtime.objectValue(from: target, selectors: ["account"]).map(runtime.objectIDString)
            let goal = runtime.objectValue(from: parent, selectors: ["account"]).map(runtime.objectIDString)
            guard source == goal else {
                throw PlatformError.invalidArgument("Moving folders between accounts is not supported.")
            }
        }
        let selector = try NativeProperty.selector(target, "setParent:")
        let setter = unsafeBitCast(
            class_getMethodImplementation(type(of: target), selector),
            to: (@convention(c) (AnyObject, Selector, AnyObject?) -> Void).self)
        setter(target, selector, parent)
        touch(target)
        try runtime.save(context: context)
        let result = try MutationVerification.readback(type: "folder", id: id) {
            try readRepository.fetchFolder(id: id)
        }
        guard result.parentID == parentID else {
            throw PlatformError.mutationUnverified(
                type: "folder", id: id, reason: "The folder did not move to the requested parent.")
        }
        return result
    }

    /// Deletes an empty-of-subfolders folder after moving its notes to Recently Deleted (as
    /// Notes does). Returns the number of notes moved.
    @discardableResult
    public func deleteFolder(id: String) throws -> Int {
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try folder(id, context: context)
        guard runtime.boolValue(from: target, selectors: ["isDeletable"]) == true else {
            throw PlatformError.invalidArgument("This system or shared folder cannot be deleted.")
        }
        let folders = try runtime.fetchFolders(context: context)
        guard
            !folders.contains(where: {
                runtime.objectValue(from: $0, selectors: ["parentFolder"]).map(runtime.objectIDString) == id
            })
        else {
            throw AgentError(
                code: "folder_not_empty", message: "The folder has subfolders.",
                hint: "Move or delete its subfolders first.")
        }
        let notes = try runtime.fetchVisibleNotes(folderID: id, context: context)
        if !notes.isEmpty {
            let trash = try runtime.trashFolder(of: target)
            for note in notes {
                ObjCSendVoidId(note, try NativeProperty.selector(note, "setFolder:"), trash)
                touch(note)
            }
        }
        let cls: AnyClass = try runtime.requireClass("ICFolder")
        ObjCSendVoidId(cls, try NativeProperty.selector(cls as AnyObject, "deleteFolder:"), target)
        try runtime.save(context: context)
        try MutationVerification.absence(id: id, type: "folder") { try readRepository.fetchFolder(id: id) }
        for note in notes {
            let noteID = runtime.objectIDString(from: note)
            let saved = try MutationVerification.readback(type: "note", id: noteID) {
                try readRepository.fetchNote(id: noteID)
            }
            guard (try? readRepository.fetchFolder(id: saved.folderID))?.isRecentlyDeleted == true else {
                throw PlatformError.mutationUnverified(
                    type: "note", id: noteID, reason: "A note of the deleted folder is not in Recently Deleted.")
            }
        }
        return notes.count
    }
}
