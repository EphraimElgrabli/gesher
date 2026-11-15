import Foundation

public protocol CLIErrorCodeProviding: Error {
    var code: String { get }
    var details: [String: String] { get }
}

public enum MutationVerification {
    /// A readback can fail after a successful commit. Preserve the affected native ID.
    public static func readback<T>(type: String, id: String, fetch: () throws -> T) throws -> T {
        do { return try fetch() } catch {
            throw PlatformError.mutationUnverified(
                type: type, id: id,
                reason: "Write outcome needs verification: " + error.localizedDescription)
        }
    }

    /// Only a native not_found response proves absence. Permission/fetch errors remain uncertain.
    public static func absence<T>(id: String, type: String = "object", fetch: () throws -> T) throws {
        do {
            _ = try fetch()
        } catch let error as CLIErrorCodeProviding where error.code == "not_found" {
            return
        } catch {
            throw PlatformError.mutationUnverified(
                type: type, id: id,
                reason: "Delete was acknowledged but absence could not be verified: " + error.localizedDescription)
        }
        throw PlatformError.mutationUnverified(
            type: type, id: id,
            reason:
                "Object \(id) still exists after delete acknowledgement. Inspect before retrying.")
    }
}
