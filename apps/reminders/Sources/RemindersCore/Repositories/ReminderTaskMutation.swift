import GesherPlatform
import Foundation
import ObjCRuntimeSupport

extension ReminderWriteRepository {
    /// Result of completing a recurring reminder: ReminderKit keeps the series on the original
    /// id (advanced to the next occurrence) and saves a completed copy.
    public struct TaskWrite: Sendable {
        public let task: ReminderTaskSnapshot
        public let advancedRecurrence: Bool
    }

    // MARK: - Create / update / delete

    public func createTask(listID: String, title: String, mutation: TaskMutation) throws -> ReminderTaskSnapshot {
        try validateTitle(title)
        try validate(mutation)
        let store = try runtime.makeStore()
        let handle = try read.findList(id: listID, store: store)
        guard !read.isGroup(handle.list) else {
            throw ReminderCLIError.invalidArgument("Groups hold lists, not reminders; pick a list.")
        }
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let listItem = try updateList(handle.list, saveRequest)
        let item: AnyObject?
        var parentItem: AnyObject?
        if case .set(let parentID)? = mutation.parent {
            let parent = try read.fetchReminderObject(id: parentID, store: store)
            try requireSameList(parent, listID: listID, what: "parent task")
            parentItem = try updateReminder(parent, saveRequest)
            let subtasks = try runtime.requireObject(parentItem!, selector: "subtaskContext")
            item = try runtime.sendObjectOptional(
                saveRequest, "addReminderWithTitle:toReminderSubtaskContextChangeItem:", title as NSString, subtasks)
        } else {
            item = try runtime.sendObjectOptional(
                saveRequest, "addReminderWithTitle:toListChangeItem:", title as NSString, listItem)
        }
        guard let item else { throw ReminderCLIError.saveFailed("ReminderKit did not create the reminder.") }
        try applyFields(mutation, to: item, existing: nil)
        if case .set(let sectionID)? = mutation.section {
            let content = try read.listContent(handle, store: store)
            try setSection(
                sectionID, for: [try uuid(of: item)], handle: handle, content: content, listItem: listItem,
                store: store)
        }
        if let position = mutation.position {
            try place(
                item, position, listItem: listItem, parentItem: parentItem, saveRequest: saveRequest, store: store)
        }
        let id = runtime.objectIDString(from: item)
        try runtime.saveSynchronously(saveRequest)
        let task = try MutationVerification.readback(type: "task", id: id) { try read.fetchTask(id: id) }
        try verify(mutation, title: title, before: nil, after: task, listID: listID)
        return task
    }

