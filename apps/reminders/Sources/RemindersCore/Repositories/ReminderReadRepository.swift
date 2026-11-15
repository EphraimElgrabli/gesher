import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Reads accounts, lists, groups, sections and reminders through `REMStore`. Every call opens a
/// fresh store so results always reflect the daemon's current state.
public final class ReminderReadRepository: @unchecked Sendable {
    let runtime: ReminderKitRuntime

    public init(runtime: ReminderKitRuntime) {
        self.runtime = runtime
    }

    /// Native handles of one list, for writes.
    struct ListHandle {
        let account: AnyObject
        let accountID: String
        let list: AnyObject
        let groupID: String?
        var id: String
    }

    // MARK: - Catalog

    /// Lists and groups of every account, plus sections and reminders of the lists in
    /// `taskLists` (all lists when nil; none when empty).
    public func fetchCatalog(taskLists: Set<String>? = nil) throws -> ReminderCatalog {
        let store = try runtime.makeStore()
        let accounts = try fetchAccounts(from: store)
        var lists: [ReminderListSnapshot] = []
        var sections: [ReminderSectionSnapshot] = []
        var tasks: [ReminderTaskSnapshot] = []
        var warnings: [String] = []
        for account in accounts {
            for handle in try listHandles(in: account, store: store) {
                let snapshot = listSnapshot(handle)
                lists.append(snapshot)
                guard !snapshot.isGroup, taskLists?.contains(snapshot.id) ?? true else { continue }
                let content = try listContent(handle, store: store)
                sections += content.sections
                tasks += content.tasks
                if let warning = content.warning { warnings.append(warning) }
            }
        }
        return ReminderCatalog(
            accounts: accounts.map(\.snapshot), lists: lists, sections: sections, tasks: tasks, warnings: warnings)
    }

    /// One reminder with its section, subtasks and order, read through its list.
    public func fetchTask(id: String) throws -> ReminderTaskSnapshot {
        let store = try runtime.makeStore()
        let reminder = try fetchReminderObject(id: id, store: store)
        guard let listObject = runtime.objectValue(from: reminder, selectors: ["list"]) else {
            throw ReminderCLIError.fetchFailed("The reminder's list is unavailable.")
        }
        let handle = try findList(id: runtime.objectIDString(from: listObject), store: store)
        let content = try listContent(handle, store: store)
        guard let task = content.tasks.first(where: { $0.id == id }) else {
            throw ReminderCLIError.objectNotFound(type: "task", id: id)
        }
        return task
    }

    public func fetchSections(listID: String) throws -> [ReminderSectionSnapshot] {
        let store = try runtime.makeStore()
        return try listContent(try findList(id: listID, store: store), store: store).sections
    }

    public func fetchList(id: String) throws -> ReminderListSnapshot {
        let store = try runtime.makeStore()
        return listSnapshot(try findList(id: id, store: store))
    }

    // MARK: - Accounts and lists

