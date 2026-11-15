import Foundation
import ObjCRuntimeSupport

extension ReminderKitRuntime {
    func makeColor(_ value: ReminderColor) throws -> AnyObject {
        try load()
        guard let colorClass = NSClassFromString("REMColor") as? NSObject.Type,
            let allocated = ObjCAlloc(colorClass) as AnyObject?
        else {
            throw ReminderCLIError.missingClass("REMColor")
        }
        let name = "initWithHexString:"
        let selector = NSSelectorFromString(name)
        guard allocated.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: "REMColor", selector: name)
        }
        guard let color = ObjCSendInitId(allocated, selector, value.hex as NSString) as AnyObject? else {
            // A nil initializer result does not mean the selector is absent.
            throw ReminderCLIError.unsupportedPrivateAPI(
                selector: name, reason: "REMColor rejected validated color \(value.hex)."
            )
        }
        return color
    }
}
