import GesherPlatform
import Foundation
import ObjCRuntimeSupport

extension ReminderReadRepository {
    struct SectionedDataView {
        var membershipByReminderID: [String: String]
        var orderedReminderIDs: [String]
        var sectionOrder: [String] = []
    }

    func sectionedDataView(
        list: AnyObject,
        account: AnyObject,
        store: AnyObject,
        includeCompleted: Bool
    ) throws -> SectionedDataView {
        guard
            let invocationClass = NSClassFromString("REMRemindersListDataView_ListSectionsInvocation")
                as? NSObject.Type,
            let allocatedInvocation = ObjCAlloc(invocationClass) as AnyObject?
        else {
            throw ReminderCLIError.missingClass("REMRemindersListDataView_ListSectionsInvocation")
        }

        let initSelector = NSSelectorFromString("initWithFetchResultTokenToDiffAgainst:")
        guard allocatedInvocation.responds(to: initSelector),
            let invocation = ObjCSendInitNil(allocatedInvocation, initSelector) as AnyObject?
        else {
            throw ReminderCLIError.missingSelector(
                className: "REMRemindersListDataView_ListSectionsInvocation",
                selector: "initWithFetchResultTokenToDiffAgainst:"
            )
        }

        guard let listObjectID = runtime.objectValue(from: list, selectors: ["remObjectID", "objectID"]),
            let listStorage = runtime.objectValue(from: list, selectors: ["storage"]),
            let accountObjectID = runtime.objectValue(from: account, selectors: ["remObjectID", "objectID"]),
            let accountStorage = runtime.objectValue(from: account, selectors: ["storage"])
        else {
            throw ReminderCLIError.fetchFailed("ListSectionsInvocation requires list/account object IDs and storages.")
        }

        let parameters: NSDictionary = [
            "list": try runtime.codablePropertyList(fromList: list),
            "fetchPredefinedGroceryListSections": false,
            "configuration": [
                "sortingStyle": [
                    "base": "creationDate",
                    "sortDirection": 0,
                ],
                "showCompleted": [
                    "base": includeCompleted ? "on" : "off"
                ],
                "countCompleted": false,
                "remindersPrefetch": [
                    "base": "none"
                ],
                "fetchSubtasks": "off",
            ],
        ]

        // A list inside a group is encoded with its parent, whose storage must be supplied too.
        let storages = NSMutableDictionary(dictionary: [listObjectID: listStorage, accountObjectID: accountStorage])
        if let parent = runtime.objectValue(from: list, selectors: ["parentList"]),
            let parentID = runtime.objectValue(from: parent, selectors: ["remObjectID", "objectID"]),
            let parentStorage = runtime.objectValue(from: parent, selectors: ["storage"])
        {
            storages[parentID] = parentStorage
        }

        let parametersData = try PropertyListSerialization.data(
            fromPropertyList: parameters,
            format: .binary,
            options: 0
        )
        let result = try runtime.performSwiftInvocation(
            store: store,
            invocation: invocation,
            parametersData: parametersData,
            storages: storages
        )

        guard let resultData = runtime.objectValue(from: result, selectors: ["resultData"]) as? Data else {
            throw ReminderCLIError.fetchFailed("ListSectionsInvocation returned no resultData.")
        }

        guard
            let payload = try PropertyListSerialization.propertyList(from: resultData, options: [], format: nil)
                as? NSDictionary
        else {
            throw ReminderCLIError.fetchFailed("ListSectionsInvocation resultData was not a dictionary.")
        }

        return try sectionedDataView(fromResultPayload: payload)
    }

    func sectionedDataView(fromResultPayload payload: NSDictionary) throws -> SectionedDataView {
        guard let model = payload["model"] as? NSDictionary,
            let sectionsModel = model["sectionsModel"] as? NSDictionary,
            let sections = sectionsModel["sections"] as? [NSDictionary]
        else {
            throw ReminderCLIError.fetchFailed("Native section model or collection is missing or malformed.")
        }

        var membershipByReminderID: [String: String] = [:]
        var orderedReminderIDs: [String] = []
        var sectionOrder: [String] = []
        for section in sections {
            guard let type = section["type"] as? NSDictionary,
                let reminders = section["reminders"] as? [NSDictionary]
            else {
                throw ReminderCLIError.fetchFailed("Native section entry is malformed.")
            }
            if let sectioned = type["sectioned"] as? NSDictionary,
                (sectioned["sectionID"] as? NSDictionary).flatMap(stableObjectIDString(fromPropertyListDictionary:))
                    == nil
            {
                throw ReminderCLIError.fetchFailed("Native section identifier is malformed.")
            }
            let sectionID = (type["sectioned"] as? NSDictionary)
                .flatMap { $0["sectionID"] as? NSDictionary }
                .flatMap(stableObjectIDString(fromPropertyListDictionary:))
            if let sectionID { sectionOrder.append(sectionID) }

            for reminder in reminders {
                guard let reminderIDDictionary = reminder["objectID"] as? NSDictionary,
                    let reminderID = stableObjectIDString(fromPropertyListDictionary: reminderIDDictionary)
                else {
                    throw ReminderCLIError.fetchFailed("Native section reminder identifier is malformed.")
                }
                orderedReminderIDs.append(reminderID)
                if let sectionID {
                    membershipByReminderID[reminderID] = sectionID
                }
            }
        }

        return SectionedDataView(
            membershipByReminderID: membershipByReminderID, orderedReminderIDs: orderedReminderIDs,
            sectionOrder: sectionOrder)
    }

    func stableObjectIDString(fromPropertyListDictionary dictionary: NSDictionary) -> String? {
        let entity = dictionary["entityName"] as? String
        let uuid = (dictionary["uuid"] as? String) ?? (dictionary["objectIDUUID"] as? String)

        guard let uuid else {
            return nil
        }

        if let entity {
            return "\(entity):\(uuid)"
        }
        return uuid
    }

    func makeObjectID(fromStableID stableID: String) -> AnyObject? {
        let parts = stableID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
            let uuid = UUID(uuidString: parts[1]),
            let objectIDClass = NSClassFromString("REMObjectID") as? NSObject.Type
        else {
            return nil
        }

        let selector = NSSelectorFromString("objectIDWithUUID:entityName:")
        if objectIDClass.responds(to: selector) {
            return ObjCSendIdId(objectIDClass, selector, uuid as NSUUID, parts[0] as NSString) as AnyObject?
        }

        let initSelector = NSSelectorFromString("initWithUUID:entityName:")
        guard let allocated = ObjCAlloc(objectIDClass) as AnyObject?,
            allocated.responds(to: initSelector)
        else {
            return nil
        }
        return ObjCSendIdId(allocated, initSelector, uuid as NSUUID, parts[0] as NSString) as AnyObject?
    }
}
