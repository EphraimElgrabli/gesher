@preconcurrency import GesherPlatform
import Foundation
import ObjCRuntimeSupport

public final class ReminderKitRuntime: @unchecked Sendable {
    private typealias REMStoragesContainerKeyGetter =
        @convention(thin) () -> CodingUserInfoKey

    private let localFrameworkCandidates = [
        "./ReminderKit",
        "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit",
    ]
    private let internalFrameworkCandidates = [
        "./ReminderKitInternal",
        "/System/Library/PrivateFrameworks/ReminderKitInternal.framework/ReminderKitInternal",
    ]

    public private(set) var loaded = false

    public init() {}

    public func load() throws {
        guard !loaded else {
            return
        }

        let reminderKitLoaded = localFrameworkCandidates.contains { path in
            dlopen(path, RTLD_NOW | RTLD_LOCAL) != nil
        }

        guard reminderKitLoaded else {
            throw ReminderCLIError.frameworkLoadFailed(localFrameworkCandidates)
        }

        _ = internalFrameworkCandidates.contains { path in
            dlopen(path, RTLD_NOW | RTLD_LOCAL) != nil
        }
        loaded = true
    }

    func makeStore() throws -> AnyObject {
        try PermissionCoordinator().ensureAuthorized(service: .reminders)
        try load()

        guard let storeClass = NSClassFromString("REMStore") as? NSObject.Type else {
            throw ReminderCLIError.missingClass("REMStore")
        }

        let initUserInteractive = NSSelectorFromString("initUserInteractive:")
        guard let allocated = ObjCAlloc(storeClass) as AnyObject? else {
            throw ReminderCLIError.storeInitializationFailed
        }

        if allocated.responds(to: initUserInteractive),
            let store = ObjCSendIdBool(allocated, initUserInteractive, true) as AnyObject?
        {
            return store
        }

        let initSelector = NSSelectorFromString("init")
        if allocated.responds(to: initSelector),
            let store = ObjCSendId(allocated, initSelector) as AnyObject?
        {
            return store
        }

        throw ReminderCLIError.storeInitializationFailed
    }

    func makeSaveRequest(store: AnyObject) throws -> AnyObject {
        guard let saveRequestClass = NSClassFromString("REMSaveRequest") as? NSObject.Type else {
            throw ReminderCLIError.missingClass("REMSaveRequest")
        }

        let selector = NSSelectorFromString("initWithStore:")
        guard let allocated = ObjCAlloc(saveRequestClass) as AnyObject?,
            allocated.responds(to: selector),
            let saveRequest = ObjCSendInitId(allocated, selector, store) as AnyObject?
        else {
            throw ReminderCLIError.missingSelector(className: "REMSaveRequest", selector: "initWithStore:")
        }

        sendVoidIdIfSupported(saveRequest, "setAuthor:", "reminders-cli" as NSString)
        sendVoidBoolIfSupported(saveRequest, "setSyncToCloudKit:", true)
        return saveRequest
    }

    func requireObject(_ target: AnyObject, selector selectorName: String) throws -> AnyObject {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }

        guard let object = ObjCSendId(target, selector) as AnyObject? else {
            throw ReminderCLIError.fetchFailed("\(selectorName) returned nil.")
        }

