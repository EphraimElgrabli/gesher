import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// A custom smart list (the app's "Make into Smart List").
public struct ReminderSmartListSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let accountID: String?
    public let groupID: String?
    public let emoji: String?
    public let colorHex: String?
    public let isPinned: Bool
    public let filter: SmartListFilter

    public init(
        id: String, title: String, accountID: String?, groupID: String?, emoji: String?, colorHex: String?,
        isPinned: Bool, filter: SmartListFilter
    ) {
        self.id = id
        self.title = title
        self.accountID = accountID
        self.groupID = groupID
        self.emoji = emoji
        self.colorHex = colorHex
        self.isPinned = isPinned
        self.filter = filter
    }
}

/// A list template (the app's "Save as Template").
public struct ReminderTemplateSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let accountID: String?
    public let emoji: String?
    public let colorHex: String?
    /// The list the template was saved from, when the app recorded it.
    public let sourceListID: String?
    public let includesCompleted: Bool?

    public init(
        id: String, title: String, accountID: String?, emoji: String?, colorHex: String?, sourceListID: String?,
        includesCompleted: Bool?
    ) {
        self.id = id
        self.title = title
        self.accountID = accountID
        self.emoji = emoji
        self.colorHex = colorHex
        self.sourceListID = sourceListID
        self.includesCompleted = includesCompleted
    }
}

extension ReminderReadRepository {
    // MARK: - Smart lists

