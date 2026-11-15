import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Native entity type numbers used by CalendarDaemon object IDs.
enum CalendarEntityType {
    static let calendar = 1
    static let event = 2
    static let alarm = 4
    static let recurrenceRule = 5
    static let source = 6
    static let attendee = 7
    static let organizer = 8
    static let exceptionDate = 10
    static let location = 14
}

/// Private CalendarDaemon access: one XPC connection per `session`, typed message sends,
/// property-row fetches and transactional commits. EventKit is loaded only to resolve the
/// private connection classes; no public EventKit store or wrapper reads or writes data.
public final class CalendarRuntime: @unchecked Sendable {
    private let loader = FrameworkLoader()
    private let frameworks = ["CalendarDatabase", "CalendarFoundation", "CalendarDaemon"]

    public init() {}

    func load() throws {
        _ = try loader.loadFirst(from: ["/System/Library/Frameworks/EventKit.framework/EventKit"])
        for framework in frameworks {
            try loader.loadFirst(from: [
                "/System/Library/PrivateFrameworks/\(framework).framework/\(framework)",
                "/System/Library/PrivateFrameworks/\(framework).framework/Versions/A/\(framework)",
            ])
        }
    }

    /// Opens a daemon connection, runs `body` with it, disconnects. No authorization check.
    func connection<T>(_ body: (AnyObject) throws -> T) throws -> T {
        try load()
        let native = DynamicRuntime.shared
        let factory = try native.requireObject(
            try native.requireClass("EKRemoteXPCConnectionFactory"), selector: "sharedInstance")
        let allocated = try native.alloc(try native.requireClass("EKDaemonConnection"))
        guard
            let connection = ObjCSendInitId(
                allocated, try NativeProperty.selector(allocated, "initWithConnectionFactory:"), factory) as AnyObject?
        else {
            throw PlatformError.storeInitializationFailed("Could not create private CalendarDaemon connection.")
        }
        defer { ObjCSendVoid(connection, NSSelectorFromString("disconnect")) }
        ObjCSendVoidId(
            connection, NSSelectorFromString("setInitializationOptions:"),
            try native.allocInit("CADDatabaseInitializationOptions"))
        guard ObjCSendBool(connection, NSSelectorFromString("_connectToServer")) else {
            throw PlatformError.fetchFailed("Could not connect to CalendarDaemon.")
        }
        return try body(connection)
    }

    /// Opens a daemon connection with full event access, runs `body`, disconnects.
    func session<T>(_ body: (CalendarSession) throws -> T) throws -> T {
        try PermissionCoordinator(backend: CalendarPermission(runtime: self)).ensureAuthorized(service: .calendar)
        return try connection { connection in
            let authorization = ObjCSendInteger(connection, NSSelectorFromString("eventAuthorization"))
            guard authorization == CalendarPermission.fullAccess else {
                throw PlatformError.permissionDenied(
                    authorization == CalendarPermission.writeOnly
                        ? "Calendar access is write-only; reading events needs Full Access. Open System Settings > "
                            + "Privacy & Security > Calendars and choose Full Access for calendar-cli."
                        : "Full Calendar access is required (native authorization status \(authorization)). "
                            + "Run calendar-cli permissions --request.")
            }
            let proxy = try DynamicRuntime.shared.requireObject(connection, selector: "CADOperationProxy")
            return try body(CalendarSession(proxy: proxy))
        }
    }
}

/// Calendar privacy through CalendarDaemon, as EventKit does on macOS 14+: the status
/// distinguishes Full Access from write-only, and requests ask for Full Access
/// (`CADDatabaseRequestAccessForEntityType:desiredFullAccess:...`). A plain TCC request
/// would only grant write-only access.
public final class CalendarPermission: PermissionBackend, @unchecked Sendable {
    static let notDetermined = 0, restricted = 1, denied = 2, fullAccess = 3, writeOnly = 4
    private let runtime: CalendarRuntime

