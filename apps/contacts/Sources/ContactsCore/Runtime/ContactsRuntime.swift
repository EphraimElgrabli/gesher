import GesherPlatform
import Foundation
import ObjCRuntimeSupport

public final class ContactsRuntime: @unchecked Sendable {
    private let loader = FrameworkLoader()
    private let runtime = DynamicRuntime.shared

    private let contactsCandidates = [
        "/System/Library/Frameworks/Contacts.framework/Contacts"
    ]

    private(set) var loaded = false

    /// Whether this process may read and write contact notes. macOS reserves notes for apps with
    /// the notes entitlement; without it, faulting a note raises inside AddressBookCore.
    public private(set) var notesAccessible = true

    private let mapperFactory: (() throws -> AnyObject)?

    /// The bound store, created once per process: it wraps the process-wide shared address book,
    /// so reusing it holds no extra state (records are still re-read on every fetch).
    private var store: AnyObject?

    public init() { mapperFactory = nil }

    // A private service test double avoids accessing personal data in unit tests.
    init(mapperFactory: @escaping () throws -> AnyObject) { self.mapperFactory = mapperFactory }

    public func load() throws {
        guard !loaded else { return }
        _ = try loader.loadFirst(from: contactsCandidates)
        _ = try loader.loadFirst(from: ["/System/Library/PrivateFrameworks/AddressBookCore.framework/AddressBookCore"])
        loaded = true
    }

    public func requireClass(_ name: String) throws -> AnyClass {
        try runtime.requireClass(name)
    }

    public func makeDataMapper() throws -> AnyObject {
        if let mapperFactory { return try mapperFactory() }
        if let store { return store }
        try load()
        try PermissionCoordinator().ensureAuthorized(service: .contacts)
        let authClass: AnyClass = try runtime.requireClass("CNAuthorizationContext")
        let authorization = try runtime.requireObject(authClass as AnyObject, selector: "sharedInstance")
        guard runtime.boolValue(from: authorization, selectors: ["isAccessGranted"]) == true else {
            throw PlatformError.permissionDenied(
                "Grant Contacts access to the terminal or agent in System Settings > Privacy & Security > Contacts. First use requires Contacts authorization; Full Disk Access alone does not grant Contacts permission."
            )
        }
        notesAccessible = runtime.boolValue(from: authorization, selectors: ["isNotesAccessGranted"]) == true
        if !notesAccessible { Self.skipNoteFields() }
        Self.installAlertToneGate()
        let storeClass: AnyClass = try runtime.requireClass("ABCNContactStore")
        guard let allocated = ObjCSendId(storeClass, NSSelectorFromString("alloc")) as AnyObject?,
            allocated.responds(to: NSSelectorFromString("initWithLegacySharedAddressBook")),
            let store = ObjCSendId(allocated, NSSelectorFromString("initWithLegacySharedAddressBook")) as AnyObject?,
            let mapper = runtime.sendObject(store, selector: "makeDataMapper"),
            let binding = class_getInstanceVariable(type(of: mapper), "_addressBook"),
            object_getIvar(mapper, binding) != nil
        else {
            throw PlatformError.privateBackendUnavailable(
                "Private macOS Contacts store could not bind the user's address book. No empty or in-memory fallback is accepted."
            )
        }
        self.store = store
        return store
    }

    /// Without notes access, AddressBookCore still converts every property, and faulting a contact's
    /// note raises (CoreData 134092), aborting the whole fetch. Make the note property neither read
    /// nor write in this process: notes are omitted from results and never changed by saves.
    private static let skipNotes: Void = {
        guard let description = NSClassFromString("ABCNNoteDescription") else { return }
        let read: @convention(block) (AnyObject, AnyObject?) -> AnyObject? = { _, _ in nil }
        let write: @convention(block) (AnyObject, AnyObject?, AnyObject?) -> Void = { _, _, _ in }
        for (name, block) in [
            ("valueFromCoreDataContact:", read as Any), ("setValue:onCoreDataContact:", write as Any),
        ] {
            if let method = class_getInstanceMethod(description, NSSelectorFromString(name)) {
                method_setImplementation(method, imp_implementationWithBlock(block))
            }
        }
    }()

