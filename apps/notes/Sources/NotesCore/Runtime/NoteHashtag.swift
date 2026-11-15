import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Real Notes tags: an `ICInlineAttachment` hashtag token backed by an `ICHashtag`, as the app
/// creates when you type `#tag`. Plain `#word` text is not a tag in Notes.
enum NoteHashtag {
    static func create(_ text: String, note: AnyObject, runtime: NotesRuntime) throws -> NSAttributedString {
        let name = text.hasPrefix("#") ? String(text.dropFirst()) : text
        let cls: AnyClass = try runtime.requireClass("ICInlineAttachment")
        let selectorName =
            "newHashtagAttachmentWithIdentifier:hashtagText:creatingHashtagIfNecessary:note:parentAttachment:"
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(cls, selector) else {
            throw PlatformError.missingSelector(className: "ICInlineAttachment", selector: selectorName)
        }
        typealias Create =
            @convention(c) (AnyClass, Selector, NSString, NSString, Bool, AnyObject, AnyObject?) ->
            Unmanaged<AnyObject>?
        let create = unsafeBitCast(method_getImplementation(method), to: Create.self)
        // `new…` returns a +1 reference.
        guard
            let attachment = create(cls, selector, UUID().uuidString as NSString, name as NSString, true, note, nil)?
                .takeRetainedValue(),
            let identifier = runtime.stringValue(from: attachment, selectors: ["identifier"]),
            let uti = runtime.stringValue(from: attachment, selectors: ["typeUTI"])
        else { throw PlatformError.saveFailed("Notes could not create the tag #\(name).") }
        let tokenClass: AnyClass = try runtime.requireClass("ICTTAttachment")
        guard let allocated = ObjCAlloc(tokenClass),
            let token = ObjCSendInitNil(allocated, NSSelectorFromString("init"))
        else { throw PlatformError.saveFailed("Notes could not embed the tag #\(name).") }
        try DynamicRuntime.shared.sendVoidId(
            token as AnyObject, selector: "setAttachmentIdentifier:", argument: identifier as NSString)
        try DynamicRuntime.shared.sendVoidId(
            token as AnyObject, selector: "setAttachmentUTI:", argument: uti as NSString)
        return NSAttributedString(string: "\u{fffc}", attributes: [.attachment: token])
    }
}

extension NotesRuntime {
    /// Standardized contents (e.g. `TRAVEL`) of the hashtags in a note.
    func hashtagContents(of note: AnyObject) -> [String] {
        guard let inline = objectValue(from: note, selectors: ["allNoteTextInlineAttachments"]),
            let attachments = runtime.objectArray(inline)
        else { return [] }
        return attachments.compactMap { attachment in
            boolValue(from: attachment, selectors: ["isHashtagAttachment"]) == true
                ? stringValue(from: attachment, selectors: ["tokenContentIdentifier"]) : nil
        }
    }

    /// Marks for deletion (synced) each of these hashtags that no inline attachment uses any more.
    func deleteUnusedHashtags(_ contents: [String], account: AnyObject) throws {
        guard !contents.isEmpty else { return }
        let inlineClass: AnyClass = try requireClass("ICInlineAttachment")
        let hashtagClass: AnyClass = try requireClass("ICHashtag")
        let countName = "countOfVisibleInlineAttachmentsForHashtagStandardizedContent:includingTrash:account:"
        guard let countMethod = class_getClassMethod(inlineClass, NSSelectorFromString(countName)) else {
            throw PlatformError.missingSelector(className: "ICInlineAttachment", selector: countName)
        }
        typealias Count = @convention(c) (AnyClass, Selector, NSString, Bool, AnyObject) -> UInt
        let count = unsafeBitCast(method_getImplementation(countMethod), to: Count.self)
        let lookup = try NativeProperty.selector(hashtagClass as AnyObject, "hashtagWithStandardizedContent:account:")
        for content in Set(contents)
        where count(inlineClass, NSSelectorFromString(countName), content as NSString, true, account) == 0 {
            if let hashtag = ObjCSendIdId(hashtagClass, lookup, content as NSString, account) as AnyObject?,
                hashtag.responds(to: NSSelectorFromString("markForDeletion"))
            {
                ObjCSendVoid(hashtag, NSSelectorFromString("markForDeletion"))
            }
        }
    }
}
