import Foundation
import ObjCRuntimeSupport

public enum NativeProperty {
    public static func selector(_ object: AnyObject, _ name: String) throws -> Selector {
        let selector = NSSelectorFromString(name)
        guard ObjCRespondsOrForwardsSelector(object, selector) else {
            throw PlatformError.missingSelector(className: String(describing: type(of: object)), selector: name)
        }
        return selector
    }

    public static func selector(_ object: AnyObject, _ name: String, returns: String, arguments: [String]) throws
        -> Selector
    {
        let selector = try selector(object, name)
        guard ObjCMatchesMethodSignature(object, selector, returns, arguments) else {
            throw PlatformError.unsupportedPrivateAPI(
                selector: name, reason: "Native method signature does not match this adapter's ABI.")
        }
        return selector
    }

    public static func coordinateSelector(_ object: AnyObject) throws -> Selector {
        let selector = try selector(object, "coordinate")
        guard ObjCMatchesCoordinateGetter(object, selector) else {
            throw PlatformError.unsupportedPrivateAPI(
                selector: "coordinate", reason: "Expected a native pair of double coordinates; private ABI changed.")
        }
        return selector
    }

    /// KVC is used only for a verified getter, and Objective-C exceptions become Swift errors.
    public static func value(_ object: NSObject, key: String) throws -> AnyObject? {
        var error: NSError?
        let value = ObjCSafePropertyValue(object, key, &error)
        if let error { throw PlatformError.fetchFailed("Native property \(key): \(error.localizedDescription)") }
        return value as AnyObject?
    }
}