    static func skipNoteFields() { _ = skipNotes }

    // MARK: Alert tones
    //
    // Converting a stored contact reads every property. Its alert tones (ringtone, text tone) are
    // a Core Data relationship that is not prefetched: faulting it is one synchronous XPC round
    // trip to the store per contact, most of the time of a whole-address-book fetch. Nothing
    // reads tones, so fetches skip them; a contact fetched to be saved back (update, delete)
    // reads them as usual (`withAlertTones`), so a save never sees them as cleared.

    private static let toneLock = NSLock()
    nonisolated(unsafe) private static var toneReaders = 0

    /// The tone properties: alert tones, and ringtone and text tone read from the same
    /// relationship (those two inherit the read, so the gate is added on their own class).
    private static let alertToneGate: Void = {
        let selector = NSSelectorFromString("valueFromCoreDataContact:")
        typealias Read = @convention(c) (AnyObject, Selector, AnyObject?) -> Unmanaged<AnyObject>?
        for name in [
            "ABCNAlertTonesPropertyDescription", "ABCNRingTonePropertyDescription", "ABCNTextTonePropertyDescription",
        ] {
            guard let description = NSClassFromString(name),
                let method = class_getInstanceMethod(description, selector)
            else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Read.self)
            let read: @convention(block) (AnyObject, AnyObject?) -> AnyObject? = { receiver, contact in
                guard readsAlertTones else { return nil }
                return original(receiver, selector, contact)?.takeUnretainedValue()
            }
            let gate = imp_implementationWithBlock(read)
            if !class_addMethod(description, selector, gate, method_getTypeEncoding(method)) {
                method_setImplementation(method, gate)
            }
        }
    }()

    static func installAlertToneGate() { _ = alertToneGate }

    private static var readsAlertTones: Bool {
        toneLock.lock()
        defer { toneLock.unlock() }
        return toneReaders > 0
    }

    /// Runs `body` with alert tones read, for contacts that will be saved back.
    static func withAlertTones<T>(_ body: () throws -> T) rethrows -> T {
        toneLock.lock()
        toneReaders += 1
        toneLock.unlock()
        defer {
            toneLock.lock()
            toneReaders -= 1
            toneLock.unlock()
        }
        return try body()
    }

    // MARK: Legacy address book
    //
    // Group membership, the me card and card links are not implemented by the ABCN layer
    // (`addMember:toGroup:` is a no-op stub there), but by the AddressBook object model in the
    // same private framework, over the same shared in-process address book.

    /// The shared ABAddressBook, or nil for an injected (in-memory) store.
    func legacyAddressBook() throws -> AnyObject? {
        guard mapperFactory == nil else { return nil }
        _ = try makeDataMapper()
        return try runtime.requireObject(
            try runtime.requireClass("ABAddressBook") as AnyObject, selector: "sharedAddressBook")
    }

    /// A person or group record by the same unique id the ABCN layer reports. Records to change
    /// are refreshed from the store first: a long-lived process (MCP) may hold records changed
    /// since they were cached. (A refresh drops lazily loaded photo data, so reads skip it.)
    func legacyRecord(_ id: String, in book: AnyObject, refresh: Bool = true) throws -> AnyObject {
        let refreshSelector = NSSelectorFromString("refreshRecordsWithUniqueIds:")
        if refresh, book.responds(to: refreshSelector) { ObjCSendVoidId(book, refreshSelector, [id] as NSArray) }
        guard
            let record = ObjCSendIdIdArg(book, NSSelectorFromString("recordForUniqueId:"), id as NSString) as AnyObject?
        else { throw PlatformError.objectNotFound(type: id.hasSuffix(":ABGroup") ? "group" : "contact", id: id) }
        return record
    }

    /// Sends a one-object message to a legacy record (e.g. addMember:, setMe:, unlinkPerson:).
    /// The reply (void or BOOL, varying by method) is ignored; callers verify by reading back.
    func legacySend(_ receiver: AnyObject, _ name: String, _ argument: AnyObject?) throws {
        let selector = NSSelectorFromString(name)
        guard receiver.responds(to: selector) else {
            throw PlatformError.privateBackendUnavailable("AddressBook lacks \(name).")
        }
        typealias Send = @convention(c) (AnyObject, Selector, AnyObject?) -> UInt
        _ = Self.msgSend(Send.self)(receiver, selector, argument)
    }

    /// AddressBook decodes and crops photos with NSImage when AppKit is loaded; without it only
    /// a raw image is recorded and Contacts shows no photo.
    func loadImageSupport() throws {
        _ = try loader.loadFirst(from: ["/System/Library/Frameworks/AppKit.framework/AppKit"])
    }

    func saveLegacy(_ book: AnyObject) throws {
        typealias Save = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        var error: NSError?
        let saved = Self.msgSend(Save.self)(book, NSSelectorFromString("saveAndReturnError:"), &error)
        try checkServiceError(error)
        guard saved else { throw PlatformError.saveFailed("The address book did not save the change.") }
    }

    // MARK: Native model
    //
    // The user's address book (ABCNContactStore over AddressBookCore) stores and returns ABCN
    // objects: ABCNContact (firstName, lastName, companyName, ...), ABCNLabeledValue,
    // ABCNPostalAddress, ABCNSocialProfile, ABCNGroup. vCard serialization works on Contacts'
    // CNContact value objects. Both are decoded and built here with CNContact key names; ABCN
    // objects translate them (`nativeKey`).

    public enum Flavor: Sendable { case addressBook, vCard }

    static let addressBookKeys: [String: String] = [
        "givenName": "firstName", "familyName": "lastName", "namePrefix": "nameTitle",
        "organizationName": "companyName", "phoneticGivenName": "phoneticFirstName",
        "phoneticFamilyName": "phoneticLastName", "birthday": "birthdayComponents",
        "nonGregorianBirthday": "alternateBirthdayComponents", "contactRelations": "relatedNames",
        "dates": "otherDateComponents", "contactType": "displayStyle", "ISOCountryCode": "countryCode",
    ]

    static func isAddressBookObject(_ object: AnyObject) -> Bool {
        NSStringFromClass(type(of: object)).hasPrefix("ABCN")
    }

    func nativeKey(_ key: String, for object: AnyObject) -> String {
        Self.isAddressBookObject(object) ? Self.addressBookKeys[key] ?? key : key
    }

    /// The stable string id of a contact or group (ABCN identifiers are objects with a stringValue).
    public func identifier(of object: AnyObject) -> String {
        if let string = runtime.stringValue(from: object, selectors: ["identifierString"]) { return string }
        if let id = runtime.objectValue(from: object, selectors: ["identifier"]) {
            if let string = id as? String { return string }
            if let string = runtime.stringValue(from: id, selectors: ["stringValue"]) { return string }
        }
        return runtime.objectIDString(from: object)
    }

    /// `ABCNContactIdentifier` / `ABCNGroupIdentifier` for a string id.
    func nativeIdentifier(_ string: String, group: Bool) throws -> AnyObject {
        try load()
        let type: AnyClass = try runtime.requireClass(group ? "ABCNGroupIdentifier" : "ABCNContactIdentifier")
        guard let id = ObjCSendIdIdArg(type, NSSelectorFromString("identifierWithString:"), string as NSString) else {
            throw PlatformError.privateBackendUnavailable("Contacts identifier could not be constructed.")
        }
        return id as AnyObject
    }

    private func newObject(_ name: String) throws -> AnyObject {
        try load()
        guard let allocated = ObjCSendId(try runtime.requireClass(name), NSSelectorFromString("alloc")) as AnyObject?,
            let object = ObjCSendId(allocated, NSSelectorFromString("init")) as AnyObject?
        else { throw PlatformError.storeInitializationFailed("Could not instantiate \(name)") }
        return object
    }

    public func makeSaveRequest() throws -> AnyObject { try newObject("ABCNSaveRequest") }

    public func makeMutableContact(_ flavor: Flavor = .addressBook) throws -> AnyObject {
        try newObject(flavor == .addressBook ? "ABCNMutableContact" : "CNMutableContact")
    }

    public func makeMutableGroup() throws -> AnyObject { try newObject("ABCNMutableGroup") }

    public func makePhoneNumber(string: String, _ flavor: Flavor) throws -> AnyObject {
        guard flavor == .vCard else { return string as NSString }
        let phoneClass = try runtime.requireClass("CNPhoneNumber")
        guard
            let phone = ObjCSendIdIdArg(
                phoneClass, NSSelectorFromString("phoneNumberWithStringValue:"), string as NSString)
        else { throw PlatformError.storeInitializationFailed("Could not instantiate CNPhoneNumber") }
        return phone as AnyObject
    }

    public func makeLabeledValue(label: String?, value: AnyObject, _ flavor: Flavor) throws -> AnyObject {
        try load()
        let labeledClass = try runtime.requireClass(flavor == .addressBook ? "ABCNLabeledValue" : "CNLabeledValue")
        let sel = NSSelectorFromString("labeledValueWithLabel:value:")
        guard (labeledClass as AnyObject).responds(to: sel) else {
            throw PlatformError.storeInitializationFailed("Could not instantiate a labeled value")
        }
        typealias Make = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject) -> Unmanaged<AnyObject>?
        guard let labeled = Self.msgSend(Make.self)(labeledClass, sel, label as NSString?, value) else {
            throw PlatformError.storeInitializationFailed("Could not instantiate a labeled value")
        }
        return labeled.takeUnretainedValue()
    }

    public func makePostalAddress(_ address: PostalAddress, _ flavor: Flavor) throws -> AnyObject {
        let object = try newObject(flavor == .addressBook ? "ABCNMutablePostalAddress" : "CNMutablePostalAddress")
        let values: [(String, String)] = [
            ("street", address.street), ("subLocality", address.subLocality), ("city", address.city),
            ("subAdministrativeArea", address.subAdministrativeArea), ("state", address.state),
            ("postalCode", address.postalCode), ("country", address.country),
            ("ISOCountryCode", address.isoCountryCode),
        ]
        for (key, value) in values { try setValue(value as NSString, key, on: object) }
        return object
    }

    public func makeSocialProfile(_ profile: SocialProfile, _ flavor: Flavor) throws -> AnyObject {
        try load()
        let profileClass = try runtime.requireClass(flavor == .addressBook ? "ABCNSocialProfile" : "CNSocialProfile")
        func text(_ value: String) -> NSString? { value.isEmpty ? nil : value as NSString }
        // alloc returns +1 and init consumes it, so the receiver stays a raw pointer.
        typealias Alloc = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
        guard let allocated = Self.msgSend(Alloc.self)(profileClass, NSSelectorFromString("alloc")) else {
            throw PlatformError.storeInitializationFailed("Could not instantiate a social profile")
        }
        let made: Unmanaged<AnyObject>?
        if flavor == .addressBook {
            typealias Make =
                @convention(c) (
                    UnsafeMutableRawPointer, Selector, AnyObject?, AnyObject?, AnyObject?, AnyObject?, AnyObject?
                ) -> Unmanaged<AnyObject>?
            made = Self.msgSend(Make.self)(
                allocated, NSSelectorFromString("initWithUrlString:username:userIdentifier:service:displayname:"),
                text(profile.url), text(profile.username), nil, text(profile.service), nil)
        } else {
            typealias Make =
                @convention(c) (UnsafeMutableRawPointer, Selector, AnyObject?, AnyObject?, AnyObject?, AnyObject?) ->
                Unmanaged<AnyObject>?
            made = Self.msgSend(Make.self)(
                allocated, NSSelectorFromString("initWithUrlString:username:userIdentifier:service:"),
                text(profile.url), text(profile.username), nil, text(profile.service))
        }
        guard let made else {
            throw PlatformError.storeInitializationFailed("Could not instantiate a social profile")
        }
        return made.takeRetainedValue()
    }

    public func makeRelation(name: String, _ flavor: Flavor) throws -> AnyObject {
        guard flavor == .vCard else { return name as NSString }
        let relationClass = try runtime.requireClass("CNContactRelation")
        guard
            let relation = ObjCSendIdIdArg(
                relationClass, NSSelectorFromString("contactRelationWithName:"), name as NSString)
        else { throw PlatformError.storeInitializationFailed("Could not instantiate CNContactRelation") }
        return relation as AnyObject
    }

    public func makeDateComponents(_ day: ContactDay) -> AnyObject {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        return components as NSDateComponents
    }

    /// KVC write after checking the setter exists (KVC on an unknown key would raise).
    public func setValue(_ value: Any?, _ key: String, on object: AnyObject) throws {
        let key = nativeKey(key, for: object)
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard let object = object as? NSObject, object.responds(to: NSSelectorFromString(setter)) else {
            throw PlatformError.privateBackendUnavailable("Contacts value lacks \(setter).")
        }
        object.setValue(value, forKey: key)
    }

    /// KVC read of a contact key, only when the native object reports the key as fetched
    /// (reading an unfetched CNContact key raises). Nil when unavailable.
    public func value(_ key: String, of object: AnyObject) -> Any? {
        guard let object = object as? NSObject else { return nil }
        let key = nativeKey(key, for: object)
        let available = NSSelectorFromString("isKeyAvailable:")
        if object.responds(to: available) {
            typealias Check = @convention(c) (AnyObject, Selector, NSString) -> Bool
            guard Self.msgSend(Check.self)(object, available, key as NSString) else { return nil }
        } else if !object.responds(to: NSSelectorFromString(key)) {
            return nil
        }
        return object.value(forKey: key)
    }

    /// Like `value`, but an address book object's missing value is the key's empty value: ABCN
    /// getters return nil for unset text and lists, whereas an unavailable key has no getter.
    public func value(_ key: String, of object: AnyObject, empty: Any) -> Any? {
        let result = value(key, of: object)
        if result == nil, Self.isAddressBookObject(object),
            (object as? NSObject)?.responds(to: NSSelectorFromString(nativeKey(key, for: object))) == true
        {
            return empty
        }
        return result
    }

    /// Typed `objc_msgSend`.
    static func msgSend<T>(_ type: T.Type) -> T {
        unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: type)
    }

    func checkServiceError(_ value: AnyObject?) throws {
        guard let error = value as? NSError else { return }
        if error.domain == "CNErrorDomain", error.code == 100 {
            throw PlatformError.permissionDenied(
                "Grant Contacts access to this terminal or agent in System Settings > Privacy & Security > Contacts.")
        }
        if error.domain == "CNErrorDomain", error.code == 1 {
            throw PlatformError.privateBackendUnavailable(
                "Private Contacts backend cannot communicate with its service. This executable has no public-store fallback. Check that the private service is available for this process. (CNErrorDomain/1)"
            )
        }
        throw PlatformError.fetchFailed(
            "Contacts service: \(error.localizedDescription) (\(error.domain)/\(error.code))")
    }

    public func objectIDString(from object: AnyObject) -> String {
        runtime.objectIDString(from: object)
    }

    public func stringValue(from object: AnyObject, selectors: [String]) -> String? {
        runtime.stringValue(from: object, selectors: selectors)
    }

    public func objectArray(_ value: Any?) -> [AnyObject]? {
        runtime.objectArray(value)
    }

    public func objectValue(from object: AnyObject, selectors: [String]) -> AnyObject? {
        runtime.objectValue(from: object, selectors: selectors)
    }
}
