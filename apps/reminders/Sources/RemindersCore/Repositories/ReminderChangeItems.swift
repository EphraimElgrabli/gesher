import GesherPlatform
import Foundation
import ObjCRuntimeSupport

extension ReminderWriteRepository {
    func changeItem(_ saveRequest: AnyObject, _ selectorName: String, _ object: AnyObject) throws -> AnyObject {
        let selector = NSSelectorFromString(selectorName)
        guard saveRequest.responds(to: selector),
            let changeItem = ObjCSendIdIdArg(saveRequest, selector, object) as AnyObject?
        else {
            throw ReminderCLIError.missingSelector(className: "REMSaveRequest", selector: selectorName)
        }
        return changeItem
    }

    func updateAccount(_ account: AnyObject, _ saveRequest: AnyObject) throws -> AnyObject {
        try changeItem(saveRequest, "updateAccount:", account)
    }

    func updateList(_ list: AnyObject, _ saveRequest: AnyObject) throws -> AnyObject {
        try changeItem(saveRequest, "updateList:", list)
    }

    func updateSection(_ section: AnyObject, _ saveRequest: AnyObject) throws -> AnyObject {
        try changeItem(saveRequest, "updateListSection:", section)
    }

    func updateReminder(_ reminder: AnyObject, _ saveRequest: AnyObject) throws -> AnyObject {
        try changeItem(saveRequest, "updateReminder:", reminder)
    }

    func applyListAppearance(_ listChangeItem: AnyObject, emoji: String?, color: ReminderColor?) throws {
        if let emoji {
            let appearance = try runtime.requireObject(listChangeItem, selector: "appearanceContext")
            try runtime.sendVoidId(appearance, selector: "setBadge:", argument: runtime.makeListBadge(emoji))
        }
        if let color {
            try runtime.sendVoidId(listChangeItem, selector: "setColor:", argument: runtime.makeColor(color))
        }
    }

    func uuid(of object: AnyObject) throws -> NSUUID {
        let objectID = runtime.objectValue(from: object, selectors: ["remObjectID", "objectID"]) ?? object
        guard let value = runtime.objectValue(from: objectID, selectors: ["uuid"]) as? NSUUID else {
            throw ReminderCLIError.fetchFailed("Native object has no UUID.")
        }
        return value
    }

    func objectID(of object: AnyObject) throws -> AnyObject {
        guard let objectID = runtime.objectValue(from: object, selectors: ["remObjectID", "objectID"]) else {
            throw ReminderCLIError.fetchFailed("Native object has no object ID.")
        }
        return objectID
    }

    /// Writes the complete section membership map of a list. ReminderKit replaces the stored
    /// memberships with this map, so it is built from the current native memberships (including
    /// completed reminders) and only `changes` differ.
    func writeMembership(
        listChangeItem: AnyObject, current: [String: String], sectionOrder: [AnyObject],
        changes: [(reminderUUID: NSUUID, sectionUUID: NSUUID?)]
    ) throws {
        let map = NSMutableDictionary()
        let now = Date() as NSDate
        func membership(_ member: NSUUID, _ group: NSUUID) throws -> AnyObject {
            guard let cls = NSClassFromString("REMMembership") as? NSObject.Type,
                let allocated = ObjCAlloc(cls) as AnyObject?
            else { throw ReminderCLIError.missingClass("REMMembership") }
            let selector = NSSelectorFromString("initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:")
            guard allocated.responds(to: selector),
                let value = ObjCSendInitIdIdBoolId(allocated, selector, member, group, false, now) as AnyObject?
            else {
                throw ReminderCLIError.missingSelector(
                    className: "REMMembership",
                    selector: "initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:")
            }
            return value
        }
        // Unchanged entries are rewritten with their current section so the map stays complete.
        for (reminderID, sectionID) in current {
            guard let member = Self.uuid(fromStableID: reminderID), let group = Self.uuid(fromStableID: sectionID)
            else { continue }
            map[member] = try membership(member, group)
        }
        for change in changes {
            if let section = change.sectionUUID {
                map[change.reminderUUID] = try membership(change.reminderUUID, section)
            } else {
                // Stored memberships merge with these by date, so an omitted or obsolete entry keeps
                // the old section. Pointing the reminder at the list itself (not a section) is what
                // takes it out of every section in the native data view.
                map[change.reminderUUID] = try membership(change.reminderUUID, try uuid(of: listChangeItem))
            }
        }
        let memberships = try runtime.make("REMMemberships", "initWithMembershipByMemberIdentifier:", map)
        let context = try runtime.requireObject(listChangeItem, selector: "sectionsContextChangeItem")
        try runtime.sendVoidId(context, selector: "setUnsavedSectionIDsOrdering:", argument: sectionOrder as NSArray)
        try runtime.sendVoidId(context, selector: "setUnsavedMembershipsOfRemindersInSections:", argument: memberships)
    }

    static func uuid(fromStableID stableID: String) -> NSUUID? {
        let parts = stableID.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return NSUUID(uuidString: String(parts[1]))
    }
}