    func smartListObjects(store: AnyObject) throws -> [AnyObject] {
        let view = try runtime.make("REMSmartListsDataView", "initWithStore:", store)
        let selector = NSSelectorFromString("fetchCustomSmartListsWithError:")
        guard view.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: "REMSmartListsDataView", selector: "fetchCustomSmartListsWithError:")
        }
        var error: NSError?
        let result = ObjCSendIdError(view, selector, &error)
        if let error { throw ReminderCLIError.fetchFailed(error.localizedDescription) }
        guard let lists = runtime.objectArray(result) else {
            throw ReminderCLIError.fetchFailed("Custom smart lists collection is missing.")
        }
        return lists
    }

    func smartListSnapshot(_ object: AnyObject) throws -> ReminderSmartListSnapshot {
        let storage = runtime.objectValue(from: object, selectors: ["storage"]) ?? object
        let data = runtime.objectValue(from: storage, selectors: ["filterData"]) as? Data
        let filter = try data.map(SmartListFilter.init(native:)) ?? SmartListFilter()
        let context = runtime.objectValue(from: object, selectors: ["customContext"])
        let badge = context.flatMap { runtime.objectValue(from: $0, selectors: ["badge"]) }
        return ReminderSmartListSnapshot(
            id: runtime.objectIDString(from: object),
            title: runtime.stringValue(from: storage, selectors: ["name"])
                ?? context.flatMap { runtime.stringValue(from: $0, selectors: ["name"]) } ?? "Untitled Smart List",
            accountID: runtime.objectValue(from: storage, selectors: ["accountID"]).map {
                runtime.stableObjectIDString(from: $0)
            },
            groupID: runtime.objectValue(from: storage, selectors: ["parentListID"]).map {
                runtime.stableObjectIDString(from: $0)
            },
            emoji: badge.flatMap { runtime.stringValue(from: $0, selectors: ["emoji", "emblem"]) }
                ?? runtime.stringValue(from: storage, selectors: ["badgeEmblem"]),
            colorHex: runtime.objectValue(from: storage, selectors: ["color"]).flatMap {
                runtime.stringValue(from: $0, selectors: ["hexString", "daHexString"])
            },
            isPinned: runtime.boolValue(from: object, selectors: ["isPinned"]) ?? false, filter: filter)
    }

    public func fetchSmartLists() throws -> [ReminderSmartListSnapshot] {
        let store = try runtime.makeStore()
        return try smartListObjects(store: store).map(smartListSnapshot)
    }

    func findSmartList(id: String, store: AnyObject) throws -> AnyObject {
        guard let object = try smartListObjects(store: store).first(where: { runtime.objectIDString(from: $0) == id })
        else { throw ReminderCLIError.objectNotFound(type: "smart list", id: id) }
        return object
    }

    public func fetchSmartList(id: String) throws -> ReminderSmartListSnapshot {
        try smartListSnapshot(try findSmartList(id: id, store: try runtime.makeStore()))
    }

    /// Ids of the reminders the daemon matches for a custom smart list, in its display order.
    public func fetchSmartListTaskIDs(id: String, includeCompleted: Bool) throws -> [String] {
        let store = try runtime.makeStore()
        let smartList = try findSmartList(id: id, store: store)
        let parameters: NSDictionary = [
            "smartList": try runtime.codablePropertyList(
                fromStorageBacked: smartList, className: "REMSmartList_Codable"),
            "sortingStyle": ["base": "creationDate", "sortDirection": 0],
            "showCompleted": ["base": includeCompleted ? "on" : "off"],
            "countCompleted": false,
            "remindersPrefetch": ["base": "none"],
            "fetchSubtasks": "off",
            "shouldFetchManualOrderingID": false,
        ]
        // The smart list is encoded by id; the daemon decodes it from these storages (the account too).
        let related = ["account", "parentList"].compactMap { runtime.objectValue(from: smartList, selectors: [$0]) }
        let payload = try invoke(
            "REMRemindersListDataView_CustomSmartListInvocation", parameters: parameters, store: store,
            storages: [smartList] + related)
        guard let model = payload["model"] as? NSDictionary else {
            throw ReminderCLIError.fetchFailed("Smart list result has no model.")
        }
        var ids: [String] = []
        func collect(_ value: Any) {
            if let dictionary = value as? NSDictionary {
                if let objectID = dictionary["objectID"] as? NSDictionary,
                    let id = stableObjectIDString(fromPropertyListDictionary: objectID), id.hasPrefix("REMCDReminder:")
                {
                    if !ids.contains(id) { ids.append(id) }
                }
                for key in dictionary.allKeys.compactMap({ $0 as? String }).sorted() { collect(dictionary[key]!) }
            } else if let array = value as? NSArray {
                for element in array { collect(element) }
            }
        }
        collect(model)
        return ids
    }

    /// Runs a ReminderKit Swift data-view invocation and returns its decoded result payload.
    func invoke(_ className: String, parameters: NSDictionary, store: AnyObject, storages objects: [AnyObject])
        throws -> NSDictionary
    {
        guard
            let payload = try invokeRaw(className, parameters: parameters, store: store, storages: objects)
                as? NSDictionary
        else { throw ReminderCLIError.fetchFailed("\(className) returned no result payload.") }
        return payload
    }

    /// Every tag the app shows in its sidebar, including tags no current task uses.
    public func fetchTagNames() throws -> [String] {
        let store = try runtime.makeStore()
        let result = try invokeRaw(
            "REMHashtagLabelDataView_AllHashtagLabelsInvocation", parameters: ["sortingStyle": 1], store: store,
            storages: [])
        guard let labels = result as? [NSDictionary] else {
            throw ReminderCLIError.fetchFailed("Tag labels result is malformed.")
        }
        return labels.compactMap { $0["name"] as? String }
    }

    func invokeRaw(_ className: String, parameters: NSDictionary, store: AnyObject, storages objects: [AnyObject])
        throws -> Any
    {
        guard let cls = NSClassFromString(className) as? NSObject.Type, let allocated = ObjCAlloc(cls) as AnyObject?
        else { throw ReminderCLIError.missingClass(className) }
        let initSelector = NSSelectorFromString("initWithFetchResultTokenToDiffAgainst:")
        guard allocated.responds(to: initSelector),
            let invocation = ObjCSendInitNil(allocated, initSelector) as AnyObject?
        else {
            throw ReminderCLIError.missingSelector(
                className: className, selector: "initWithFetchResultTokenToDiffAgainst:")
        }
        let storages = NSMutableDictionary()
        for object in objects {
            if let objectID = runtime.objectValue(from: object, selectors: ["remObjectID", "objectID"]),
                let storage = runtime.objectValue(from: object, selectors: ["storage"])
            {
                storages[objectID] = storage
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: parameters, format: .binary, options: 0)
        let result = try runtime.performSwiftInvocation(
            store: store, invocation: invocation, parametersData: data, storages: storages)
        guard let resultData = runtime.objectValue(from: result, selectors: ["resultData"]) as? Data else {
            throw ReminderCLIError.fetchFailed("\(className) returned no result payload.")
        }
        return try PropertyListSerialization.propertyList(from: resultData, options: [], format: nil)
    }

    // MARK: - Templates

    func templateObjects(store: AnyObject) throws -> [AnyObject] {
        let view = try runtime.make("REMTemplatesDataView", "initWithStore:", store)
        var templates: [AnyObject] = []
        for account in try fetchAccounts(from: store) {
            let selector = NSSelectorFromString("fetchTemplatesInAccount:error:")
            guard view.responds(to: selector) else {
                throw ReminderCLIError.missingSelector(
                    className: "REMTemplatesDataView", selector: "fetchTemplatesInAccount:error:")
            }
            var error: NSError?
            let result = ObjCSendIdIdError(view, selector, account.object, &error)
            if let error { throw ReminderCLIError.fetchFailed(error.localizedDescription) }
            templates += runtime.objectArray(result) ?? []
        }
        return templates
    }

    func templateSnapshot(_ object: AnyObject) -> ReminderTemplateSnapshot {
        let storage = runtime.objectValue(from: object, selectors: ["storage"]) ?? object
        let configuration = runtime.objectValue(from: storage, selectors: ["configuration"])
        let badge = runtime.objectValue(from: object, selectors: ["badge"])
        return ReminderTemplateSnapshot(
            id: runtime.objectIDString(from: object),
            title: runtime.stringValue(from: storage, selectors: ["name"]) ?? "Untitled Template",
            accountID: runtime.objectValue(from: storage, selectors: ["accountID"]).map {
                runtime.stableObjectIDString(from: $0)
            },
            emoji: badge.flatMap { runtime.stringValue(from: $0, selectors: ["emoji", "emblem"]) }
                ?? runtime.stringValue(from: storage, selectors: ["badgeEmblem"]),
            colorHex: runtime.objectValue(from: storage, selectors: ["color"]).flatMap {
                runtime.stringValue(from: $0, selectors: ["hexString", "daHexString"])
            },
            sourceListID: configuration.flatMap { runtime.objectValue(from: $0, selectors: ["sourceListID"]) }.map {
                runtime.stableObjectIDString(from: $0)
            },
            includesCompleted: configuration.flatMap {
                runtime.boolValue(from: $0, selectors: ["shouldSaveCompleted"])
            })
    }

    public func fetchTemplates() throws -> [ReminderTemplateSnapshot] {
        try templateObjects(store: try runtime.makeStore()).map(templateSnapshot)
    }

    func findTemplate(id: String, store: AnyObject) throws -> AnyObject {
        guard let object = try templateObjects(store: store).first(where: { runtime.objectIDString(from: $0) == id })
        else { throw ReminderCLIError.objectNotFound(type: "template", id: id) }
        return object
    }
}