    public func updateTask(id: String, mutation: TaskMutation) throws -> TaskWrite {
        guard mutation.hasChanges else {
            throw ReminderCLIError.invalidArgument("Provide at least one field to change. No write was started.")
        }
        try validate(mutation)
        let store = try runtime.makeStore()
        let reminder = try read.fetchReminderObject(id: id, store: store)
        let before = try read.fetchTask(id: id)
        let sourceHandle = try read.findList(id: before.listID, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try updateReminder(reminder, saveRequest)
        try applyFields(mutation, to: item, existing: reminder)

        var handle = sourceHandle
        var listItem = try updateList(sourceHandle.list, saveRequest)
        if let target = mutation.listID, target != before.listID {
            let targetHandle = try read.findList(id: target, store: store)
            guard !read.isGroup(targetHandle.list) else {
                throw ReminderCLIError.invalidArgument("Groups hold lists, not reminders; pick a list.")
            }
            guard targetHandle.accountID == sourceHandle.accountID else {
                throw ReminderCLIError.invalidArgument(
                    "Moving reminders between accounts is not supported; pick a list in the same account.")
            }
            handle = targetHandle
            listItem = try updateList(targetHandle.list, saveRequest)
            if mutation.parent == nil {
                // A subtask moved alone becomes a top-level reminder of the target list.
                try runtime.sendVoidId(listItem, selector: "addReminderChangeItem:", argument: item)
            }
            // Subtasks must stay in their parent's list: move them along, under the moved parent.
            if !before.subtaskIDs.isEmpty {
                let context = try runtime.requireObject(reminder, selector: "subtaskContext")
                let selector = NSSelectorFromString("fetchRemindersForMovingWithError:")
                guard context.responds(to: selector) else {
                    throw ReminderCLIError.missingSelector(
                        className: "REMReminderSubtaskContext", selector: "fetchRemindersForMovingWithError:")
                }
                var error: NSError?
                let fetched = ObjCSendIdError(context, selector, &error)
                if let error { throw ReminderCLIError.fetchFailed(error.localizedDescription) }
                let subtasks = runtime.objectArray(fetched) ?? []
                let movedContext = try runtime.requireObject(item, selector: "subtaskContext")
                for subtask in subtasks {
                    try runtime.sendVoidId(
                        movedContext, selector: "addReminderChangeItem:",
                        argument: try updateReminder(subtask, saveRequest))
                }
            }
        }
        var parentItem: AnyObject?
        switch mutation.parent {
        case .set(let parentID)?:
            guard parentID != id else { throw ReminderCLIError.invalidArgument("A task cannot be its own parent.") }
            guard before.subtaskIDs.isEmpty else {
                throw ReminderCLIError.invalidArgument(
                    "Reminders supports one level of subtasks; this task has subtasks of its own.")
            }
            let parent = try read.fetchReminderObject(id: parentID, store: store)
            try requireSameList(parent, listID: handle.id, what: "parent task")
            parentItem = try updateReminder(parent, saveRequest)
            let subtasks = try runtime.requireObject(parentItem!, selector: "subtaskContext")
            try runtime.sendVoidId(subtasks, selector: "addReminderChangeItem:", argument: item)
        case .clear?:
            try runtime.sendVoidId(listItem, selector: "addReminderChangeItem:", argument: item)
        case nil:
            if let parentID = before.parentID, mutation.listID == nil || mutation.listID == before.listID,
                mutation.position != nil
            {
                parentItem = try updateReminder(try read.fetchReminderObject(id: parentID, store: store), saveRequest)
            }
        }
        if let section = mutation.section {
            let content = try read.listContent(handle, store: store)
            let members = [try uuid(of: item)] + (try before.subtaskIDs.map { try uuidOrThrow($0) })
            switch section {
            case .set(let sectionID):
                try setSection(
                    sectionID, for: members, handle: handle, content: content, listItem: listItem, store: store)
            case .clear:
                try setSection(nil, for: members, handle: handle, content: content, listItem: listItem, store: store)
            }
        }
        if let position = mutation.position {
            try place(
                item, position, listItem: listItem, parentItem: parentItem, saveRequest: saveRequest, store: store)
        }
        try runtime.saveSynchronously(saveRequest)
        let after = try MutationVerification.readback(type: "task", id: id) { try read.fetchTask(id: id) }
        let advanced = mutation.completed == true && before.recurrence != nil && !after.isCompleted
        try verify(mutation, title: nil, before: before, after: after, listID: mutation.listID, advanced: advanced)
        return TaskWrite(task: after, advancedRecurrence: advanced)
    }

    /// Deletes a reminder (and its subtasks, as the app does).
    public func deleteTask(id: String) throws {
        let store = try runtime.makeStore()
        let reminder = try read.fetchReminderObject(id: id, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try updateReminder(reminder, saveRequest)
        if item.responds(to: NSSelectorFromString("removeFromListAllowingUndo")) {
            _ = runtime.sendObject(item, selector: "removeFromListAllowingUndo")
        } else {
            try runtime.sendVoid(item, selector: "removeFromList")
        }
        try runtime.saveSynchronously(saveRequest)
        try MutationVerification.absence(id: id, type: "task") {
            try read.fetchReminderObject(id: id, store: runtime.makeStore())
        }
    }

    // MARK: - Helpers

    private func uuidOrThrow(_ id: String) throws -> NSUUID {
        guard let value = Self.uuid(fromStableID: id) else { throw ReminderCLIError.invalidArgument("Bad id \(id).") }
        return value
    }

    private func requireSameList(_ reminder: AnyObject, listID: String, what: String) throws {
        let list = runtime.objectValue(from: reminder, selectors: ["list"]).map { runtime.objectIDString(from: $0) }
        guard list == listID else {
            throw ReminderCLIError.invalidArgument("The \(what) must be in the same list as the task.")
        }
        let storage = runtime.objectValue(from: reminder, selectors: ["storage"]) ?? reminder
        if runtime.objectValue(from: storage, selectors: ["parentReminderID"]) != nil {
            throw ReminderCLIError.invalidArgument(
                "The \(what) is itself a subtask; Reminders supports one level of subtasks.")
        }
    }

    private func setSection(
        _ sectionID: String?, for members: [NSUUID], handle: ReminderReadRepository.ListHandle,
        content: ReminderReadRepository.ListContent, listItem: AnyObject, store: AnyObject
    ) throws {
        if content.warning != nil {
            throw ReminderCLIError.fetchFailed(
                "Section membership of this list could not be read, so it cannot be changed safely.")
        }
        let objects = try read.fetchSectionObjects(in: handle.list, store: store)
        let byID = Dictionary(objects.map { (runtime.objectIDString(from: $0), $0) }, uniquingKeysWith: { a, _ in a })
        var group: NSUUID?
        if let sectionID {
            guard let section = byID[sectionID] else {
                throw ReminderCLIError.objectNotFound(type: "section", id: sectionID)
            }
            group = try uuid(of: section)
        }
        let order = try content.sections.compactMap { byID[$0.id] }.map { try objectID(of: $0) }
        try writeMembership(
            listChangeItem: listItem, current: content.membership, sectionOrder: order,
            changes: members.map { ($0, group) })
    }

    private func place(
        _ item: AnyObject, _ position: TaskPosition, listItem: AnyObject, parentItem: AnyObject?,
        saveRequest: AnyObject, store: AnyObject
    ) throws {
        let container = try parentItem.map { try runtime.requireObject($0, selector: "subtaskContext") } ?? listItem
        let itemID = runtime.objectIDString(from: item)
        func anchor(_ id: String) throws -> AnyObject {
            try updateReminder(try read.fetchReminderObject(id: id, store: store), saveRequest)
        }
        let siblings: [String]
        if let parentItem {
            siblings = try read.fetchTask(id: runtime.objectIDString(from: parentItem)).subtaskIDs
        } else {
            // The list's manual order, not display order: sections group the display, and the
            // manual order decides the position within each section.
            let handle = try read.findList(id: runtime.objectIDString(from: listItem), store: store)
            let tasks = try read.listContent(handle, store: store).tasks
            let open = Set(tasks.filter { $0.parentID == nil && !$0.isCompleted }.map(\.id))
            siblings = runtime.objectIDStringArray(from: handle.list, selectors: ["reminderIDsOrdering"])
                .filter(open.contains)
        }
        let others = siblings.filter { $0 != itemID }
        switch position {
        case .top:
            guard let first = others.first else { return }
            try runtime.sendVoidTwo(
                container, "insertReminderChangeItem:beforeReminderChangeItem:", item, try anchor(first))
        case .bottom:
            guard let last = others.last else { return }
            try runtime.sendVoidTwo(
                container, "insertReminderChangeItem:afterReminderChangeItem:", item, try anchor(last))
        case .before(let other):
            try runtime.sendVoidTwo(
                container, "insertReminderChangeItem:beforeReminderChangeItem:", item, try anchor(other))
        case .after(let other):
            try runtime.sendVoidTwo(
                container, "insertReminderChangeItem:afterReminderChangeItem:", item, try anchor(other))
        }
    }

    func validate(_ mutation: TaskMutation) throws {
        if let title = mutation.title { try validateTitle(title) }
        if let priority = mutation.priority, !(0...9).contains(priority) {
            throw ReminderCLIError.invalidArgument("Priority must be between 0 and 9.")
        }
        if case .set(let url)? = mutation.url, URL(string: url)?.scheme == nil {
            throw ReminderCLIError.invalidArgument("URL must be absolute and include its scheme, e.g. https://…")
        }
        for tag in (mutation.tags ?? []) + mutation.addTags where TaskMutation.normalizeTag(tag).isEmpty {
            throw ReminderCLIError.invalidArgument("Tag names cannot be empty.")
        }
    }

    // MARK: - Field application

    /// Native due-date components: date-only values carry no time and no zone (all-day); timed
    /// values carry the user's zone, as the Reminders app writes them.
    static func components(_ value: ReminderDate, zone: TimeZone = .current) -> NSDateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: value.date)
        let components = NSDateComponents()
        components.year = parts.year ?? 0
        components.month = parts.month ?? 0
        components.day = parts.day ?? 0
        if value.hasTime {
            components.hour = parts.hour ?? 0
            components.minute = parts.minute ?? 0
            components.second = parts.second ?? 0
            components.timeZone = zone
        }
        return components
    }

