import GesherPlatform
import CoreData
import CryptoKit
import Foundation
import ObjCRuntimeSupport

public final class NotesRuntime {
    private let loader = FrameworkLoader()
    let runtime = DynamicRuntime.shared

    private let frameworkCandidates = [
        "/System/Library/PrivateFrameworks/NotesShared.framework/NotesShared"
    ]
    private let supportCandidates = [
        "/System/Library/PrivateFrameworks/NotesSupport.framework/NotesSupport"
    ]

    private(set) var loaded = false
    private var tableSupportLoaded = false

    private var testContext: NSManagedObjectContext?

    public init() {}

    // Internal injection is restricted to in-memory stores for native integration tests.
    init(inMemoryContext: NSManagedObjectContext) {
        precondition(
            inMemoryContext.persistentStoreCoordinator?.persistentStores.allSatisfy { $0.type == NSInMemoryStoreType }
                == true)
        testContext = inMemoryContext
    }

    public func load() throws {
        guard !loaded else { return }
        try loader.loadFirst(from: frameworkCandidates)
        _ = loader.loadOptional(from: supportCandidates)
        loaded = true
    }

    func loadTableSupport() throws {
        guard !tableSupportLoaded else { return }
        try loader.loadFirst(from: ["/System/Library/PrivateFrameworks/NotesEditor.framework/NotesEditor"])
        ObjCSendVoid(try requireClass("ICCRCoder"), NSSelectorFromString("registerCRClasses"))
        ObjCSendVoid(try requireClass("ICTable"), NSSelectorFromString("registerWithICCRCoder"))
        tableSupportLoaded = true
    }

    public func requireClass(_ name: String) throws -> AnyClass {
        try runtime.requireClass(name)
    }

    public func obtainContext() throws -> NSManagedObjectContext {
        guard Thread.isMainThread else {
            throw PlatformError.storeInitializationFailed("Notes repositories must be called on the main thread.")
        }
        try load()
        if let testContext { return testContext }
        let contextClass = try runtime.requireClass("ICNoteContext")
        let sharedSel = NSSelectorFromString("sharedContext")

        let noteContext: AnyObject = try {
            if (contextClass as AnyObject).responds(to: sharedSel),
                let existing = ObjCSendId(contextClass, sharedSel) as AnyObject?
            {
                return existing
            }

            let startSel = NSSelectorFromString("startSharedContextWithOptions:")
            if (contextClass as AnyObject).responds(to: startSel) {
                let startFunc = unsafeBitCast(
                    method_getImplementation(class_getClassMethod(contextClass, startSel)!),
                    to: (@convention(c) (AnyClass, Selector, UInt) -> Void).self
                )
                startFunc(contextClass, startSel, 0)
            }

            guard (contextClass as AnyObject).responds(to: sharedSel),
                let created = ObjCSendId(contextClass, sharedSel) as AnyObject?
            else {
                throw PlatformError.storeInitializationFailed("Could not obtain ICNoteContext.sharedContext")
            }
            return created
        }()

        let mocSel = NSSelectorFromString("managedObjectContext")
        guard noteContext.responds(to: mocSel),
            let mocAny = ObjCSendId(noteContext, mocSel) as AnyObject?,
            let moc = mocAny as? NSManagedObjectContext
        else {
            throw PlatformError.storeInitializationFailed(
                "Could not obtain NSManagedObjectContext from ICNoteContext")
        }

        guard let coordinator = moc.persistentStoreCoordinator,
            !coordinator.persistentStores.isEmpty
        else {
            throw PlatformError.storeInitializationFailed(
                "NotesShared did not open the real Notes store. Grant Full Disk Access to the CLI or its host application and restart it. No substitute database was created. See stderr for the native store error."
            )
        }

        return moc
    }

    public func fetchAccounts(context: NSManagedObjectContext) throws -> [AnyObject] {
        let accountClass = try runtime.requireClass("ICAccount")
        for selName in ["allActiveAccountsInContext:", "allAccountsInContext:"] {
            let sel = NSSelectorFromString(selName)
            if (accountClass as AnyObject).responds(to: sel),
                let accounts = ObjCSendIdIdArg(accountClass, sel, context) as AnyObject?,
                let array = runtime.objectArray(accounts)
            {
                return array
            }
        }
        throw PlatformError.fetchFailed("NotesShared returned no collection or lacks the required fetch selector.")
    }

    public func fetchFolders(context: NSManagedObjectContext) throws -> [AnyObject] {
        let folderClass = try runtime.requireClass("ICFolder")
        let sel = NSSelectorFromString("visibleFoldersInContext:")
        if (folderClass as AnyObject).responds(to: sel),
            let folders = ObjCSendIdIdArg(folderClass, sel, context) as AnyObject?,
            let array = runtime.objectArray(folders)
        {
            return array
        }
        throw PlatformError.fetchFailed("NotesShared returned no collection or lacks the required fetch selector.")
    }