    func fetchAccounts(from store: AnyObject) throws -> [(snapshot: ReminderAccountSnapshot, object: AnyObject)] {
        try PermissionCoordinator().ensureAuthorized(service: .reminders)
        let selector = NSSelectorFromString("fetchAccountsWithError:")
        guard store.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: "REMStore", selector: "fetchAccountsWithError:")
        }
        var error: NSError?
        guard let accountObjects = runtime.objectArray(ObjCSendIdError(store, selector, &error)) else {
            if let error, error.domain == NSCocoaErrorDomain && (error.code == 4097 || error.code == 4099) {
                try PermissionCoordinator().ensureAuthorized(service: .reminders)
            }
            throw ReminderCLIError.fetchFailed(
                error?.localizedDescription ?? "REMStore.fetchAccountsWithError returned no accounts.")
        }
        let defaultSelector = NSSelectorFromString("fetchDefaultAccountWithError:")
        var defaultError: NSError?
        let defaultAccount =
            store.responds(to: defaultSelector)
            ? ObjCSendIdError(store, defaultSelector, &defaultError) as AnyObject? : nil
        let defaultID = defaultError == nil ? defaultAccount.map { runtime.objectIDString(from: $0) } : nil
        return accountObjects.map { account in
            let id = runtime.objectIDString(from: account)
            return (
                ReminderAccountSnapshot(
                    id: id,
                    title: runtime.stringValue(from: account, selectors: ["displayName", "name"]) ?? "Reminders",
                    isDefault: defaultID.map { id == $0 }),
                account
            )
        }
    }

    func defaultListID(store: AnyObject) -> String? {
        let selector = NSSelectorFromString("fetchDefaultListWithError:")
        guard store.responds(to: selector) else { return nil }
        var error: NSError?
        guard let list = ObjCSendIdError(store, selector, &error) as AnyObject?, error == nil else { return nil }
        return runtime.objectIDString(from: list)
    }

    /// The native default list ("New reminders go to..."), if ReminderKit reports one.
    public func fetchDefaultListID() throws -> String? {
        defaultListID(store: try runtime.makeStore())
    }

    /// Lists and groups of an account in sidebar order: each group is followed by its lists.
    func listHandles(in account: (snapshot: ReminderAccountSnapshot, object: AnyObject), store: AnyObject) throws
        -> [ListHandle]
    {
        let topLevel = try objects(account.object, "fetchListsWithError:")
        var handles: [ListHandle] = []
        var seen = Set<String>()
        func add(_ list: AnyObject, group: String?) {
            let id = runtime.objectIDString(from: list)
            guard seen.insert(id).inserted else { return }
            handles.append(
                ListHandle(account: account.object, accountID: account.snapshot.id, list: list, groupID: group, id: id))
        }
        for list in topLevel {
            add(list, group: nil)
            guard isGroup(list), let context = runtime.objectValue(from: list, selectors: ["sublistContext"]) else {
                continue
            }
            let groupID = runtime.objectIDString(from: list)
            for sublist in try objects(context, "fetchListsWithError:") { add(sublist, group: groupID) }
        }
        // Lists the ordered fetch did not return (e.g. a group whose context is unavailable).
        if account.object.responds(to: NSSelectorFromString("fetchListsAndSublistsWithError:")) {
            for list in try objects(account.object, "fetchListsAndSublistsWithError:") {
                let parent = runtime.objectValue(from: list, selectors: ["parentList"])
                add(list, group: parent.map { runtime.objectIDString(from: $0) })
            }
        }
        return handles
    }

    func isGroup(_ list: AnyObject) -> Bool {
        let storage = runtime.objectValue(from: list, selectors: ["storage"]) ?? list
        return runtime.boolValue(from: storage, selectors: ["isGroup"]) ?? false
    }

    func findList(id: String, store: AnyObject) throws -> ListHandle {
        for account in try fetchAccounts(from: store) {
            if let handle = try listHandles(in: account, store: store).first(where: { $0.id == id }) {
                return handle
            }
        }
        throw ReminderCLIError.objectNotFound(type: "list", id: id)
    }

    private func objects(_ target: AnyObject, _ selectorName: String) throws -> [AnyObject] {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: type(of: target)), selector: selectorName)
        }
        var error: NSError?
        let result = ObjCSendIdError(target, selector, &error)
        if let error { throw ReminderCLIError.fetchFailed(error.localizedDescription) }
        guard let array = runtime.objectArray(result) else {
            throw ReminderCLIError.fetchFailed("\(selectorName) returned no collection.")
        }
        return array
    }

    func listSnapshot(_ handle: ListHandle) -> ReminderListSnapshot {
        let list = handle.list
        let storage = runtime.objectValue(from: list, selectors: ["storage"]) ?? list
        var sharees: [ReminderShareeSnapshot] = []
        var owner: String?
        let shared = runtime.boolValue(from: list, selectors: ["isShared"]) ?? false
        if shared, let context = runtime.objectValue(from: list, selectors: ["shareeContext"]) {
            if let values = runtime.objectValue(from: context, selectors: ["shareesExcludingOwner", "sharees"]) {
                sharees = (runtime.objectArray(values) ?? []).map(shareeSnapshot)
            }
            if let sharedOwner = runtime.objectValue(from: context, selectors: ["sharedOwner"]) {
                owner = shareeSnapshot(sharedOwner).name
            }
        }
        return ReminderListSnapshot(
            id: handle.id,
            title: runtime.stringValue(from: storage, selectors: ["name", "displayName"]) ?? "Untitled List",
            accountID: handle.accountID, isGroup: isGroup(list), groupID: handle.groupID,
            emoji: runtime.listBadgeValue(from: list),
            colorHex: runtime.objectValue(from: storage, selectors: ["color"]).flatMap {
                runtime.stringValue(from: $0, selectors: ["hexString", "daHexString"])
            },
            isShared: shared, isSharedToMe: runtime.boolValue(from: list, selectors: ["isSharedToMe"]) ?? false,
            sharedOwner: owner ?? runtime.stringValue(from: storage, selectors: ["sharedOwnerName"]),
            sharees: sharees, isPinned: runtime.boolValue(from: list, selectors: ["isPinned"]) ?? false)
    }

    private func shareeSnapshot(_ sharee: AnyObject) -> ReminderShareeSnapshot {
        let status = runtime.intValue(from: sharee, selectors: ["status"]) ?? -1
        let statusName =
            switch status {
            case 0: "unknown"
            case 1: "pending"
            case 2: "accepted"
            case 3: "declined"
            default: "status-\(status)"
            }
        return ReminderShareeSnapshot(
            id: runtime.objectIDString(from: sharee),
            name: runtime.stringValue(from: sharee, selectors: ["formattedName", "displayName", "shortName"]),
            address: runtime.stringValue(from: sharee, selectors: ["address"]), status: statusName)
    }

    // MARK: - Sections and reminders of one list

    struct ListContent {
        var sections: [ReminderSectionSnapshot]
        var tasks: [ReminderTaskSnapshot]
        var membership: [String: String]
        var warning: String?
    }

    func listContent(_ handle: ListHandle, store: AnyObject) throws -> ListContent {
        let listID = handle.id
        let sectionObjects = try fetchSectionObjects(in: handle.list, store: store)
        var view: SectionedDataView?
        var warning: String?
        do {
            view = try sectionedDataView(
                list: handle.list, account: handle.account, store: store, includeCompleted: true)
        } catch {
            warning = "Sections of list \(listID) could not be read: \(error.localizedDescription)"
        }
        var sections = sectionObjects.map { section in
            ReminderSectionSnapshot(
                id: runtime.objectIDString(from: section), listID: listID,
                title: runtime.stringValue(from: section, selectors: ["displayName", "name"]) ?? "Untitled Section")
        }
        if let order = view?.sectionOrder, !order.isEmpty {
            let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            sections = sections.enumerated().sorted {
                (rank[$0.element.id] ?? order.count + $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset)
            }.map(\.element)
        }

        let reminders = try fetchReminderObjects(in: handle.list, store: store)
        var tasks = try reminders.map { try makeTaskSnapshot($0, listID: listID) }
        let membership = view?.membershipByReminderID ?? [:]
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Subtasks display under their parent, so they share its section.
        for index in tasks.indices {
            let task = tasks[index]
            let sectionOwner = task.parentID.flatMap { byID[$0] }?.id ?? task.id
            tasks[index].sectionID = membership[sectionOwner].flatMap { id in
                sections.contains { $0.id == id } ? id : nil
            }
        }

        // Order: the list's manual order (the app's default sort) within each section, then each
        // parent's subtasks. The data view is configured by creation date and only fills gaps.
        let manual = runtime.objectIDStringArray(from: handle.list, selectors: ["reminderIDsOrdering"])
        let displayOrder = manual + (view?.orderedReminderIDs ?? [])
        let rank = Dictionary(displayOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sectionRank = Dictionary(sections.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func key(_ task: ReminderTaskSnapshot) -> (Int, Int, Double) {
            (
                task.sectionID.flatMap { sectionRank[$0] }.map { $0 + 1 } ?? 0, rank[task.id] ?? Int.max,
                task.creationDate?.timeIntervalSince1970 ?? 0
            )
        }
        let children = Dictionary(grouping: tasks.filter { $0.parentID.flatMap { byID[$0] } != nil }) { $0.parentID! }
        let topLevel = tasks.filter { $0.parentID.flatMap { byID[$0] } == nil }.sorted { key($0) < key($1) }
        var ordered: [ReminderTaskSnapshot] = []
        for var task in topLevel {
            let subtasks = (children[task.id] ?? []).sorted {
                (rank[$0.id] ?? Int.max, $0.creationDate?.timeIntervalSince1970 ?? 0)
                    < (rank[$1.id] ?? Int.max, $1.creationDate?.timeIntervalSince1970 ?? 0)
            }
            task.subtaskIDs = subtasks.map(\.id)
            task.order = ordered.count
            ordered.append(task)
            for var subtask in subtasks {
                subtask.order = ordered.count
                ordered.append(subtask)
            }
        }
        return ListContent(sections: sections, tasks: ordered, membership: membership, warning: warning)
    }

    func fetchReminderObjects(in list: AnyObject, store: AnyObject) throws -> [AnyObject] {
        let reminders = try objects(list, "fetchRemindersAndSubtasksWithError:")
        // Early alerts are stored separately; refetch the reminders that have some.
        let pending = reminders.filter { reminder in
            let storage = runtime.objectValue(from: reminder, selectors: ["storage"]) ?? reminder
            return runtime.boolValue(from: storage, selectors: ["hasUnfetchedDueDateDeltaAlerts"]) == true
        }
        guard !pending.isEmpty, let options = runtime.fetchOptionsWithEarlyAlerts() else { return reminders }
        let ids = pending.compactMap { runtime.objectValue(from: $0, selectors: ["remObjectID", "objectID"]) }
        let fetched =
            try runtime.sendObjectError(
                store, "fetchRemindersWithObjectIDs:fetchOptions:error:", ids as NSArray, options
            )
            .flatMap(runtime.objectArray) ?? []
        let byID = Dictionary(fetched.map { (runtime.objectIDString(from: $0), $0) }, uniquingKeysWith: { a, _ in a })
        return reminders.map { byID[runtime.objectIDString(from: $0)] ?? $0 }
    }

    func fetchSectionObjects(in list: AnyObject, store: AnyObject) throws -> [AnyObject] {
        let selector = NSSelectorFromString("fetchListSectionsWithListObjectID:error:")
        guard store.responds(to: selector),
            let listObjectID = runtime.objectValue(from: list, selectors: ["remObjectID", "objectID"])
        else {
            throw ReminderCLIError.missingSelector(
                className: "REMStore", selector: "fetchListSectionsWithListObjectID:error:")
        }
        var error: NSError?
        let result = ObjCSendIdIdError(store, selector, listObjectID, &error)
        if let error { throw ReminderCLIError.fetchFailed(error.localizedDescription) }
        guard let sections = runtime.objectArray(result) else {
            throw ReminderCLIError.fetchFailed("Native sections collection is missing or malformed.")
        }
        return sections
    }

    func findSection(id: String, listID: String, store: AnyObject) throws -> AnyObject {
        let handle = try findList(id: listID, store: store)
        guard
            let section = try fetchSectionObjects(in: handle.list, store: store).first(where: {
                runtime.objectIDString(from: $0) == id
            })
        else { throw ReminderCLIError.objectNotFound(type: "section", id: id) }
        return section
    }

    func fetchReminderObject(id: String, store: AnyObject) throws -> AnyObject {
        guard id.hasPrefix("REMCDReminder:"), let objectID = makeObjectID(fromStableID: id) else {
            throw ReminderCLIError.invalidArgument("A task ID must look like REMCDReminder:<UUID>.")
        }
        if let options = runtime.fetchOptionsWithEarlyAlerts(),
            store.responds(to: NSSelectorFromString("fetchReminderWithObjectID:fetchOptions:error:")),
            let reminder = try? runtime.sendObjectError(
                store, "fetchReminderWithObjectID:fetchOptions:error:", objectID, options)
        {
            return reminder
        }
        let selector = NSSelectorFromString("fetchReminderWithObjectID:error:")
        guard store.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: "REMStore", selector: "fetchReminderWithObjectID:error:")
        }
        var error: NSError?
        guard let reminder = ObjCSendIdIdError(store, selector, objectID, &error) as AnyObject? else {
            if let error, !(error.domain == "com.apple.reminderkit" && error.code == -3000) {
                throw ReminderCLIError.fetchFailed(error.localizedDescription)
            }
            throw ReminderCLIError.objectNotFound(type: "task", id: id)
        }
        return reminder
    }

    // MARK: - Reminder fields

    func makeTaskSnapshot(_ reminder: AnyObject, listID: String) throws -> ReminderTaskSnapshot {
        let storage = runtime.objectValue(from: reminder, selectors: ["storage"]) ?? reminder
        guard let completed = runtime.boolValue(from: storage, selectors: ["isCompleted", "completed"]),
            let priority = runtime.intValue(from: storage, selectors: ["priority"])
        else {
            throw ReminderCLIError.fetchFailed(
                "Reminder response is missing completion or priority; no defaults were inferred.")
        }
        let tags =
            (runtime.objectValue(from: storage, selectors: ["hashtags"]).flatMap(runtime.objectArray) ?? [])
            .compactMap { runtime.stringValue(from: $0, selectors: ["name"]) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let attachments = attachmentSnapshots(storage)
        let url =
            attachments.first(where: { $0.kind == "url" })?.url
            ?? (runtime.objectValue(from: storage, selectors: ["icsUrl"]) as? URL)?.absoluteString
        let assignment = runtime.objectValue(from: storage, selectors: ["currentAssignment"])
        return ReminderTaskSnapshot(
            id: runtime.objectIDString(from: reminder), listID: listID,
            title: runtime.stringValue(from: storage, selectors: ["titleAsString"])
                ?? runtime.stringValue(from: reminder, selectors: ["titleAsString", "title"]) ?? "",
            notes: runtime.stringValue(from: storage, selectors: ["notesAsString"]),
            isCompleted: completed,
            completionDate: runtime.objectValue(from: storage, selectors: ["completionDate"]) as? Date,
            creationDate: runtime.objectValue(from: storage, selectors: ["creationDate"]) as? Date,
            modifiedDate: runtime.objectValue(from: storage, selectors: ["lastModifiedDate"]) as? Date,
            priority: priority,
            isFlagged: (runtime.intValue(from: storage, selectors: ["flagged"]) ?? 0) != 0,
            due: reminderDate(runtime.objectValue(from: storage, selectors: ["dueDateComponents"])),
            start: startDate(runtime.objectValue(from: storage, selectors: ["startDateComponents"])),
            url: url,
            alarms: try alarmSnapshots(storage),
            earlyAlert: earlyAlert(reminder),
            tags: tags,
            parentID: runtime.objectValue(from: storage, selectors: ["parentReminderID"]).map {
                runtime.stableObjectIDString(from: $0)
            },
            recurrence: recurrence(storage),
            attachments: attachments.filter { $0.kind != "url" || $0.url != url },
            assigneeID: assignment.flatMap { runtime.objectValue(from: $0, selectors: ["assigneeID"]) }.map {
                runtime.stableObjectIDString(from: $0)
            },
            isUrgent: runtime.boolValue(from: storage, selectors: ["isUrgentStateEnabledForCurrentUser"]) ?? false)
    }

    /// Native date components to a date: no hour means date-only; a missing zone means floating
    /// (interpreted in the user's zone).
    func reminderDate(_ value: AnyObject?) -> ReminderDate? {
        if let date = value as? Date { return ReminderDate(date: date, hasTime: true, timeZone: nil) }
        guard let components = value as? DateComponents ?? (value as? NSDateComponents).map({ $0 as DateComponents })
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? .current
        var dateOnly = DateComponents()
        dateOnly.year = components.year
        dateOnly.month = components.month
        dateOnly.day = components.day
        guard components.hour != nil else {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = .current
            return local.date(from: dateOnly).map { ReminderDate(date: $0, hasTime: false, timeZone: nil) }
        }
        var timed = dateOnly
        timed.hour = components.hour
        timed.minute = components.minute ?? 0
        timed.second = components.second ?? 0
        return calendar.date(from: timed).map {
            ReminderDate(date: $0, hasTime: true, timeZone: components.timeZone?.identifier)
        }
    }

    /// Start dates are floating; ReminderKit stores a day-only start as midnight, read back as a day.
    func startDate(_ value: AnyObject?) -> ReminderDate? {
        guard let date = reminderDate(value) else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date.date)
        if date.hasTime, date.timeZone == nil, parts.hour == 0, parts.minute == 0, parts.second == 0 {
            return ReminderDate(date: date.date, hasTime: false, timeZone: nil)
        }
        return date
    }

    func alarmSnapshots(_ storage: AnyObject) throws -> [ReminderAlarmSnapshot] {
        guard let value = runtime.objectValue(from: storage, selectors: ["alarms"]) else { return [] }
        guard let alarms = runtime.objectArray(value) else {
            throw ReminderCLIError.fetchFailed("Native alarms collection is malformed.")
        }
        return try alarms.compactMap { alarm -> ReminderAlarmSnapshot? in
            if runtime.boolValue(from: alarm, selectors: ["isSnooze"]) == true { return nil }
            guard let trigger = runtime.objectValue(from: alarm, selectors: ["trigger"]) else {
                throw ReminderCLIError.fetchFailed("Native alarm trigger is unavailable.")
            }
            let kind = String(describing: type(of: trigger))
            if kind.contains("LocationTrigger") {
                guard let location = runtime.objectValue(from: trigger, selectors: ["structuredLocation"]),
                    let latitude = runtime.doubleValue(from: location, selectors: ["latitude"]),
                    let longitude = runtime.doubleValue(from: location, selectors: ["longitude"]),
                    let radius = runtime.doubleValue(from: location, selectors: ["radius"]),
                    let proximity = runtime.intValue(from: trigger, selectors: ["proximity"])
                else { throw ReminderCLIError.fetchFailed("Native location alarm is incomplete.") }
                return .location(
                    title: runtime.stringValue(from: location, selectors: ["title", "displayName"]),
                    address: runtime.stringValue(from: location, selectors: ["address"]), latitude: latitude,
                    longitude: longitude, radius: radius,
                    proximity: ReminderLocationProximity(reminderKitValue: proximity)?.rawValue ?? "unknown")
            }
            if kind.contains("DateTrigger"), !kind.contains("DueDateDelta") {
                return reminderDate(runtime.objectValue(from: trigger, selectors: ["dateComponents"])).map {
                    .date($0)
                }
            }
            if kind.contains("TimeIntervalTrigger"),
                let seconds = runtime.doubleValue(from: trigger, selectors: ["timeInterval"])
            {
                return .relative(seconds: seconds)
            }
            return nil
        }
    }

    func earlyAlert(_ reminder: AnyObject) -> ReminderEarlyAlert? {
        guard let context = runtime.objectValue(from: reminder, selectors: ["dueDateDeltaAlertContext"]),
            let alerts = runtime.objectValue(from: context, selectors: ["dueDateDeltaAlerts"]).flatMap(
                runtime.objectArray),
            let delta = alerts.lazy.compactMap({ self.runtime.objectValue(from: $0, selectors: ["dueDateDelta"]) })
                .first,
            let unit = runtime.intValue(from: delta, selectors: ["unit"]).flatMap(ReminderEarlyAlert.Unit.init),
            let count = runtime.intValue(from: delta, selectors: ["count"]), count != 0
        else { return nil }
        return ReminderEarlyAlert(unit: unit, count: abs(count))
    }

    func recurrence(_ storage: AnyObject) -> ReminderRecurrenceSnapshot? {
        guard
            let rule = runtime.objectValue(from: storage, selectors: ["recurrenceRules"]).flatMap(runtime.objectArray)?
                .first,
            let code = runtime.intValue(from: rule, selectors: ["frequency"])
        else { return nil }
        let weekdays =
            (runtime.objectValue(from: rule, selectors: ["daysOfTheWeek"]).flatMap(runtime.objectArray) ?? [])
            .compactMap { runtime.intValue(from: $0, selectors: ["dayOfTheWeek"]) }
        let days = (runtime.objectValue(from: rule, selectors: ["daysOfTheMonth"]).flatMap(runtime.objectArray) ?? [])
            .compactMap { ($0 as? NSNumber)?.intValue }
        var endDate: Date?
        var count: Int?
        if let end = runtime.objectValue(from: rule, selectors: ["recurrenceEnd"]) {
            if runtime.boolValue(from: end, selectors: ["usesEndDate"]) == true {
                endDate = runtime.objectValue(from: end, selectors: ["endDate"]) as? Date
            } else if let occurrences = runtime.intValue(from: end, selectors: ["occurrenceCount"]), occurrences > 0 {
                count = occurrences
            }
        }
        return ReminderRecurrenceSnapshot(
            frequency: RecurrenceMutation.Frequency(code: code)?.rawValue ?? "custom",
            interval: max(1, runtime.intValue(from: rule, selectors: ["interval"]) ?? 1), weekdays: weekdays,
            daysOfMonth: days, endDate: endDate, count: count)
    }

    func attachmentSnapshots(_ storage: AnyObject) -> [ReminderAttachmentSnapshot] {
        (runtime.objectValue(from: storage, selectors: ["attachments"]).flatMap(runtime.objectArray) ?? []).map {
            attachment in
            let kind = String(describing: type(of: attachment))
            let isURL = kind.contains("URL")
            let url = runtime.objectValue(from: attachment, selectors: isURL ? ["url"] : ["fileURL"]) as? URL
            return ReminderAttachmentSnapshot(
                id: runtime.objectIDString(from: attachment),
                kind: isURL ? "url" : kind.contains("Image") ? "image" : "file",
                url: isURL ? url?.absoluteString : nil,
                uti: runtime.rawStringValue(from: attachment, selectors: ["uti"]),
                width: kind.contains("Image") ? runtime.intValue(from: attachment, selectors: ["width"]) : nil,
                height: kind.contains("Image") ? runtime.intValue(from: attachment, selectors: ["height"]) : nil,
                size: isURL ? nil : runtime.intValue(from: attachment, selectors: ["fileSize"]),
                fileURL: isURL ? nil : url)
        }
    }
}
