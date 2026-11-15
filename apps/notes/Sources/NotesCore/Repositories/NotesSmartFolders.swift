import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport

extension NotesReadRepository {
    /// Notes a smart folder shows, evaluated with the folder's own native query (newest first).
    public func fetchSmartFolderNoteSummaries(folderID: String) throws -> [NoteSummarySnapshot] {
        let context = try runtime.obtainContext()
        guard
            let folder = try runtime.fetchFolders(context: context).first(where: {
                runtime.objectIDString(from: $0) == folderID
            })
        else { throw PlatformError.objectNotFound(type: "folder", id: folderID) }
        guard runtime.boolValue(from: folder, selectors: ["isSmartFolder"]) == true,
            let query = runtime.objectValue(from: folder, selectors: ["smartFolderQueryObjC", "smartFolderQuery"]),
            let predicate = runtime.objectValue(from: query, selectors: ["predicate"]) as? NSPredicate
        else { throw PlatformError.fetchFailed("The smart folder has no readable native query.") }
        let cls: AnyClass = try runtime.requireClass("ICNote")
        let visible = try NativeProperty.selector(cls as AnyObject, "predicateForVisibleNotesInContext:")
        guard let visiblePredicate = ObjCSendIdIdArg(cls, visible, context) as? NSPredicate else {
            throw PlatformError.fetchFailed("Native visible-notes predicate is unavailable.")
        }
        var parts = [visiblePredicate, predicate]
        // Smart folders show the notes of their own account only.
        if let account = runtime.objectValue(from: folder, selectors: ["account"]) {
            parts.append(NSPredicate(format: "account == %@", account as! NSObject))
        }
        let fetch = try NativeProperty.selector(cls as AnyObject, "notesMatchingPredicate:context:")
        guard
            let value = ObjCSendIdId(
                cls, fetch, NSCompoundPredicate(andPredicateWithSubpredicates: parts), context),
            let objects = runtime.runtime.objectArray(value)
        else { throw PlatformError.fetchFailed("Native smart folder notes are unavailable.") }
        return sorted(try objects.map(summary).filter { !$0.isInRecentlyDeleted })
    }
}

extension NotesWriteRepository {
    /// Creates a smart folder showing notes with the given tags (all of them, or any), as the app's
    /// "New Smart Folder" with a Tags filter does. The tags must exist.
    public func createSmartFolder(title: String, tags: [String], matchAll: Bool, accountID: String? = nil) throws
        -> NoteFolderSnapshot
    {
        let name = try self.title(title)
        guard !tags.isEmpty else { throw PlatformError.invalidArgument("A smart folder needs at least one tag.") }
        let context = try runtime.obtainContext()
        defer { if context.hasChanges { context.rollback() } }
        let account: AnyObject
        if let accountID {
            account = try find(accountID, in: runtime.fetchAccounts(context: context), type: "account")
        } else {
            guard let found = runtime.objectValue(from: try folder(nil, context: context), selectors: ["account"])
            else {
                throw PlatformError.objectNotFound(type: "account", id: "default")
            }
            account = found
        }
        let hashtagClass: AnyClass = try runtime.requireClass("ICHashtag")
        let lookupName = "hashtagWithDisplayText:account:createIfNecessary:"
        guard let lookupMethod = class_getClassMethod(hashtagClass, NSSelectorFromString(lookupName)) else {
            throw PlatformError.missingSelector(className: "ICHashtag", selector: lookupName)
        }
        typealias Lookup = @convention(c) (AnyClass, Selector, NSString, AnyObject, Bool) -> AnyObject?
        let lookup = unsafeBitCast(method_getImplementation(lookupMethod), to: Lookup.self)
        let objectIDs = try tags.map { tag -> NSManagedObjectID in
            let text = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
            guard
                let hashtag = lookup(hashtagClass, NSSelectorFromString(lookupName), text as NSString, account, false),
                let objectID = (hashtag as? NSManagedObject)?.objectID
            else {
                throw AgentError(
                    code: "not_found", message: "No tag #\(text) in this account.",
                    hint: "Add the tag to a note first (write #\(text) in it), or check tag list.")
            }
            return objectID
        }
        let selectionClass: AnyClass = try runtime.requireClass("ICTagSelection")
        guard let allocated = ObjCAlloc(selectionClass) as AnyObject? else {
            throw PlatformError.missingClass("ICTagSelection")
        }
        typealias Init = @convention(c) (AnyObject, Selector, AnyObject, NSSet, NSSet, UInt) -> AnyObject?
        let initName = "initWithManagedObjectContext:includedObjectIDs:excludedObjectIDs:tagOperator:"
        guard let initMethod = class_getInstanceMethod(selectionClass, NSSelectorFromString(initName)) else {
            throw PlatformError.missingSelector(className: "ICTagSelection", selector: initName)
        }
        // Native tag operators: 0 = any (or), 1 = all (and).
        guard
            let selection = unsafeBitCast(method_getImplementation(initMethod), to: Init.self)(
                allocated, NSSelectorFromString(initName), context, NSSet(array: objectIDs), NSSet(),
                matchAll ? 1 : 0)
        else { throw PlatformError.saveFailed("Notes rejected the tag selection.") }
        let queryClass: AnyClass = try runtime.requireClass("ICQuery")
        guard
            let query = ObjCSendIdIdArg(
                queryClass, try NativeProperty.selector(queryClass as AnyObject, "queryForNotesMatchingTagSelection:"),
                selection) as AnyObject?
        else { throw PlatformError.saveFailed("Notes could not build the smart folder query.") }
        let folderClass: AnyClass = try runtime.requireClass("ICFolder")
        guard
            let created = ObjCSendIdId(
                folderClass, try NativeProperty.selector(folderClass as AnyObject, "smartFolderWithQuery:account:"),
                query, account) as AnyObject?
        else { throw PlatformError.saveFailed("Notes could not create the smart folder.") }
        ObjCSendVoidId(created, NSSelectorFromString("setTitle:"), name as NSString)
        ObjCSendVoidId(created, NSSelectorFromString("updateChangeCountWithReason:"), "notes-cli" as NSString)
        try runtime.save(context: context)
        let id = runtime.objectIDString(from: created)
        let result = try MutationVerification.readback(type: "folder", id: id) {
            try readRepository.fetchFolder(id: id)
        }
        guard result.title == name, result.isSmart else {
            throw PlatformError.mutationUnverified(
                type: "folder", id: id, reason: "The smart folder did not read back as a smart folder named \(name).")
        }
        return result
    }
}
