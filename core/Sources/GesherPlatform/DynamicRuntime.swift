import Foundation
import ObjCRuntimeSupport

public final class FrameworkLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var loadedPaths: Set<String> = []

    public init() {}

    @discardableResult
    public func loadFirst(from candidates: [String]) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        for path in candidates {
            if loadedPaths.contains(path) {
                return path
            }
            if dlopen(path, RTLD_NOW | RTLD_LOCAL) != nil {
                loadedPaths.insert(path)
                return path
            }
        }
        throw PlatformError.frameworkLoadFailed(candidates)
    }

    public func loadOptional(from candidates: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        for path in candidates {
            if loadedPaths.contains(path) {
                return true
            }
            if dlopen(path, RTLD_NOW | RTLD_LOCAL) != nil {
                loadedPaths.insert(path)
                return true
            }
        }
        return false
    }
}

public final class DynamicRuntime: @unchecked Sendable {
    public static let shared = DynamicRuntime()

    public init() {}

    public func requireClass(_ name: String) throws -> NSObject.Type {
        guard let cls = NSClassFromString(name) as? NSObject.Type else {
            throw PlatformError.missingClass(name)
        }
        return cls
    }

    public func alloc(_ cls: AnyClass) throws -> AnyObject {
        guard let allocated = ObjCAlloc(cls) as AnyObject? else {
            throw PlatformError.storeInitializationFailed("Failed to alloc \(cls)")
        }
        return allocated
    }

    public func allocInit(_ clsName: String) throws -> AnyObject {
        let cls = try requireClass(clsName)
        let allocated = try alloc(cls)
        let initSel = NSSelectorFromString("init")
        if allocated.responds(to: initSel), let inst = ObjCSendId(allocated, initSel) as AnyObject? {
            return inst
        }
        return allocated
    }

    public func sendObject(_ target: AnyObject, selector: String) -> AnyObject? {
        let sel = NSSelectorFromString(selector)
        guard ObjCMatchesMethodSignature(target, sel, "@#", []) else { return nil }
        return ObjCSendId(target, sel) as AnyObject?
    }

    public func sendObject(_ target: AnyObject, selector: String, argument: AnyObject) -> AnyObject? {
        let sel = NSSelectorFromString(selector)
        guard ObjCMatchesMethodSignature(target, sel, "@#", ["@#"]) else { return nil }
        return ObjCSendIdIdArg(target, sel, argument) as AnyObject?
    }

    public func requireObject(_ target: AnyObject, selector: String) throws -> AnyObject {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: String(describing: type(of: target)),
                selector: selector
            )
        }
        guard let obj = ObjCSendId(target, sel) as AnyObject? else {
            throw PlatformError.fetchFailed("\(selector) returned nil.")
        }
        return obj
    }

    public func sendVoid(_ target: AnyObject, selector: String) throws {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: String(describing: type(of: target)),
                selector: selector
            )
        }
        _ = try NativeProperty.selector(target, selector, returns: "v", arguments: [])
        ObjCSendVoid(target, sel)
    }

    public func sendVoidId(_ target: AnyObject, selector: String, argument: AnyObject) throws {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: String(describing: type(of: target)),
                selector: selector
            )
        }
        _ = try NativeProperty.selector(target, selector, returns: "v", arguments: ["@#"])
        ObjCSendVoidId(target, sel, argument)
    }

    public func sendVoidBool(_ target: AnyObject, selector: String, value: Bool) throws {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: String(describing: type(of: target)),
                selector: selector
            )
        }
        _ = try NativeProperty.selector(target, selector, returns: "v", arguments: ["Bc"])
        ObjCSendVoidBool(target, sel, value)
    }

    public func sendVoidInteger(_ target: AnyObject, selector: String, value: Int) throws {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: String(describing: type(of: target)),
                selector: selector
            )
        }
        if ObjCMatchesMethodSignature(target, sel, "v", ["i"]), let narrowed = Int32(exactly: value) {
            ObjCSendVoidInt32(target, sel, narrowed)
        } else if ObjCMatchesMethodSignature(target, sel, "v", ["I"]), let narrowed = UInt32(exactly: value) {
            ObjCSendVoidUInt32(target, sel, narrowed)
        } else {
            _ = try NativeProperty.selector(target, selector, returns: "v", arguments: ["qQ"])
            ObjCSendVoidInteger(target, sel, value)
        }
    }

    public func sendVoidDouble(_ target: AnyObject, selector: String, value: Double) throws {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: String(describing: type(of: target)),
                selector: selector
            )
        }
        _ = try NativeProperty.selector(target, selector, returns: "v", arguments: ["d"])
        ObjCSendVoidDouble(target, sel, value)
    }

    public func objectArray(_ value: Any?) -> [AnyObject]? {
        if let array = value as? [AnyObject] {
            return array
        }
        if let array = value as? NSArray {
            return array.compactMap { $0 as AnyObject }
        }
        if let dictionary = value as? NSDictionary {
            return dictionary.allValues.compactMap { $0 as AnyObject }
        }
        if let set = value as? NSSet {
            return set.allObjects.compactMap { $0 as AnyObject }
        }
        return nil
    }

    public func objectValue(from object: AnyObject, selectors: [String]) -> AnyObject? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if ObjCMatchesMethodSignature(object, selector, "@#", []),
                let value = ObjCSendId(object, selector) as AnyObject?
            {
                return value
            }
        }
        return nil
    }

    public func stringValue(from object: AnyObject, selectors: [String]) -> String? {
        for selectorName in selectors {
            guard let value = objectValue(from: object, selectors: [selectorName]),
                let str = value as? String
            else {
                continue
            }
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    public func rawStringValue(from object: AnyObject, selectors: [String]) -> String? {
        for selectorName in selectors {
            guard let value = objectValue(from: object, selectors: [selectorName]) else {
                continue
            }
            if let uuid = value as? UUID {
                return uuid.uuidString
            }
            if let str = value as? String {
                return str
            }
            if value is NSUUID {
                return String(describing: value)
            }
        }
        return nil
    }

    public func boolValue(from object: AnyObject, selectors: [String]) -> Bool? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if ObjCMatchesMethodSignature(object, selector, "Bc", []) {
                return ObjCSendBool(object, selector)
            }
        }
        return nil
    }

    public func intValue(from object: AnyObject, selectors: [String]) -> Int? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if ObjCMatchesMethodSignature(object, selector, "qQ", []) {
                return ObjCSendInteger(object, selector)
            }
        }
        return nil
    }

    public func doubleValue(from object: AnyObject, selectors: [String]) -> Double? {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if ObjCMatchesMethodSignature(object, selector, "d", []) {
                return ObjCSendDouble(object, selector)
            }
        }
        return nil
    }

    public func dateStringValue(from object: AnyObject, selectors: [String]) -> String? {
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

    public func stableObjectIDString(from objectID: AnyObject) -> String {
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

    public func objectIDString(from object: AnyObject) -> String {
        if let objectID = objectValue(from: object, selectors: ["remObjectID", "objectID", "identifier"]) {
            return stableObjectIDString(from: objectID)
        }
        return stableObjectIDString(from: object)
    }

    public func methods(on object: AnyObject, matching filter: String? = nil) -> [String] {
        let names = ObjCMethodNames(type(of: object))
        guard let filter else {
            return names
        }
        return names.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
}
