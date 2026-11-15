import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Writes through `REMSaveRequest` change items only, then verifies every change by reading
/// it back through a fresh store. Selectors are resolved to ids by the caller.
public final class ReminderWriteRepository: @unchecked Sendable {
    let runtime: ReminderKitRuntime
    let read: ReminderReadRepository

    public init(runtime: ReminderKitRuntime, readRepository: ReminderReadRepository) {
        self.runtime = runtime
        self.read = readRepository
    }

    func validateTitle(_ value: String, _ what: String = "Title") throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReminderCLIError.invalidArgument("\(what) cannot be empty.")
        }
    }

    func unverified(_ type: String, _ id: String, _ what: String) -> PlatformError {
        .mutationUnverified(type: type, id: id, reason: "\(type.capitalized) \(id) was saved but \(what).")
    }

    // MARK: - Lists and groups

    /// Creates a list (or a group when `isGroup`), optionally inside a group.
    public func createList(
        accountID: String, name: String, emoji: String? = nil, colorHex: String? = nil, groupID: String? = nil,
        isGroup: Bool = false
    ) throws -> ReminderListSnapshot {
        try validateTitle(name, "Name")
        let color = try colorHex.map(ReminderColor.init)
        let store = try runtime.makeStore()
        guard let account = try read.fetchAccounts(from: store).first(where: { $0.snapshot.id == accountID }) else {
            throw ReminderCLIError.objectNotFound(type: "account", id: accountID)
        }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let accountItem = try updateAccount(account.object, saveRequest)
        let created: AnyObject?
        if isGroup {
            let groupContext = try runtime.requireObject(accountItem, selector: "groupContext")
            created = try runtime.sendObjectOptional(
                saveRequest, "addGroupWithName:toAccountGroupContextChangeItem:", name as NSString, groupContext)
        } else if let groupID {
            let group = try read.findList(id: groupID, store: store)
            guard read.isGroup(group.list) else { throw ReminderCLIError.invalidArgument("\(groupID) is not a group.") }
            let sublists = try runtime.requireObject(
                try updateList(group.list, saveRequest), selector: "sublistContext")
            created = try runtime.sendObjectOptional(
                saveRequest, "addListWithName:toListSublistContextChangeItem:", name as NSString, sublists)
        } else {
            created = try runtime.sendObjectOptional(
                saveRequest, "addListWithName:toAccountChangeItem:", name as NSString, accountItem)
        }
        guard let listItem = created else { throw ReminderCLIError.saveFailed("ReminderKit did not create the list.") }
        try applyListAppearance(listItem, emoji: emoji, color: color)
        let id = runtime.objectIDString(from: listItem)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "list", id: id) { try read.fetchList(id: id) }
        guard result.title == name, result.isGroup == isGroup, isGroup || result.groupID == groupID else {
            throw unverified("list", id, "its name or group did not round-trip")
        }
        try verifyAppearance(emoji: emoji, color: color, list: result)
        return result
    }

    /// Renames, restyles, or moves a list into (`.set`) or out of (`.clear`) a group.
    public func updateList(
        id: String, name: String? = nil, emoji: String? = nil, colorHex: String? = nil,
        group: FieldChange<String>? = nil
    ) throws -> ReminderListSnapshot {
        guard name != nil || emoji != nil || colorHex != nil || group != nil else {
            throw ReminderCLIError.invalidArgument("Nothing to change. No write was started.")
        }
        if let name { try validateTitle(name, "Name") }
        let color = try colorHex.map(ReminderColor.init)
        let store = try runtime.makeStore()
        let handle = try read.findList(id: id, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let listItem = try updateList(handle.list, saveRequest)
        if let name { try runtime.sendVoidId(listItem, selector: "setName:", argument: name as NSString) }
        try applyListAppearance(listItem, emoji: emoji, color: color)
        switch group {
        case .set(let groupID)?:
            guard !read.isGroup(handle.list) else {
                throw ReminderCLIError.invalidArgument("Groups cannot be nested in other groups.")
            }
            let target = try read.findList(id: groupID, store: store)
            guard read.isGroup(target.list), target.accountID == handle.accountID else {
                throw ReminderCLIError.invalidArgument("\(groupID) is not a group in the list's account.")
            }
            let sublists = try runtime.requireObject(
                try updateList(target.list, saveRequest), selector: "sublistContext")
            try runtime.sendVoidId(sublists, selector: "addListChangeItem:", argument: listItem)
        case .clear?:
            try runtime.sendVoidId(
                try updateAccount(handle.account, saveRequest), selector: "addListChangeItem:", argument: listItem)
        case nil: break
        }
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "list", id: id) { try read.fetchList(id: id) }
        if let name, result.title != name { throw unverified("list", id, "its name did not round-trip") }
        switch group {
        case .set(let groupID)? where result.groupID != groupID: throw unverified("list", id, "it is not in the group")
        case .clear? where result.groupID != nil: throw unverified("list", id, "it is still in a group")
        default: break
        }
        try verifyAppearance(emoji: emoji, color: color, list: result)
        return result
    }

    func verifyAppearance(emoji: String?, color: ReminderColor?, list: ReminderListSnapshot) throws {
        if let emoji, list.emoji != emoji { throw unverified("list", list.id, "its emoji did not round-trip") }
        if let color {
            guard let actual = list.colorHex, let decoded = try? ReminderColor(actual),
                decoded.hex == color.hex || decoded.hex == color.hex + "FF" || decoded.hex + "FF" == color.hex
            else { throw unverified("list", list.id, "its color did not round-trip") }
        }
    }

    /// Deletes a list with its reminders, or a group. A group's lists are moved out of it first
    /// (as "Ungroup" does in the app), so deleting a group never deletes lists.
    public func deleteList(id: String) throws {
        let store = try runtime.makeStore()
        let handle = try read.findList(id: id, store: store)
        if read.isGroup(handle.list) {
            let members = try read.fetchCatalog(taskLists: []).lists.filter { $0.groupID == id }
            for member in members { _ = try updateList(id: member.id, group: .clear) }
        }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let listItem = try updateList(handle.list, saveRequest)
        if listItem.responds(to: NSSelectorFromString("removeFromParentAllowingUndo")) {
            _ = runtime.sendObject(listItem, selector: "removeFromParentAllowingUndo")
        } else {
            try runtime.sendVoid(listItem, selector: "removeFromParent")
        }
        try runtime.saveSynchronously(saveRequest)
        try MutationVerification.absence(id: id, type: "list") { try read.fetchList(id: id) }
    }

    // MARK: - Sections

    public func createSection(listID: String, name: String) throws -> ReminderSectionSnapshot {
        try validateTitle(name, "Name")
        let store = try runtime.makeStore()
        let handle = try read.findList(id: listID, store: store)
        guard !read.isGroup(handle.list) else {
            throw ReminderCLIError.invalidArgument("Groups have no sections; pick a list.")
        }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let context = try runtime.requireObject(
            try updateList(handle.list, saveRequest), selector: "sectionsContextChangeItem")
        guard
            let sectionItem = try runtime.sendObjectOptional(
                saveRequest, "addListSectionWithDisplayName:toListSectionContextChangeItem:", name as NSString, context)
        else { throw ReminderCLIError.saveFailed("ReminderKit did not create the section.") }
        let id = runtime.objectIDString(from: sectionItem)
        try runtime.saveSynchronously(saveRequest)
        let section = try MutationVerification.readback(type: "section", id: id) {
            guard let section = try read.fetchSections(listID: listID).first(where: { $0.id == id }) else {
                throw ReminderCLIError.objectNotFound(type: "section", id: id)
            }
            return section
        }
        guard section.title == name else { throw unverified("section", id, "its name did not round-trip") }
        return section
    }

    public func renameSection(listID: String, id: String, name: String) throws -> ReminderSectionSnapshot {
        try validateTitle(name, "Name")
        let store = try runtime.makeStore()
        let section = try read.findSection(id: id, listID: listID, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        try runtime.sendVoidId(
            try updateSection(section, saveRequest), selector: "setDisplayName:", argument: name as NSString)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "section", id: id) {
            guard let section = try read.fetchSections(listID: listID).first(where: { $0.id == id }) else {
                throw ReminderCLIError.objectNotFound(type: "section", id: id)
            }
            return section
        }
        guard result.title == name else { throw unverified("section", id, "its name did not round-trip") }
        return result
    }

    /// Puts the list's sections in `orderedIDs` order (sections not named keep their relative
    /// order after the named ones).
    public func reorderSections(listID: String, orderedIDs: [String]) throws -> [ReminderSectionSnapshot] {
        let store = try runtime.makeStore()
        let handle = try read.findList(id: listID, store: store)
        let content = try read.listContent(handle, store: store)
        let current = content.sections.map(\.id)
        let target = orderedIDs + current.filter { !orderedIDs.contains($0) }
        let objects = try read.fetchSectionObjects(in: handle.list, store: store)
        let byID = Dictionary(objects.map { (runtime.objectIDString(from: $0), $0) }, uniquingKeysWith: { a, _ in a })
        let ordering = try target.map { id -> AnyObject in
            guard let object = byID[id] else { throw ReminderCLIError.objectNotFound(type: "section", id: id) }
            return try objectID(of: object)
        }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let context = try runtime.requireObject(
            try updateList(handle.list, saveRequest), selector: "sectionsContextChangeItem")
        try runtime.sendVoidBool(context, selector: "setShouldUpdateSectionsOrdering:", value: true)
        try runtime.sendVoidId(context, selector: "setUnsavedSectionIDsOrdering:", argument: ordering as NSArray)
        try runtime.saveSynchronously(saveRequest)
        let result = try MutationVerification.readback(type: "list", id: listID) {
            try read.fetchSections(listID: listID)
        }
        guard result.map(\.id) == target else {
            throw unverified("list", listID, "the section order did not round-trip")
        }
        return result
    }

    /// Deletes a section. Its reminders stay in the list, outside any section.
    public func deleteSection(listID: String, id: String) throws {
        let store = try runtime.makeStore()
        let section = try read.findSection(id: id, listID: listID, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        try runtime.sendVoid(try updateSection(section, saveRequest), selector: "removeFromList")
        try runtime.saveSynchronously(saveRequest)
        try MutationVerification.absence(id: id, type: "section") {
            try read.findSection(id: id, listID: listID, store: runtime.makeStore())
        }
    }
}
