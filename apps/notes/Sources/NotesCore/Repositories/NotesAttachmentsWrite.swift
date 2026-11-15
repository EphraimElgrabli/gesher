import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport

extension NotesWriteRepository {
    /// Adds files (images, PDFs, any file) at the end of a note, each on its own line, as dropping
    /// them into the app does. Only the inserted range of the native text changes. A note shared
    /// through iCloud (itself or its folder) needs `confirmShared`: its files reach every participant.
    public func addAttachments(id: String, files: [URL], ifRevision: String? = nil, confirmShared: Bool = false)
        throws -> NoteSnapshot
    {
        guard !files.isEmpty else { throw PlatformError.invalidArgument("Give at least one file.") }
        for file in files where !FileManager.default.isReadableFile(atPath: file.path) {
            throw PlatformError.invalidArgument("Cannot read \(file.path).")
        }
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let target = try note(id, context: context)
        if let ifRevision, try runtime.revision(of: target) != ifRevision {
            throw AgentError(
                code: "revision_conflict", message: "The note changed since it was read.",
                hint: "Read the note again (note get) and retry with its current revision.")
        }
        let shared = ["isSharedViaICloud", "isSharedViaICloudFolder"].contains {
            runtime.boolValue(from: target, selectors: [$0]) == true
        }
        if shared && !confirmShared {
            throw AgentError(
                code: "confirmation_required",
                message: "This note is shared through iCloud; files attached to it reach everyone it is shared with.",
                hint:
                    "Ask the user whether to share these files with the note's participants, then retry with confirmShared."
            )
        }
        guard runtime.boolValue(from: target, selectors: ["canAddAttachment"]) != false else {
            throw PlatformError.invalidArgument("This note does not accept attachments.")
        }
        guard let existing = runtime.objectValue(from: target, selectors: ["attributedString"]) as? NSAttributedString,
            let mergeable = runtime.objectValue(from: target, selectors: ["mergeableString"])
        else { throw PlatformError.fetchFailed("Cannot read the existing formatted body.") }
        let before = Set(try readRepository.fetchNoteDetail(id: id).attachments.map(\.id))
        try prepareForEditing(target)
        let addSelector = try NativeProperty.selector(target, "addAttachmentWithFileURL:")
        let tokenClass: AnyClass = try runtime.requireClass("ICTTAttachment")
        let addition = NSMutableAttributedString()
        let string = existing.string as NSString
        if string.length > 0, ![10, 13, 0x2029].contains(string.character(at: string.length - 1)) {
            addition.append(NSAttributedString(string: "\n"))
        }
        for file in files {
            guard let attachment = ObjCSendIdIdArg(target, addSelector, file as NSURL) as AnyObject?,
                let identifier = runtime.stringValue(from: attachment, selectors: ["identifier"]),
                let uti = runtime.stringValue(from: attachment, selectors: ["typeUTI"])
            else { throw PlatformError.saveFailed("Notes could not import \(file.lastPathComponent).") }
            if attachment.responds(to: NSSelectorFromString("updateAfterLoadWithSubAttachmentIdentifierMap:")) {
                ObjCSendVoidId(
                    attachment, NSSelectorFromString("updateAfterLoadWithSubAttachmentIdentifierMap:"), NSDictionary())
            }
            guard let allocated = ObjCAlloc(tokenClass),
                let token = ObjCSendInitNil(allocated, NSSelectorFromString("init"))
            else { throw PlatformError.saveFailed("Notes could not embed \(file.lastPathComponent).") }
            try DynamicRuntime.shared.sendVoidId(
                token as AnyObject, selector: "setAttachmentIdentifier:", argument: identifier as NSString)
            try DynamicRuntime.shared.sendVoidId(
                token as AnyObject, selector: "setAttachmentUTI:", argument: uti as NSString)
            addition.append(NSAttributedString(string: "\u{fffc}", attributes: [.attachment: token]))
            addition.append(NSAttributedString(string: "\n"))
        }
        try runtime.insertText(addition, at: string.length, in: mergeable)
        ObjCSendVoid(target, NSSelectorFromString("didChangeNoteText"))
        guard ObjCSendBool(target, NSSelectorFromString("saveNoteData")) else {
            throw PlatformError.saveFailed("Native note text serialization failed.")
        }
        ObjCSendVoidId(target, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
        try runtime.save(context: context)
        let result = try MutationVerification.readback(type: "note", id: id) { try readRepository.fetchNote(id: id) }
        let after = try readRepository.fetchNoteDetail(id: id).attachments.map(\.id)
        guard after.filter({ !before.contains($0) }).count == files.count else {
            throw PlatformError.mutationUnverified(
                type: "note", id: id, reason: "Not every attachment was read back; read the note before retrying.")
        }
        return result
    }
}