extension ReminderWriteRepository {
    // MARK: - Smart lists

    private func applySmartListFields(
        _ item: AnyObject, name: String?, filter: SmartListFilter?, emoji: String?, color: ReminderColor?
    ) throws {
        let context = try runtime.requireObject(item, selector: "customContext")
        if let name { try runtime.sendVoidId(context, selector: "setName:", argument: name as NSString) }
        if let filter {
            // The daemon parses filterData by the list's minimumSupportedVersion; ours is always v2.
            try runtime.sendVoidInteger(
                item, selector: "setMinimumSupportedVersion:", value: SmartListFilter.nativeVersion)
            try runtime.sendVoidId(item, selector: "setFilterData:", argument: try filter.nativeData() as NSData)
        }
        if let emoji { try runtime.sendVoidId(context, selector: "setBadge:", argument: runtime.makeListBadge(emoji)) }
        if let color { try runtime.sendVoidId(context, selector: "setColor:", argument: runtime.makeColor(color)) }
    }

    private func verifySmartList(
        _ result: ReminderSmartListSnapshot, name: String?, filter: SmartListFilter?, emoji: String?
    ) throws {
        if let name, result.title != name { throw unverified("smart list", result.id, "its name did not round-trip") }
        if let filter, try result.filter.nativeData() != filter.nativeData() {
            throw unverified("smart list", result.id, "its filter did not round-trip")
        }
        if let emoji, result.emoji != emoji {
            throw unverified("smart list", result.id, "its emoji did not round-trip")
        }
    }

