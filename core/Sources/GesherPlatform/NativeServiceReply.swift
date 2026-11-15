import Foundation

/// Owns native callback state even after timeout; late or repeated replies cannot race a reader.
public final class NativeServiceReply: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var closed = false
    private var value: AnyObject?
    private var failure: NSError?

    public init() {}

    public func complete(value: AnyObject?, error: AnyObject?) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed, !closed else { return }
        self.value = value
        self.failure = error as? NSError
        completed = true
    }

    public func wait(timeout: TimeInterval = 15) throws -> AnyObject? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            if completed {
                let result = value
                let error = failure
                closed = true
                lock.unlock()
                if let error { throw PlatformError.fetchFailed(error.localizedDescription) }
                return result
            }
            if Date() >= deadline {
                closed = true
                lock.unlock()
                throw PlatformError.fetchFailed("Native service request timed out.")
            }
            lock.unlock()
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
    }
}