    func applyFields(_ mutation: TaskMutation, to item: AnyObject, existing reminder: AnyObject?) throws {
        if let title = mutation.title {
            try runtime.sendVoidId(item, selector: "setTitleAsString:", argument: title as NSString)
        }
        switch mutation.notes {
        case .set(let notes)?: try runtime.sendVoidId(item, selector: "setNotesAsString:", argument: notes as NSString)
        case .clear?: try runtime.sendVoidOptional(item, "setNotesAsString:", nil)
        case nil: break
        }
        if let url = mutation.url {
            let attachments = try runtime.requireObject(item, selector: "attachmentContext")
            switch url {
            case .set(let text):
                guard let parsed = URL(string: text) else { throw ReminderCLIError.invalidArgument("Invalid URL.") }
                guard
                    try runtime.sendObjectOptional(attachments, "setURLAttachmentWithURL:", parsed as NSURL, nil)
                        != nil
                else { throw ReminderCLIError.saveFailed("ReminderKit rejected the URL.") }
            case .clear:
                try runtime.sendVoid(attachments, selector: "removeURLAttachments")
            }
            let storage = runtime.objectValue(from: item, selectors: ["storage"]) ?? item
            if runtime.objectValue(from: storage, selectors: ["icsUrl"]) != nil {
                try runtime.sendVoidOptional(item, "setIcsUrl:", nil)
            }
        }
        switch mutation.due {
        case .set(let due)?: try runtime.sendVoidOptional(item, "setDueDateComponents:", Self.components(due))
        case .clear?: try runtime.sendVoidOptional(item, "setDueDateComponents:", nil)
        case nil: break
        }
        switch mutation.start {
        case .set(let start)?:
            // ReminderKit converts zoned start components to GMT and drops the zone; floating local
            // components (as the app's start dates are) round-trip unchanged.
            let components = Self.components(start)
            components.timeZone = nil
            try runtime.sendVoidOptional(item, "setStartDateComponents:", components)
        case .clear?: try runtime.sendVoidOptional(item, "setStartDateComponents:", nil)
        case nil: break
        }
        if let priority = mutation.priority {
            try runtime.sendVoidInteger(item, selector: "setPriority:", value: priority)
        }
        if let flagged = mutation.flagged {
            let target = runtime.objectValue(from: item, selectors: ["flaggedContext"]) ?? item
            try runtime.sendVoidInteger(target, selector: "setFlagged:", value: flagged ? 1 : 0)
        }
        if let completed = mutation.completed {
            try runtime.sendVoidBool(item, selector: "setCompleted:", value: completed)
        }
        if mutation.changesTags {
            let context = try runtime.requireObject(item, selector: "hashtagContext")
            let existing =
                runtime.objectValue(from: context, selectors: ["hashtags"]).flatMap(runtime.objectArray) ?? []
            let names = existing.compactMap { runtime.stringValue(from: $0, selectors: ["name"]) }
            let wanted = mutation.resultingTags(from: names)
            let wantedKeys = Set(wanted.map { $0.lowercased() })
            for hashtag in existing {
                let name = runtime.stringValue(from: hashtag, selectors: ["name"])?.lowercased() ?? ""
                if !wantedKeys.contains(name) {
                    try runtime.sendVoidId(context, selector: "removeHashtag:", argument: hashtag)
                }
            }
            let have = Set(names.map { $0.lowercased() })
            for tag in wanted where !have.contains(tag.lowercased()) {
                _ = try runtime.sendIdIntegerId(
                    context, selector: "addHashtagWithType:name:", first: 0, second: tag as NSString)
            }
        }
        if let recurrence = mutation.recurrence {
            try runtime.sendVoid(item, selector: "removeAllRecurrenceRules")
            if case .set(let rule) = recurrence {
                let weekdays = try rule.weekdays.map { try runtime.recurrenceDayOfWeek($0) }
                var end: AnyObject?
                if let date = rule.endDate {
                    end = try runtime.make("REMRecurrenceEnd", "initWithEndDate:", date as NSDate)
                } else if let count = rule.count {
                    guard let cls = NSClassFromString("REMRecurrenceEnd") as? NSObject.Type,
                        let allocated = ObjCAlloc(cls) as AnyObject?
                    else { throw ReminderCLIError.missingClass("REMRecurrenceEnd") }
                    typealias Init = @convention(c) (AnyObject, Selector, Int) -> AnyObject?
                    let (selector, call) = try runtime.implementation(
                        allocated, "initWithOccurrenceCount:", as: Init.self)
                    end = call(allocated, selector, count)
                }
                try runtime.addRecurrenceRule(
                    item, frequency: rule.frequency.code, interval: rule.interval,
                    daysOfTheWeek: weekdays.isEmpty ? nil : weekdays as NSArray,
                    daysOfTheMonth: rule.daysOfMonth.isEmpty
                        ? nil : rule.daysOfMonth.map { NSNumber(value: $0) } as NSArray,
                    end: end)
            }
        }
        if mutation.clearAlarms || mutation.location != nil {
            let storage = runtime.objectValue(from: item, selectors: ["storage"]) ?? item
            let alarms = runtime.objectValue(from: storage, selectors: ["alarms"]).flatMap(runtime.objectArray) ?? []
            for alarm in alarms where runtime.boolValue(from: alarm, selectors: ["isSnooze"]) != true {
                let trigger = runtime.objectValue(from: alarm, selectors: ["trigger"])
                let kind = trigger.map { String(describing: type(of: $0)) } ?? ""
                let isLocation = kind.contains("LocationTrigger")
                let isTime = kind.contains("DateTrigger") && !kind.contains("DueDateDelta")
                if (mutation.clearAlarms && (isLocation || isTime)) || (mutation.location != nil && isLocation) {
                    try runtime.sendVoidId(item, selector: "removeAlarm:", argument: alarm)
                }
            }
        }
        for alarm in mutation.alarms {
            var timed = alarm
            if !timed.hasTime {
                timed = ReminderDate(date: alarm.date.addingTimeInterval(9 * 3600), hasTime: true, timeZone: nil)
            }
            let trigger = try runtime.make("REMAlarmDateTrigger", "initWithDateComponents:", Self.components(timed))
            guard try runtime.sendObjectOptional(item, "addAlarmWithTrigger:", trigger, nil) != nil else {
                throw ReminderCLIError.saveFailed("ReminderKit rejected the alarm.")
            }
        }
        if case .set(let location)? = mutation.location { try addLocationAlarm(location, to: item) }
        if let early = mutation.earlyAlert {
            let context = try runtime.requireObject(item, selector: "dueDateDeltaAlertContext")
            if let reminder,
                let current = runtime.objectValue(from: reminder, selectors: ["dueDateDeltaAlertContext"]),
                let alerts = runtime.objectValue(from: current, selectors: ["dueDateDeltaAlerts"]).flatMap(
                    runtime.objectArray), !alerts.isEmpty
            {
                let identifiers = alerts.compactMap { runtime.objectValue(from: $0, selectors: ["identifier"]) }
                try runtime.sendVoidId(
                    context, selector: "removeDueDateDeltaAlertsWithIdentifiers:", argument: identifiers as NSArray)
            }
            if case .set(let alert) = early {
                let delta = try runtime.dueDateDelta(unit: alert.unit.rawValue, count: -alert.count)
                guard
                    try runtime.sendObjectOptional(context, "addDueDateDeltaAlertWithDueDateDelta:", delta, nil) != nil
                else { throw ReminderCLIError.saveFailed("ReminderKit rejected the early alert.") }
            }
        }
    }