    public func fetchNotes(context: NSManagedObjectContext) throws -> [AnyObject] {
        let noteClass = try runtime.requireClass("ICNote")
        let sel = NSSelectorFromString("visibleNotesInContext:")
        if (noteClass as AnyObject).responds(to: sel),
            let notes = ObjCSendIdIdArg(noteClass, sel, context) as AnyObject?,
            let array = runtime.objectArray(notes)
        {
            return array
        }
        throw PlatformError.fetchFailed("NotesShared returned no collection or lacks the required fetch selector.")
    }

    /// Native Notes list titles are ellipsized. The first body paragraph is the full title.
    static func fullTitle(from body: String) -> String {
        body.components(separatedBy: .newlines).first ?? ""
    }

    func fetchVisibleNote(id: String, context: NSManagedObjectContext) throws -> AnyObject? {
        let cls: AnyClass = try runtime.requireClass("ICNote")
        let selector = try NativeProperty.selector(cls as AnyObject, "visibleNoteWithIdentifier:context:")
        return ObjCSendIdId(cls, selector, id as NSString, context) as AnyObject?
    }

    func fetchVisibleNotes(folderID: String?, context: NSManagedObjectContext) throws -> [AnyObject] {
        guard let folderID else { return try fetchNotes(context: context) }
        let cls: AnyClass = try runtime.requireClass("ICNote")
        let visible = try NativeProperty.selector(cls as AnyObject, "predicateForVisibleNotesInContext:")
        guard let predicate = ObjCSendIdIdArg(cls, visible, context) as? NSPredicate else {
            throw PlatformError.fetchFailed("Native visible-notes predicate is unavailable.")
        }
        let scoped = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate, NSPredicate(format: "folder.identifier == %@", folderID),
        ])
        let fetch = try NativeProperty.selector(cls as AnyObject, "notesMatchingPredicate:context:")
        guard let value = ObjCSendIdId(cls, fetch, scoped, context), let objects = runtime.objectArray(value) else {
            throw PlatformError.fetchFailed("Native scoped note collection is unavailable.")
        }
        return objects
    }

    func requireSelectors(_ object: AnyObject, _ names: [String]) throws {
        for name in names where !object.responds(to: NSSelectorFromString(name)) {
            throw PlatformError.missingSelector(className: String(describing: type(of: object)), selector: name)
        }
    }

    func replaceText(_ text: NSAttributedString, in mergeable: AnyObject) throws {
        let selector = NSSelectorFromString("replaceCharactersInRange:withAttributedString:")
        guard mergeable.responds(to: selector),
            let method = class_getInstanceMethod(type(of: mergeable), selector)
        else {
            throw PlatformError.missingSelector(
                className: "ICTTMergeableString", selector: NSStringFromSelector(selector))
        }
        let replace = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, NSRange, NSAttributedString) -> Void).self)
        let length = ObjCSendInteger(mergeable, NSSelectorFromString("length"))
        ObjCSendVoid(mergeable, NSSelectorFromString("beginEditing"))
        replace(mergeable, selector, NSRange(location: 0, length: length), text)
        ObjCSendVoid(mergeable, NSSelectorFromString("endEditing"))
    }

    func revision(of note: AnyObject) throws -> String {
        guard let mergeable = objectValue(from: note, selectors: ["mergeableString"]),
            let data = objectValue(from: mergeable, selectors: ["serialize"]) as? Data
        else { throw PlatformError.fetchFailed("Cannot obtain native note revision.") }
        var revisionData = data
        if let text = objectValue(from: note, selectors: ["attributedString"]) as? NSAttributedString {
            let tables = try NoteTable.read(from: text, note: note, runtime: self)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            revisionData.append(try encoder.encode(tables))
        }
        return SHA256.hash(data: revisionData).map { String(format: "%02x", $0) }.joined()
    }

    public func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
            context.refreshAllObjects()
        } catch {
            throw PlatformError.saveFailed(error.localizedDescription)
        }
    }

    public func objectIDString(from object: AnyObject) -> String {
        if let str = runtime.stringValue(from: object, selectors: ["identifier"]) {
            return str
        }
        return runtime.objectIDString(from: object)
    }

    public func stringValue(from object: AnyObject, selectors: [String]) -> String? {
        runtime.stringValue(from: object, selectors: selectors)
    }

    public func dateStringValue(from object: AnyObject, selectors: [String]) -> String? {
        runtime.dateStringValue(from: object, selectors: selectors)
    }

    public func boolValue(from object: AnyObject, selectors: [String]) -> Bool? {
        runtime.boolValue(from: object, selectors: selectors)
    }

    public func intValue(from object: AnyObject, selectors: [String]) -> Int? {
        runtime.intValue(from: object, selectors: selectors)
    }

    public func objectValue(from object: AnyObject, selectors: [String]) -> AnyObject? {
        runtime.objectValue(from: object, selectors: selectors)
    }
}
