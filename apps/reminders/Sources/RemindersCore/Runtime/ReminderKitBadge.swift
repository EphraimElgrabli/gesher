import Foundation
import ObjCRuntimeSupport

extension ReminderKitRuntime {
    func makeListBadge(_ value: String) throws -> AnyObject {
        try load()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReminderCLIError.invalidArgument("List badge cannot be empty.")
        }
        let isEmoji = value.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
        if isEmoji && value.count != 1 {
            throw ReminderCLIError.invalidArgument("List badge must contain a single emoji.")
        }
        guard let badgeClass = NSClassFromString("REMListBadge") as? NSObject.Type,
            let allocated = ObjCAlloc(badgeClass) as AnyObject?
        else {
            throw ReminderCLIError.missingClass("REMListBadge")
        }
        let name = isEmoji ? "initWithEmoji:" : "initWithEmblem:"
        let selector = NSSelectorFromString(name)
        guard allocated.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: "REMListBadge", selector: name)
        }
        guard let badge = ObjCSendInitId(allocated, selector, value as NSString) as AnyObject? else {
            throw ReminderCLIError.invalidArgument("ReminderKit rejected the list badge.")
        }
        return badge
    }

    func listBadgeValue(from list: AnyObject) -> String? {
        if let context = objectValue(from: list, selectors: ["appearanceContext"]),
            let badge = objectValue(from: context, selectors: ["badge"]),
            let value = stringValue(from: badge, selectors: ["emoji", "emblem"])
        {
            return value
        }
        return stringValue(from: list, selectors: ["badgeEmblem"])
    }
}