    public init(runtime: CalendarRuntime = CalendarRuntime()) { self.runtime = runtime }

    public func preflight(service: TCCService) -> TCCStatus {
        guard service == .calendar else { return TCCPermission.shared.preflight(service: service) }
        guard
            let status = try? runtime.connection({
                ObjCSendInteger($0, NSSelectorFromString("eventAuthorization"))
            })
        else { return .unknown }
        switch status {
        case Self.fullAccess: return .authorized
        case Self.writeOnly: return .writeOnly
        case Self.notDetermined: return .notDetermined
        case Self.restricted, Self.denied: return .denied
        default: return .unknown
        }
    }

    public func request(service: TCCService, timeoutSeconds: Double) -> PermissionRequestResult {
        guard service == .calendar else {
            return TCCPermission.shared.request(service: service, timeoutSeconds: timeoutSeconds)
        }
        // Right 2 is full access; calaccessd answers CADDatabaseRequestAccess... with an error for
        // clients without an app bundle, so the CLI asks tccd for its own process directly.
        let reply = TCCPermission.shared.requestRight(service: .calendar, right: 2, timeoutSeconds: timeoutSeconds)
        if reply.timedOut { return .timedOut }
        if ProcessInfo.processInfo.environment["GESHER_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("calendar access right: \(String(describing: reply.right))\n".utf8))
        }
        guard reply.right != nil else { return .unavailable }
        return preflight(service: .calendar) == .authorized ? .granted : .denied
    }
}

/// One live daemon connection. Not thread-safe; used within a single `session` call.
final class CalendarSession {
    let proxy: AnyObject

    init(proxy: AnyObject) { self.proxy = proxy }

    private func send() throws -> UnsafeMutableRawPointer {
        guard let address = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else {
            throw PlatformError.internalError("Objective-C runtime dispatch unavailable.")
        }
        return address
    }

    private func selector(_ name: String) throws -> Selector { try NativeProperty.selector(proxy, name) }

    // MARK: Reads

    /// `CADDatabaseGet...WithFaultedProperties:reply:` → one object ID and one property row per entity.
    func fetchAll(_ selectorName: String, keys: [String]) throws -> [NativeCalendarEntity] {
        let reply = CalendarDaemonReply()
        let callback: @convention(block) (Int32, AnyObject?, AnyObject?) -> Void = { code, ids, rows in
            reply.complete(code: code, ids: ids, rows: rows)
        }
        typealias Send = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        unsafeBitCast(try send(), to: Send.self)(
            proxy, try selector(selectorName), keys as NSArray, callback as AnyObject)
        let deadline = Date().addingTimeInterval(5)
        while !reply.isComplete && deadline.timeIntervalSinceNow > 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return try reply.entities(keys: keys)
    }