    func addLocationAlarm(_ location: ReminderLocationMutation, to item: AnyObject) throws {
        let structured = try runtime.make("REMStructuredLocation", "initWithTitle:", location.title as NSString)
        if let address = location.address {
            try runtime.sendVoidId(structured, selector: "setAddress:", argument: address as NSString)
        }
        try runtime.sendVoidDouble(structured, selector: "setLatitude:", value: location.latitude)
        try runtime.sendVoidDouble(structured, selector: "setLongitude:", value: location.longitude)
        try runtime.sendVoidDouble(structured, selector: "setRadius:", value: location.radius)
        guard let cls = NSClassFromString("REMAlarmLocationTrigger") as? NSObject.Type,
            let allocated = ObjCAlloc(cls) as AnyObject?
        else { throw ReminderCLIError.missingClass("REMAlarmLocationTrigger") }
        let selector = NSSelectorFromString("initWithStructuredLocation:proximity:")
        guard allocated.responds(to: selector),
            let trigger = ObjCSendInitIdInteger(allocated, selector, structured, location.proximity.reminderKitValue)
                as AnyObject?
        else {
            throw ReminderCLIError.missingSelector(
                className: "REMAlarmLocationTrigger", selector: "initWithStructuredLocation:proximity:")
        }
        guard try runtime.sendObjectOptional(item, "addAlarmWithTrigger:", trigger, nil) != nil else {
            throw ReminderCLIError.saveFailed("ReminderKit rejected the location alarm.")
        }
    }