    public func createSmartList(
        accountID: String, name: String, filter: SmartListFilter, emoji: String? = nil, colorHex: String? = nil
    ) throws -> ReminderSmartListSnapshot {
        try validateTitle(name, "Name")
        _ = try filter.nativeData()
        let color = try colorHex.map(ReminderColor.init)
        let store = try runtime.makeStore()
        guard let account = try read.fetchAccounts(from: store).first(where: { $0.snapshot.id == accountID }) else {
            throw ReminderCLIError.objectNotFound(type: "account", id: accountID)
        }
        guard let smartListClass = NSClassFromString("REMSmartList"),
            let objectID = runtime.sendObject(smartListClass as AnyObject, selector: "newObjectID")
        else { throw ReminderCLIError.missingClass("REMSmartList") }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let accountItem = try updateAccount(account.object, saveRequest)
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject) -> AnyObject?
        let (selector, add) = try runtime.implementation(
            saveRequest, "addCustomSmartListWithName:toAccountChangeItem:smartListObjectID:", as: Add.self)
        guard let item = add(saveRequest, selector, name as NSString, accountItem, objectID) else {
            throw ReminderCLIError.saveFailed("ReminderKit did not create the smart list.")
        }
        try applySmartListFields(item, name: nil, filter: filter, emoji: emoji, color: color)
        let id = runtime.objectIDString(from: item)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "smart list", id: id) {
            try read.fetchSmartList(id: id)
        }
        try verifySmartList(result, name: name, filter: filter, emoji: emoji)
        return result
    }

    public func updateSmartList(
        id: String, name: String? = nil, filter: SmartListFilter? = nil, emoji: String? = nil, colorHex: String? = nil
    ) throws -> ReminderSmartListSnapshot {
        guard name != nil || filter != nil || emoji != nil || colorHex != nil else {
            throw ReminderCLIError.invalidArgument("Nothing to change. No write was started.")
        }
        if let name { try validateTitle(name, "Name") }
        _ = try filter?.nativeData()
        let color = try colorHex.map(ReminderColor.init)
        let store = try runtime.makeStore()
        let object = try read.findSmartList(id: id, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try changeItem(saveRequest, "updateSmartList:", object)
        try applySmartListFields(item, name: name, filter: filter, emoji: emoji, color: color)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "smart list", id: id) {
            try read.fetchSmartList(id: id)
        }
        try verifySmartList(result, name: name, filter: filter, emoji: emoji)
        return result
    }

    public func deleteSmartList(id: String) throws {
        let store = try runtime.makeStore()
        let object = try read.findSmartList(id: id, store: store)
        guard let account = runtime.objectValue(from: object, selectors: ["account"]) else {
            throw ReminderCLIError.fetchFailed("The smart list's account is unavailable.")
        }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try changeItem(saveRequest, "updateSmartList:", object)
        try runtime.sendVoidId(
            item, selector: "removeFromParentWithAccountChangeItem:", argument: try updateAccount(account, saveRequest))
        try runtime.saveSynchronously(saveRequest)
        try MutationVerification.absence(id: id, type: "smart list") { try read.fetchSmartList(id: id) }
    }

    // MARK: - Templates

    /// Saves a list as a template (its tasks and sections are copied by ReminderKit).
    public func createTemplate(listID: String, name: String, includeCompleted: Bool) throws
        -> ReminderTemplateSnapshot
    {
        try validateTitle(name, "Name")
        let store = try runtime.makeStore()
        let handle = try read.findList(id: listID, store: store)
        guard !read.isGroup(handle.list) else {
            throw ReminderCLIError.invalidArgument("Groups cannot be saved as templates; pick a list.")
        }
        guard let configurationClass = NSClassFromString("REMTemplateConfiguration") as? NSObject.Type,
            let allocated = ObjCAlloc(configurationClass) as AnyObject?
        else { throw ReminderCLIError.missingClass("REMTemplateConfiguration") }
        typealias Init = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> AnyObject?
        let (initSelector, initialize) = try runtime.implementation(
            allocated, "initWithSourceListID:shouldSaveCompleted:", as: Init.self)
        guard let configuration = initialize(allocated, initSelector, try objectID(of: handle.list), includeCompleted)
        else { throw ReminderCLIError.saveFailed("ReminderKit rejected the template configuration.") }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let accountItem = try updateAccount(handle.account, saveRequest)
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject) -> AnyObject?
        let (selector, add) = try runtime.implementation(
            saveRequest, "addTemplateWithName:configuration:toAccountChangeItem:", as: Add.self)
        guard let item = add(saveRequest, selector, name as NSString, configuration, accountItem) else {
            throw ReminderCLIError.saveFailed("ReminderKit did not create the template.")
        }
        let id = runtime.objectIDString(from: item)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "template", id: id) {
            read.templateSnapshot(try read.findTemplate(id: id, store: try runtime.makeStore()))
        }
        guard result.title == name else { throw unverified("template", id, "its name did not round-trip") }
        return result
    }

    /// Creates a new list from a template, as "New List from Template" does.
    public func applyTemplate(id: String, accountID: String?) throws -> ReminderListSnapshot {
        let store = try runtime.makeStore()
        let template = try read.findTemplate(id: id, store: store)
        let accounts = try read.fetchAccounts(from: store)
        let templateAccount = read.templateSnapshot(template).accountID
        guard
            let account = accounts.first(where: { $0.snapshot.id == (accountID ?? templateAccount) })
                ?? accounts.first(where: { $0.snapshot.isDefault == true }) ?? accounts.first
        else { throw ReminderCLIError.objectNotFound(type: "account", id: accountID ?? "default") }
        let before = Set(try read.fetchCatalog(taskLists: []).lists.map(\.id))
        let saveRequest = try runtime.makeSaveRequest(store: store)
        guard
            let created = try runtime.sendObjectOptional(
                saveRequest, "addListUsingTemplate:toAccountChangeItem:", template,
                try updateAccount(account.object, saveRequest))
        else { throw ReminderCLIError.saveFailed("ReminderKit did not create a list from the template.") }
        let listID = runtime.objectIDString(from: created)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "list", id: listID) { try read.fetchList(id: listID) }
        guard !before.contains(result.id) else { throw unverified("list", listID, "no new list appeared") }
        return result
    }

    public func deleteTemplate(id: String) throws {
        let store = try runtime.makeStore()
        let template = try read.findTemplate(id: id, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try changeItem(saveRequest, "updateTemplate:", template)
        try runtime.sendVoid(item, selector: "removeFromParentAccount")
        try runtime.saveSynchronously(saveRequest)
        try MutationVerification.absence(id: id, type: "template") {
            try read.findTemplate(id: id, store: try runtime.makeStore())
        }
    }
}
