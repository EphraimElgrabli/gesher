import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// A task in Reminders' Recently Deleted.
public struct ReminderDeletedTaskSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let accountID: String
    public let isCompleted: Bool
    public let modifiedDate: Date?
}

extension ReminderReadRepository {
    /// Native reminders in each account's Recently Deleted (concealed objects), newest first.
    func recentlyDeletedObjects(store: AnyObject) throws -> [(accountID: AnyObject, reminder: AnyObject)] {
        var result: [(AnyObject, AnyObject)] = []
        for account in try fetchAccounts(from: store) {
            guard let accountObjectID = runtime.objectValue(from: account.object, selectors: ["remObjectID"]),
                let uuid = (runtime.objectValue(from: accountObjectID, selectors: ["uuid"]) as? NSUUID)?.uuidString
            else { continue }
            if let capabilities = runtime.objectValue(from: account.object, selectors: ["capabilities"]),
                runtime.boolValue(from: capabilities, selectors: ["supportsRecentlyDeletedList"]) == false
            {
                continue
            }
            let parameters: NSDictionary = [
                "accountID": ["uuid": uuid, "entityName": "REMCDAccount"],
                // The app keeps deleted reminders for 30 days; ask a little wider.
                "deletedAfterDate": Date(timeIntervalSinceNow: -45 * 86_400),
                "countCompleted": false,
                "remindersPrefetch": ["base": "none"],
            ]
            let payload = try invoke(
                "REMRemindersListDataView_RecentlyDeletedInvocation", parameters: parameters, store: store,
                storages: [account.object])
            guard let model = payload["model"] as? NSDictionary, let entries = model["reminders"] as? [NSDictionary]
            else { throw ReminderCLIError.fetchFailed("Recently Deleted result is malformed.") }
            let selector = NSSelectorFromString("fetchReminderIncludingConcealedWithObjectID:error:")
            guard store.responds(to: selector) else {
                throw ReminderCLIError.missingSelector(className: "REMStore", selector: NSStringFromSelector(selector))
            }
            for entry in entries {
                guard let objectID = (entry["objectID"] as? NSDictionary).flatMap(stableObjectIDString),
                    let nativeID = makeObjectID(fromStableID: objectID)
                else { continue }
                var error: NSError?
                if let reminder = ObjCSendIdIdError(store, selector, nativeID, &error) as AnyObject? {
                    result.append((accountObjectID, reminder))
                }
            }
        }
        return result
    }

    public func fetchRecentlyDeletedTasks() throws -> [ReminderDeletedTaskSnapshot] {
        let store = try runtime.makeStore()
        return try recentlyDeletedObjects(store: store).map { accountID, reminder in
            let storage = runtime.objectValue(from: reminder, selectors: ["storage"]) ?? reminder
            return ReminderDeletedTaskSnapshot(
                id: runtime.objectIDString(from: reminder),
                title: runtime.stringValue(from: storage, selectors: ["titleAsString"]) ?? "",
                accountID: runtime.stableObjectIDString(from: accountID),
                isCompleted: runtime.boolValue(from: storage, selectors: ["isCompleted", "completed"]) ?? false,
                modifiedDate: runtime.objectValue(from: storage, selectors: ["lastModifiedDate"]) as? Date)
        }
    }
}

extension ReminderWriteRepository {
    /// Erases tasks from Recently Deleted, as "Delete" there does in the app
    /// (`REMStore.permanentlyHideReminders(with:accountID:completion:)`).
    public func purgeDeletedTasks(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let store = try runtime.makeStore()
        let wanted = Set(ids)
        let objects = try read.recentlyDeletedObjects(store: store).filter {
            wanted.contains(runtime.objectIDString(from: $0.reminder))
        }
        let found = Set(objects.map { runtime.objectIDString(from: $0.reminder) })
        if let missing = ids.first(where: { !found.contains($0) }) {
            throw ReminderCLIError.objectNotFound(type: "recently deleted task", id: missing)
        }
        let symbols = [
            "$sSo8REMStoreC19ReminderKitInternalE24permanentlyHideReminders4with9accountID10completionySaySo11REMReminderCG_So09REMObjectJ0Cys6ResultOyyts5Error_pGctF"
        ]
        let function = try DynamicRuntime.resolveFirstSymbol(
            candidates: symbols, feature: "REMStore.permanentlyHideReminders")
        let groups = Dictionary(grouping: objects) { runtime.stableObjectIDString(from: $0.accountID) }
        for (_, members) in groups {
            let reply = NativeServiceReply()
            let completion = PurgeCompletion { result in
                switch result {
                case .success: reply.complete(value: NSNull(), error: nil)
                case .failure(let error): reply.complete(value: nil, error: error as NSError)
                }
            }
            let reminders: [AnyObject] = members.map(\.reminder)
            let account = members[0].accountID
            // Thick Swift closure = (function, context); the array is one reference-counted word.
            let closure = withUnsafeBytes(of: completion) { $0.load(as: (UInt, UInt).self) }
            let array = withUnsafeBytes(of: reminders) { $0.load(as: UInt.self) }
            do {
                try withExtendedLifetime((reminders, completion, account, store)) {
                    ObjCCallSwiftMethod4(
                        function, Unmanaged.passUnretained(store).toOpaque(), array,
                        UInt(bitPattern: Unmanaged.passUnretained(account).toOpaque()), closure.0, closure.1)
                    _ = try reply.wait(timeout: 30)
                }
            } catch {
                throw ReminderCLIError.saveFailed("Recently Deleted was not emptied: \(error.localizedDescription)")
            }
        }
        let remaining = Set(try read.fetchRecentlyDeletedTasks().map(\.id))
        if let still = ids.first(where: remaining.contains) {
            throw PlatformError.mutationUnverified(
                type: "task", id: still, reason: "Task \(still) is still in Recently Deleted.")
        }
    }
}

/// Holds the completion closure with the exact Swift type ReminderKitInternal expects.
private struct PurgeCompletion {
    let body: (Result<Void, Error>) -> Void
    init(_ body: @escaping (Result<Void, Error>) -> Void) { self.body = body }
}