    // MARK: - Verification

    /// Fields that did not round-trip. Empty means the readback matches the request.
    func mismatches(
        _ mutation: TaskMutation, title: String?, before: ReminderTaskSnapshot?, after: ReminderTaskSnapshot,
        listID: String?, advanced: Bool = false
    ) -> [String] {
        var failed: [String] = []
        func check(_ name: String, _ ok: Bool) { if !ok { failed.append(name) } }
        if let title = mutation.title ?? title { check("title", after.title == title) }
        switch mutation.notes {
        case .set(let notes)?: check("notes", after.notes == notes)
        case .clear?: check("notes", after.notes == nil)
        case nil: break
        }
        switch mutation.url {
        case .set(let url)?: check("url", after.url == url)
        case .clear?: check("url", after.url == nil)
        case nil: break
        }
        switch mutation.due {
        case .set(let due)? where !advanced:
            check(
                "due",
                after.due.map { $0.hasTime == due.hasTime && abs($0.date.timeIntervalSince(due.date)) < 1 } ?? false)
        case .clear?: check("due", after.due == nil)
        default: break
        }
        switch mutation.start {
        case .set(let start)?:
            check(
                "start",
                after.start.map { $0.hasTime == start.hasTime && abs($0.date.timeIntervalSince(start.date)) < 1 }
                    ?? false)
        case .clear?: check("start", after.start == nil)
        case nil: break
        }
        if let priority = mutation.priority { check("priority", after.priority == priority) }
        if let flagged = mutation.flagged { check("flagged", after.isFlagged == flagged) }
        if let completed = mutation.completed, !advanced { check("completed", after.isCompleted == completed) }
        if mutation.changesTags {
            let expected = Set(mutation.resultingTags(from: before?.tags ?? []).map { $0.lowercased() })
            check("tags", Set(after.tags.map { $0.lowercased() }) == expected)
        }
        switch mutation.recurrence {
        case .set(let rule)?:
            let actual = after.recurrence
            check(
                "recurrence",
                actual?.frequency == rule.frequency.rawValue && actual?.interval == rule.interval
                    && actual?.weekdays.sorted() == rule.weekdays && actual?.daysOfMonth.sorted() == rule.daysOfMonth
                    && actual?.count == rule.count
                    && (rule.endDate == nil) == (actual?.endDate == nil))
        case .clear?: check("recurrence", after.recurrence == nil)
        case nil: break
        }
        let dates = after.alarms.compactMap { alarm -> Date? in
            if case .date(let date) = alarm { return date.date }
            return nil
        }
        for alarm in mutation.alarms where alarm.hasTime && !advanced {
            check("alarms", dates.contains { abs($0.timeIntervalSince(alarm.date)) < 1 })
        }
        if mutation.clearAlarms, mutation.alarms.isEmpty { check("alarms", dates.isEmpty) }
        let locations = after.alarms.filter {
            if case .location = $0 { return true }
            return false
        }
        switch mutation.location {
        case .set(let location)?:
            check(
                "location",
                locations.contains {
                    if case .location(_, _, let lat, let lon, let radius, let proximity) = $0 {
                        return abs(lat - location.latitude) < 1e-6 && abs(lon - location.longitude) < 1e-6
                            && abs(radius - location.radius) < 0.01 && proximity == location.proximity.rawValue
                    }
                    return false
                })
        case .clear?: check("location", locations.isEmpty)
        case nil: break
        }
        switch mutation.earlyAlert {
        case .set(let alert)?: check("earlyAlert", after.earlyAlert == alert)
        case .clear?: check("earlyAlert", after.earlyAlert == nil)
        case nil: break
        }
        if let listID { check("list", after.listID == listID) }
        switch mutation.section {
        case .set(let id)?: check("section", after.sectionID == id)
        case .clear?: check("section", after.sectionID == nil)
        case nil: break
        }
        switch mutation.parent {
        case .set(let id)?: check("parent", after.parentID == id)
        case .clear?: check("parent", after.parentID == nil)
        case nil: break
        }
        return failed
    }

    func verify(
        _ mutation: TaskMutation, title: String?, before: ReminderTaskSnapshot?, after: ReminderTaskSnapshot,
        listID: String?, advanced: Bool = false
    ) throws {
        let failed = mismatches(
            mutation, title: title, before: before, after: after, listID: listID, advanced: advanced)
        guard failed.isEmpty else {
            throw unverified("task", after.id, "these fields did not round-trip: \(failed.joined(separator: ", "))")
        }
    }
}
