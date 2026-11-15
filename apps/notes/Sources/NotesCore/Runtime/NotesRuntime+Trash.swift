import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport

extension NotesRuntime {
    /// Visible notes, optionally including those in Recently Deleted. Notes marked for permanent
    /// deletion are never returned.
    func fetchNotes(includeTrash: Bool, context: NSManagedObjectContext) throws -> [AnyObject] {
        guard includeTrash else { return try fetchNotes(context: context) }
        let cls: AnyClass = try requireClass("ICNote")
        let selector = NSSelectorFromString(
            "predicateForVisibleNotesIncludingTrash:includingSystemPaper:includingMathNotes:includingCallNotes:inContext:"
        )
        guard let method = class_getClassMethod(cls, selector),
            ObjCMatchesMethodSignature(cls, selector, "@", ["B", "B", "B", "B", "@"])
        else {
            throw PlatformError.missingSelector(className: "ICNote", selector: NSStringFromSelector(selector))
        }
        typealias Predicate =
            @convention(c) (AnyClass, Selector, Bool, Bool, Bool, Bool, NSManagedObjectContext) -> NSPredicate?
        guard
            let predicate = unsafeBitCast(method_getImplementation(method), to: Predicate.self)(
                cls, selector, true, true, true, true, context)
        else { throw PlatformError.fetchFailed("Native visible-notes predicate is unavailable.") }
        let fetch = try NativeProperty.selector(cls as AnyObject, "notesMatchingPredicate:context:")
        guard let value = ObjCSendIdId(cls, fetch, predicate, context), let objects = runtime.objectArray(value) else {
            throw PlatformError.fetchFailed("Native note collection is unavailable.")
        }
        return objects
    }

    /// One note by identifier, in Recently Deleted or not; nil when absent or marked for deletion.
    func fetchNote(id: String, includeTrash: Bool, context: NSManagedObjectContext) throws -> AnyObject? {
        if let visible = try fetchVisibleNote(id: id, context: context) {
            return includeTrash || !isInTrash(visible) ? visible : nil
        }
        guard includeTrash else { return nil }
        let cls: AnyClass = try requireClass("ICNote")
        let selector = NSSelectorFromString("noteWithIdentifier:includeDeleted:context:")
        guard let method = class_getClassMethod(cls, selector),
            ObjCMatchesMethodSignature(cls, selector, "@", ["@", "B", "@"])
        else {
            throw PlatformError.missingSelector(className: "ICNote", selector: NSStringFromSelector(selector))
        }
        typealias Lookup = @convention(c) (AnyClass, Selector, NSString, Bool, NSManagedObjectContext) -> AnyObject?
        guard
            let note = unsafeBitCast(method_getImplementation(method), to: Lookup.self)(
                cls, selector, id as NSString, false, context),
            boolValue(from: note, selectors: ["markedForDeletion"]) != true,
            isInTrash(note)
        else { return nil }
        return note
    }

    func isInTrash(_ note: AnyObject) -> Bool {
        objectValue(from: note, selectors: ["folder"]).flatMap { boolValue(from: $0, selectors: ["isTrashFolder"]) }
            == true
    }

    func trashFolder(of object: AnyObject) throws -> AnyObject {
        guard let account = objectValue(from: object, selectors: ["account"]),
            let trash = objectValue(from: account, selectors: ["trashFolder"])
        else {
            throw PlatformError.unsupportedPrivateAPI(
                selector: "trashFolder", reason: "This account has no Recently Deleted folder.")
        }
        return trash
    }

    /// Inserts attributed text at a UTF-16 location without rewriting the rest of the note, so
    /// concurrent edits elsewhere in the mergeable document are preserved.
    func insertText(_ text: NSAttributedString, at location: Int, in mergeable: AnyObject) throws {
        let selector = NSSelectorFromString("replaceCharactersInRange:withAttributedString:")
        guard mergeable.responds(to: selector), let method = class_getInstanceMethod(type(of: mergeable), selector)
        else {
            throw PlatformError.missingSelector(
                className: "ICTTMergeableString", selector: NSStringFromSelector(selector))
        }
        let replace = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, NSRange, NSAttributedString) -> Void).self)
        ObjCSendVoid(mergeable, NSSelectorFromString("beginEditing"))
        replace(mergeable, selector, NSRange(location: location, length: 0), text)
        ObjCSendVoid(mergeable, NSSelectorFromString("endEditing"))
    }

    /// Replaces the attributes of ranges of the mergeable text without changing its characters.
    func setAttributes(
        _ edits: [(range: NSRange, attributes: [NSAttributedString.Key: Any])], in mergeable: AnyObject
    ) throws {
        let selector = NSSelectorFromString("setAttributes:range:")
        guard mergeable.responds(to: selector), let method = class_getInstanceMethod(type(of: mergeable), selector)
        else {
            throw PlatformError.missingSelector(
                className: "ICTTMergeableAttributedString", selector: NSStringFromSelector(selector))
        }
        let set = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, NSDictionary, NSRange) -> Void).self)
        ObjCSendVoid(mergeable, NSSelectorFromString("beginEditing"))
        for edit in edits {
            set(mergeable, selector, edit.attributes as NSDictionary, edit.range)
        }
        ObjCSendVoid(mergeable, NSSelectorFromString("endEditing"))
    }

    /// Hashtags in the note (`#tag` display text), in body order, deduplicated.
    func tags(of note: AnyObject) -> [String] {
        guard let inline = objectValue(from: note, selectors: ["allNoteTextInlineAttachments"]),
            let attachments = runtime.objectArray(inline)
        else { return [] }
        var seen = Set<String>()
        return attachments.compactMap { attachment -> String? in
            guard boolValue(from: attachment, selectors: ["isHashtagAttachment"]) == true,
                boolValue(from: attachment, selectors: ["markedForDeletion"]) != true,
                let text = stringValue(from: attachment, selectors: ["displayText", "altText"]), !text.isEmpty
            else { return nil }
            let tag = text.hasPrefix("#") ? text : "#" + text
            return seen.insert(tag.lowercased()).inserted ? tag : nil
        }
    }
}
