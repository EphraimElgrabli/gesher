import GesherPlatform
import Foundation
import ObjCRuntimeSupport

struct NativeCalendarEntity {
    let id: AnyObject
    let properties: [String: Any]
    var occurrenceDate: Date? = nil

    var identifier: String? { Self.identifier(of: id) }

    /// A to-one relation as an object ID string.
    func relatedIdentifier(_ key: String) -> String? {
        related(key).first.flatMap(Self.identifier(of:))
    }

    /// A to-one or to-many relation as native object IDs. Dictionary representations without a
    /// `dbID` (relations within the same database) take this entity's database.
    func related(_ key: String) -> [AnyObject] {
        properties[key].map { Self.objectIDs(from: $0, database: CalendarSession.database(of: id)) } ?? []
    }

    func string(_ key: String) -> String? {
        (properties[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func number(_ key: String) -> NSNumber? { properties[key] as? NSNumber }

    func date(_ key: String) -> Date? { properties[key] as? Date }

    static func identifier(of value: Any) -> String? {
        objectIDs(from: value).first.flatMap {
            DynamicRuntime.shared.stringValue(from: $0, selectors: ["stringRepresentation"])
        }
    }

    /// Relations arrive as CADObjectIDs, dictionary representations, or collections of either.
    static func objectIDs(from value: Any, database: Int? = nil) -> [AnyObject] {
        if let set = value as? NSSet { return set.allObjects.flatMap { objectIDs(from: $0, database: database) } }
        if let array = value as? NSArray { return array.flatMap { objectIDs(from: $0, database: database) } }
        if var dictionary = value as? [String: Any] {
            if dictionary["dbID"] == nil, let database { dictionary["dbID"] = database }
            guard let cls = NSClassFromString("CADObjectID"), let allocated = ObjCAlloc(cls),
                let id = ObjCSendInitId(
                    allocated, NSSelectorFromString("initWithDictionaryRepresentation:"), dictionary as NSDictionary)
            else { return [] }
            return [id as AnyObject]
        }
        if value is NSNull { return [] }
        let object = value as AnyObject
        return DynamicRuntime.shared.stringValue(from: object, selectors: ["stringRepresentation"]) == nil
            ? [] : [object]
    }
}

/// Callbacks can arrive on the daemon connection queue; all shared state is locked.
final class CalendarDaemonReply: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var code: Int32 = 0
    private var ids: AnyObject?
    private var rows: AnyObject?

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    func complete(code: Int32, ids: AnyObject?, rows: AnyObject?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        self.code = code
        self.ids = ids
        self.rows = rows
        done = true
    }

    func entities(keys: [String]) throws -> [NativeCalendarEntity] {
        lock.lock()
        defer { lock.unlock() }
        guard done else { throw PlatformError.fetchFailed("CalendarDaemon reply timed out after 5 seconds.") }
        guard code == 0 else { throw PlatformError.fetchFailed("CalendarDaemon rejected fetch (code \(code)).") }
        guard let ids = ids as? NSArray, let rows = rows as? NSArray, ids.count == rows.count else {
            throw PlatformError.fetchFailed("CalendarDaemon returned malformed entity/property collections.")
        }
        return try (0..<ids.count).map { index in
            guard let values = rows[index] as? NSArray, values.count == keys.count else {
                throw PlatformError.fetchFailed("CalendarDaemon returned a property row with unexpected length.")
            }
            let properties = Dictionary(
                uniqueKeysWithValues: keys.enumerated().compactMap { offset, key in
                    values[offset] is NSNull ? nil : (key, values[offset])
                })
            return NativeCalendarEntity(id: ids[index] as AnyObject, properties: properties)
        }
    }
}

final class CalendarValueReply: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (Int32, AnyObject?)?

    func complete(code: Int32, value: AnyObject?) {
        lock.lock()
        defer { lock.unlock() }
        if result == nil { result = (code, value) }
    }

    func wait() throws -> AnyObject? {
        let deadline = Date().addingTimeInterval(5)
        while deadline.timeIntervalSinceNow > 0 {
            lock.lock()
            let snapshot = result
            lock.unlock()
            if let (code, value) = snapshot {
                guard code == 0 else {
                    if code == 1010 {
                        throw PlatformError.objectNotFound(type: "calendar object", id: "requested ID")
                    }
                    throw PlatformError.fetchFailed("CalendarDaemon rejected operation (code \(code)).")
                }
                return value
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        throw PlatformError.fetchFailed("CalendarDaemon reply timed out after 5 seconds.")
    }
}
