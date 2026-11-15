import Foundation

public enum TCCService: String, Sendable {
    case reminders = "kTCCServiceReminders"
    case calendar = "kTCCServiceCalendar"
    case contacts = "kTCCServiceAddressBook"
    case fullDiskAccess = "kTCCServiceSystemPolicyAllFiles"

    public var displayName: String {
        switch self {
        case .reminders: return "Reminders"
        case .calendar: return "Calendars"
        case .contacts: return "Contacts"
        case .fullDiskAccess: return "Full Disk Access"
        }
    }
}

public enum TCCStatus: Int, Sendable {
    case authorized = 0
    case denied = 1
    case notDetermined = 2
    /// Calendar on macOS 14+: events can be added but not read (Full Access is needed to read).
    case writeOnly = 3
    case unknown = -1
}

public final class TCCPermission: PermissionBackend, @unchecked Sendable {
    public static let shared = TCCPermission()

    private let tccHandle: UnsafeMutableRawPointer?

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFn =
        @convention(c) (CFString, CFDictionary?, (@convention(block) (Bool) -> Void)?) -> Bool

    private let preflightFn: PreflightFn?
    private let requestFn: RequestFn?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW)
        self.tccHandle = handle

        if let handle {
            if let sym = dlsym(handle, "TCCAccessPreflight") {
                self.preflightFn = unsafeBitCast(sym, to: PreflightFn.self)
            } else {
                self.preflightFn = nil
            }

            if let sym = dlsym(handle, "TCCAccessRequest") {
                self.requestFn = unsafeBitCast(sym, to: RequestFn.self)
            } else {
                self.requestFn = nil
            }
        } else {
            self.preflightFn = nil
            self.requestFn = nil
        }
    }

    public func preflight(service: TCCService) -> TCCStatus {
        guard let preflightFn else { return .unknown }
        let result = preflightFn(service.rawValue as CFString, nil)
        switch result {
        case 0: return .authorized
        case 1: return .denied
        case 2: return .notDetermined
        default: return .unknown
        }
    }

    public func request(service: TCCService, timeoutSeconds: Double = 60) -> PermissionRequestResult {
        guard service.canRequestDialog else { return .settingsRequired }
        guard let requestFn else { return .unavailable }
        let reply = NativeServiceReply()
        let purposeKey: CFString
        if let tccHandle, let symbol = dlsym(tccHandle, "kTCCAccessRequestOptionPurpose") {
            purposeKey = symbol.assumingMemoryBound(to: CFString.self).pointee
        } else {
            return .unavailable
        }
        let options = [purposeKey as String: service.purpose] as CFDictionary
        _ = requestFn(service.rawValue as CFString, options) { granted in
            reply.complete(value: NSNumber(value: granted), error: nil)
        }
        do {
            guard let granted = try reply.wait(timeout: timeoutSeconds) as? NSNumber else { return .unavailable }
            return granted.boolValue ? .granted : .denied
        } catch { return .timedOut }
    }

    /// Asks tccd for a specific authorization right for this process, as Apple's daemons do
    /// (`tcc_server_message_request_authorization_change`). Calendar on macOS 14+ needs right 2
    /// (full access); a plain `TCCAccessRequest` asks for write-only access. Returns the granted
    /// right (0 denied, 1 unknown, 2 allowed, 3 limited, 4 write-only) or nil when unavailable.
    public func requestRight(service: TCCService, right: UInt64, timeoutSeconds: Double = 60) -> (
        right: UInt64?, timedOut: Bool
    ) {
        typealias Create = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias Make = @convention(c) () -> UnsafeMutableRawPointer?
        typealias SetPolicy = @convention(c) (UnsafeMutableRawPointer, UInt64) -> Void
        typealias Service = @convention(c) (CFString) -> UnsafeMutableRawPointer?
        typealias Value = @convention(c) (UnsafeMutableRawPointer) -> UInt64
        typealias Reply = @convention(block) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        typealias Request =
            @convention(c) (
                UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer,
                UInt64, UnsafeRawPointer?, Reply
            ) -> Void
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            guard let tccHandle, let address = dlsym(tccHandle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let createServer = symbol("tcc_server_create", Create.self),
            let createOptions = symbol("tcc_message_options_create", Make.self),
            let setReplyPolicy = symbol("tcc_message_options_set_reply_handler_policy", SetPolicy.self),
            let selfCredential = symbol("tcc_credential_singleton_for_self", Make.self),
            let serviceNamed = symbol("tcc_service_singleton_for_CF_name", Service.self),
            let recordRight = symbol("tcc_authorization_record_get_authorization_right", Value.self),
            let requestChange = symbol("tcc_server_message_request_authorization_change", Request.self),
            let server = createServer(nil), let options = createOptions(), let credential = selfCredential(),
            let tccService = serviceNamed(service.rawValue as CFString)
        else { return (nil, false) }
        setReplyPolicy(options, 0)
        let reply = NativeServiceReply()
        let completion: Reply = { record, _ in
            reply.complete(value: record.map { NSNumber(value: recordRight($0)) }, error: nil)
        }
        requestChange(server, options, credential, tccService, right, nil, completion)
        do {
            return ((try reply.wait(timeout: timeoutSeconds) as? NSNumber)?.uint64Value, false)
        } catch { return (nil, true) }
    }
}