        return object
    }

    func sendObject(_ target: AnyObject, selector selectorName: String) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            return nil
        }

        return ObjCSendId(target, selector) as AnyObject?
    }

    func sendObject(_ target: AnyObject, selector selectorName: String, argument: AnyObject) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            return nil
        }

        return ObjCSendIdIdArg(target, selector, argument) as AnyObject?
    }

    func sendVoid(_ target: AnyObject, selector selectorName: String) throws {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }

        ObjCSendVoid(target, selector)
    }

    func sendVoidId(_ target: AnyObject, selector selectorName: String, argument: AnyObject) throws {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }

        ObjCSendVoidId(target, selector, argument)
    }

    func sendVoidBool(_ target: AnyObject, selector selectorName: String, value: Bool) throws {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }

        ObjCSendVoidBool(target, selector, value)
    }

    func sendVoidInteger(_ target: AnyObject, selector selectorName: String, value: Int) throws {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }

        ObjCSendVoidInteger(target, selector, value)
    }

    func sendVoidDouble(_ target: AnyObject, selector selectorName: String, value: Double) throws {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }

        ObjCSendVoidDouble(target, selector, value)
    }

    func sendIdIntegerId(_ target: AnyObject, selector selectorName: String, first: Int, second: AnyObject) throws
        -> AnyObject?
    {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }
        return ObjCSendIdIntegerId(target, selector, first, second) as AnyObject?
    }

    func sendVoidIdIfSupported(_ target: AnyObject, _ selectorName: String, _ argument: AnyObject) {
        let selector = NSSelectorFromString(selectorName)
        if target.responds(to: selector) {
            ObjCSendVoidId(target, selector, argument)
        }
    }

    func sendVoidBoolIfSupported(_ target: AnyObject, _ selectorName: String, _ value: Bool) {
        let selector = NSSelectorFromString(selectorName)
        if target.responds(to: selector) {
            ObjCSendVoidBool(target, selector, value)
        }
    }

    func saveSynchronously(_ saveRequest: AnyObject) throws {
        let selector = NSSelectorFromString("saveSynchronouslyWithError:")
        guard saveRequest.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: saveRequest)), selector: "saveSynchronouslyWithError:")
        }

        var error: NSError?
        guard ObjCSendBoolError(saveRequest, selector, &error) else {
            if let error, error.domain == NSCocoaErrorDomain && (error.code == 4097 || error.code == 4099) {
                try PermissionCoordinator().ensureAuthorized(service: .reminders)
            }
            throw ReminderCLIError.saveFailed(
                error?.localizedDescription ?? "REMSaveRequest.saveSynchronouslyWithError returned false.")
        }
    }

    func performSwiftInvocation(
        store: AnyObject,
        invocation: AnyObject,
        parametersData: Data,
        storages: NSDictionary
    ) throws -> AnyObject {
        let selectorName = "resultFromPerformingSwiftInvocation:parametersData:storages:error:"
        let selector = NSSelectorFromString(selectorName)
        guard store.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: "REMStore", selector: selectorName)
        }

        var error: NSError?
        guard
            let result = ObjCSendIdIdIdError(store, selector, invocation, parametersData as NSData, storages, &error)
                as AnyObject?
        else {
            if let error, error.domain == NSCocoaErrorDomain && (error.code == 4097 || error.code == 4099) {
                try PermissionCoordinator().ensureAuthorized(service: .reminders)
            }
            throw ReminderCLIError.fetchFailed(error?.localizedDescription ?? "\(selectorName) returned nil.")
        }

        return result
    }

    func codablePropertyList(fromList list: AnyObject) throws -> AnyObject {
        guard let store = objectValue(from: list, selectors: ["store"]),
            let account = objectValue(from: list, selectors: ["account"]),
            let storage = objectValue(from: list, selectors: ["storage"])
        else { throw ReminderCLIError.missingSelector(className: "REMList", selector: "store/account/storage") }
        return try codablePropertyList(
            className: "REMList_Codable", initializer: "initWithStore:account:storage:", store: store,
            arguments: [store, account, storage])
    }

    /// A smart list (or template) encoded as its private `_Codable` wrapper, for Swift invocations.
    func codablePropertyList(fromStorageBacked object: AnyObject, className: String) throws -> AnyObject {
        guard let store = objectValue(from: object, selectors: ["store"]),
            let storage = objectValue(from: object, selectors: ["storage"])
        else { throw ReminderCLIError.missingSelector(className: className, selector: "store/storage") }
        return try codablePropertyList(
            className: className, initializer: "initWithStore:storage:", store: store, arguments: [store, storage])
    }

    private func codablePropertyList(
        className: String, initializer selectorName: String, store: AnyObject, arguments: [AnyObject]
    ) throws -> AnyObject {
        guard let codableClass = NSClassFromString(className) as? NSObject.Type,
            let allocated = ObjCAlloc(codableClass) as AnyObject?
        else {
            throw ReminderCLIError.missingClass(className)
        }
        let selector = NSSelectorFromString(selectorName)
        guard allocated.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: className, selector: selectorName)
        }
        let codable: AnyObject?
        switch arguments.count {
        case 2: codable = ObjCSendIdId(allocated, selector, arguments[0], arguments[1]) as AnyObject?
        default: codable = ObjCSendIdIdId(allocated, selector, arguments[0], arguments[1], arguments[2]) as AnyObject?
        }
        guard let codable, let encodable = codable as? any Encodable else {
            throw ReminderCLIError.fetchFailed("\(className) did not return an Encodable value.")
        }

        do {
            let encoder = PropertyListEncoder()
            let (userInfoKey, container) = try encodingContext(store: store)
            // Sendable is a marker protocol: this preserves the native object identity.
            // The private container and encoder are confined to this synchronous call;
            // neither escapes to another actor/task. A wrapper would break ReminderKit's cast.
            let codingContext = unsafeBitCast(container, to: (AnyObject & Sendable).self)
            encoder.userInfo[userInfoKey] = codingContext
            let data = try encoder.encode(encodable)
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as AnyObject
        } catch {
            let nsError = error as NSError
            throw ReminderCLIError.fetchFailed(
                "Could not encode \(className): \(nsError.localizedDescription) \(nsError.userInfo)"
            )
        }
    }

    private func encodingContext(store: AnyObject) throws -> (CodingUserInfoKey, AnyObject) {
        let initializerName =
            "$s19ReminderKitInternal24REMStoreObjectsContainerC5store8storagesACSo0D0C_SDySo11REMObjectIDCypGtcfC"
        let keyGetterName =
            "$ss17CodingUserInfoKeyV19ReminderKitInternalE20remStoragesContainerABvgZ"
        let processHandle = UnsafeMutableRawPointer(bitPattern: -2)

        guard let initializerSymbol = dlsym(processHandle, initializerName),
            let keyGetterSymbol = dlsym(processHandle, keyGetterName),
            let containerClass = NSClassFromString("ReminderKitInternal.REMStoreObjectsContainer")
        else {
            throw ReminderCLIError.fetchFailed("Could not create the ReminderKit encoding context.")
        }

        // Encoding only requires a container of the exact private type. Keep the map
        // empty so no inaccessible Dictionary<REMObjectID, Any> generic state crosses
        // the ABI boundary.
        let storages: [NSObject: Any] = [:]

        let getKey = unsafeBitCast(keyGetterSymbol, to: REMStoragesContainerKeyGetter.self)
        let rawStorages = unsafeBitCast(storages, to: UnsafeMutableRawPointer.self)
        // ReminderKit's allocating initializer receives its metatype in x20 on arm64;
        // the assembly shim preserves that Swift calling convention.
        guard
            let container = ObjCCallSwiftAllocatingInitializer(
                initializerSymbol,
                store,
                rawStorages,
                containerClass
            ) as AnyObject?
        else {
            throw ReminderCLIError.fetchFailed("ReminderKit returned no encoding context.")
        }
        withExtendedLifetime(storages) {}
        return (getKey(), container)
    }

    func objectArray(_ value: Any?) -> [AnyObject]? {
        if let array = value as? [AnyObject] {
            return array
        }

        if let array = value as? NSArray {
            return array.compactMap { $0 as AnyObject }
        }

        if let dictionary = value as? NSDictionary {
            return dictionary.allValues.compactMap { $0 as AnyObject }
        }

        if let ordered = value as? NSOrderedSet {
            return ordered.array.compactMap { $0 as AnyObject }
        }

        if let set = value as? NSSet {
            return set.allObjects.compactMap { $0 as AnyObject }
        }

        return nil
    }

    func objectIDString(from object: AnyObject) -> String {
        if let objectID = objectValue(from: object, selectors: ["remObjectID", "objectID"]) {
            return stableObjectIDString(from: objectID)
        }

        return stableObjectIDString(from: object)
    }

    func objectValue(from object: AnyObject, selectors: [String]) -> AnyObject? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if object.responds(to: selector),
                let value = ObjCSendId(object, selector) as AnyObject?
            {
                return value
            }
        }

        return nil
    }

    func stableObjectIDString(from objectID: AnyObject) -> String {
        let uuid = rawStringValue(from: objectID, selectors: ["uuid", "UUID", "identifier"])
        let entityName = rawStringValue(from: objectID, selectors: ["entityName"])

        if let uuid, let entityName {
            return "\(entityName):\(uuid)"
        }

        if let uuid {
            return uuid
        }

        return String(describing: objectID)
    }

    func stringValue(from object: AnyObject, selectors: [String]) -> String? {
        for selectorName in selectors {
            guard let value = objectValue(from: object, selectors: [selectorName]),
                let rawString = value as? String
            else {
                continue
            }

            let string = sanitizedReminderText(rawString)
            if !string.isEmpty {
                return string
            }
        }

        return nil
    }

    func rawStringValue(from object: AnyObject, selectors: [String]) -> String? {
        for selectorName in selectors {
            guard let value = objectValue(from: object, selectors: [selectorName]) else {
                continue
            }

            if let uuid = value as? UUID {
                return uuid.uuidString
            }

            if let rawString = value as? String {
                return rawString
            }

            if value is NSUUID {
                return String(describing: value)
            }
        }

        return nil
    }

    func boolValue(from object: AnyObject, selectors: [String]) -> Bool? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if object.responds(to: selector) {
                return ObjCSendBool(object, selector)
            }
        }

        return nil
    }

    func intValue(from object: AnyObject, selectors: [String]) -> Int? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if object.responds(to: selector) {
                return ObjCSendInteger(object, selector)
            }
        }

        return nil
    }

    func doubleValue(from object: AnyObject, selectors: [String]) -> Double? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if object.responds(to: selector) {
                return ObjCSendDouble(object, selector)
            }
        }

        return nil
    }

    func dateStringValue(from object: AnyObject, selectors: [String]) -> String? {
        for selectorName in selectors {
            guard let value = objectValue(from: object, selectors: [selectorName]) else {
                continue
            }

            if let date = value as? Date {
                return ISO8601DateFormatter().string(from: date)
            }

            if let components = value as? DateComponents,
                let date = Calendar.current.date(from: components)
            {
                return ISO8601DateFormatter().string(from: date)
            }
        }

        return nil
    }

    func objectIDStringArray(from object: AnyObject, selectors: [String]) -> [String] {
        guard let value = objectValue(from: object, selectors: selectors) else {
            return []
        }

        return objectArray(value)?.map { stableObjectIDString(from: $0) } ?? []
    }

    func methods(on object: AnyObject, matching filter: String? = nil) -> [String] {
        let names = ObjCMethodNames(type(of: object))
        guard let filter else {
            return names
        }

        return names.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    private func sanitizedReminderText(_ rawString: String) -> String {
        var text = rawString.trimmingCharacters(in: .whitespacesAndNewlines)

        while let openBrace = text.lastIndex(of: "{"),
            text[text.index(after: openBrace)...].trimmingCharacters(in: .whitespacesAndNewlines) == "}"
        {
            text = String(text[..<openBrace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }
}