    /// Property rows for the given object IDs, in input order. Missing IDs fail.
    func properties(_ ids: [AnyObject], keys: [String]) throws -> [NativeCalendarEntity] {
        if ids.isEmpty { return [] }
        var seen = Set<String>()
        let unique = try ids.filter { seen.insert(try Self.string($0)).inserted }
        let result = CalendarValueReply()
        let callback: @convention(block) (Int32, AnyObject?) -> Void = { result.complete(code: $0, value: $1) }
        typealias Fetch = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject) -> Void
        unsafeBitCast(try send(), to: Fetch.self)(
            proxy, try selector("CADObjects:getPropertiesWithNames:reply:"), unique as NSArray, keys as NSArray,
            callback as AnyObject)
        guard let rows = try result.wait() as? NSArray, rows.count == unique.count else {
            throw PlatformError.fetchFailed("CalendarDaemon returned malformed property rows.")
        }
        var byID: [String: NativeCalendarEntity] = [:]
        for (index, id) in unique.enumerated() {
            guard
                let row = DynamicRuntime.shared.objectValue(from: rows[index] as AnyObject, selectors: ["loadedValues"])
                    as? NSArray, row.count == keys.count
            else { throw PlatformError.fetchFailed("CalendarDaemon returned a malformed property row.") }
            let values = Dictionary(
                uniqueKeysWithValues: keys.enumerated().compactMap { i, key in row[i] is NSNull ? nil : (key, row[i]) })
            byID[try Self.string(id)] = NativeCalendarEntity(id: id, properties: values)
        }
        return try ids.map { id in
            guard let entity = byID[try Self.string(id)] else {
                throw PlatformError.fetchFailed("CalendarDaemon omitted requested properties.")
            }
            return entity
        }
    }

    /// Occurrences overlapping [start, end) in the given calendars (all when nil).
    func occurrences(start: Date, end: Date, calendars: [AnyObject]?) throws -> [(id: AnyObject, occurrence: Date?)] {
        let native = DynamicRuntime.shared
        let allocated = try native.alloc(try native.requireClass("CADEventPredicate"))
        typealias Initialize =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject?) -> AnyObject?
        guard
            let predicate = unsafeBitCast(try send(), to: Initialize.self)(
                allocated, try NativeProperty.selector(allocated, "initWithStartDate:endDate:timeZone:calendars:"),
                start as NSDate, end as NSDate, TimeZone.current as NSTimeZone, calendars.map { $0 as NSArray })
        else { throw PlatformError.fetchFailed("Could not construct private event predicate.") }
        let result = CalendarValueReply()
        let callback: @convention(block) (Int32, AnyObject?) -> Void = { result.complete(code: $0, value: $1) }
        typealias Fetch = @convention(c) (AnyObject, Selector, AnyObject, Int32, Int32, Bool, AnyObject) -> Void
        unsafeBitCast(try send(), to: Fetch.self)(
            proxy,
            try selector("CADDatabaseFetchCalendarItemsWithPredicate:entityType:fetchIdentifier:synchronous:reply:"),
            predicate, Int32(CalendarEntityType.event), 1, true, callback as AnyObject)
        guard let wrappers = try result.wait() as? NSArray else {
            throw PlatformError.fetchFailed("CalendarDaemon returned malformed event wrappers.")
        }
        return try wrappers.map { wrapper in
            (
                try native.requireObject(wrapper as AnyObject, selector: "objectID"),
                native.objectValue(from: wrapper as AnyObject, selectors: ["occurrenceDate"]) as? Date
            )
        }
    }

    /// The calendar that receives new events by default, when the daemon reports one.
    func defaultCalendarID() throws -> String? {
        let result = CalendarValueReply()
        let callback: @convention(block) (Int32, AnyObject?) -> Void = { result.complete(code: $0, value: $1) }
        typealias Fetch = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject) -> Void
        unsafeBitCast(try send(), to: Fetch.self)(
            proxy, try selector("CADDatabaseGetDefaultCalendarForNewEventsInDelegateSource:withReply:"), nil,
            callback as AnyObject)
        guard let value = try result.wait() else { return nil }
        return NativeCalendarEntity.identifier(of: value)
    }

    /// True when every ID exists. `CADObjectsExist:reply:` replies with the IDs that do not.
    func exists(_ id: AnyObject) throws -> Bool {
        let result = CalendarValueReply()
        let callback: @convention(block) (Int32, AnyObject?) -> Void = { result.complete(code: $0, value: $1) }
        typealias Fetch = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        unsafeBitCast(try send(), to: Fetch.self)(
            proxy, try selector("CADObjectsExist:reply:"), [id] as NSArray, callback as AnyObject)
        guard let missing = try result.wait() else { return true }
        guard let array = missing as? NSArray else {
            throw PlatformError.fetchFailed("CalendarDaemon returned malformed missing-object IDs.")
        }
        return array.count == 0
    }

    // MARK: Writes

    /// Commits deletes and inserts/updates in one daemon transaction; returns temporary → permanent IDs.
    @discardableResult
    func commit(_ changes: CalendarChangeSet) throws -> NSDictionary {
        let result = CalendarValueReply()
        // Installed daemon ABI: error, ID map, timestamp, changes, offsets, syncOnly.
        let callback: @convention(block) (Int32, AnyObject?, AnyObject?, AnyObject?, AnyObject?, Bool) -> Void = {
            code, ids, _, _, _, _ in result.complete(code: code, value: ids)
        }
        typealias Commit =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject, Int64, AnyObject?, AnyObject) -> Void
        unsafeBitCast(try send(), to: Commit.self)(
            proxy,
            try selector("CADDatabaseCommitDeletes:updatesAndInserts:options:andFetchChangesSinceTimestamp:withReply:"),
            changes.deletes as NSArray, changes.updates, 0, nil, callback as AnyObject)
        do {
            guard let map = try result.wait() as? NSDictionary else {
                throw PlatformError.saveFailed("CalendarDaemon returned a malformed commit ID map.")
            }
            return map
        } catch {
            throw PlatformError.saveFailed(
                "CalendarDaemon commit failed: \(error.localizedDescription). Inspect current state before retrying; the result may be uncertain."
            )
        }
    }

    // MARK: IDs

    static func string(_ id: AnyObject) throws -> String {
        guard let value = DynamicRuntime.shared.stringValue(from: id, selectors: ["stringRepresentation"]) else {
            throw PlatformError.fetchFailed("CalendarDaemon object has no native ID.")
        }
        return value
    }

    /// Decodes a native ID string like `x-apple-eventkit:///Event/p12` for the expected entity.
    static func objectID(_ string: String, entity: String, type: Int) throws -> AnyObject {
        guard let url = URL(string: string), url.scheme == "x-apple-eventkit",
            url.pathComponents.count == 3, url.pathComponents[1] == entity,
            url.lastPathComponent.hasPrefix("p"), let row = Int(url.lastPathComponent.dropFirst()), row > 0,
            let database = Int(url.host ?? "0"), database >= 0
        else {
            throw AgentError.invalid(
                "'\(string)' is not a \(entity.lowercased()) id.",
                hint: "Use an id returned by a list or search operation, or a name.")
        }
        return try make(["dbID": database, "entityType": type, "rowID": row, "temporary": false])
    }

    static func make(_ representation: NSDictionary) throws -> AnyObject {
        let allocated = try DynamicRuntime.shared.alloc(try DynamicRuntime.shared.requireClass("CADObjectID"))
        guard
            let object = ObjCSendInitId(
                allocated, NSSelectorFromString("initWithDictionaryRepresentation:"), representation) as AnyObject?
        else { throw PlatformError.internalError("Could not construct a native calendar object ID.") }
        return object
    }

    static func database(of id: AnyObject) -> Int { ObjCSendInteger(id, NSSelectorFromString("databaseID")) }
}

/// One daemon transaction being assembled: inserts get temporary IDs in the target database.
final class CalendarChangeSet {
    let database: Int
    let updates = NSMutableDictionary()
    private(set) var deletes: [AnyObject] = []

    init(database: Int) { self.database = database }

    func insert(_ type: Int, _ values: [String: Any]) throws -> AnyObject {
        let id = try CalendarSession.make([
            "entityType": type, "rowID": Int.random(in: 1...Int(Int32.max)), "dbID": database, "temporary": true,
        ])
        try set(id, values)
        return id
    }

    /// Merges values into the pending update for `id`.
    func set(_ id: AnyObject, _ values: [String: Any]) throws {
        guard let key = id as? NSCopying else { throw PlatformError.internalError("Native ID is not copyable.") }
        let merged = NSMutableDictionary(dictionary: (updates.object(forKey: key) as? NSDictionary) ?? [:])
        for (name, value) in values { merged[name] = value }
        updates.setObject(merged, forKey: key)
    }

    func delete(_ ids: [AnyObject]) { deletes.append(contentsOf: ids) }

    var isEmpty: Bool { updates.count == 0 && deletes.isEmpty }
}
