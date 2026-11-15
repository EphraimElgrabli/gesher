import Foundation

public protocol PermissionBackend: Sendable {
    func preflight(service: TCCService) -> TCCStatus
    func request(service: TCCService, timeoutSeconds: Double) -> PermissionRequestResult
}

public enum PermissionRequestResult: String, Codable, Sendable {
    case granted, denied, timedOut = "timed_out", unavailable, blocked, settingsRequired = "settings_required"
}

public struct PermissionSnapshot: Encodable, Sendable {
    public let service: String
    public let permission: String
    public let requestMethod: String
    public let requestAttempted: Bool
    public let requestResult: PermissionRequestResult?
    public let settingsURL: String
    public let recovery: String
}

/// Authorization is a user decision. Never repeatedly prompt a denied service or
/// interpret a callback timeout as denial. Store authorization is checked separately.
public struct PermissionCoordinator: Sendable {
    private let backend: any PermissionBackend
    public init(backend: any PermissionBackend = TCCPermission.shared) { self.backend = backend }

    public func inspect(service: TCCService, request: Bool = false, timeoutSeconds: Double = 60) -> PermissionSnapshot {
        let before = backend.preflight(service: service)
        // Write-only Calendar access may be upgraded to Full Access through the same dialog.
        let attempted = request && (before == .notDetermined || before == .writeOnly) && service.canRequestDialog
        var result: PermissionRequestResult? =
            attempted
            ? backend.request(service: service, timeoutSeconds: timeoutSeconds)
            : (request && !service.canRequestDialog ? .settingsRequired : nil)
        let after = attempted ? backend.preflight(service: service) : before
        if result == .denied && after == .notDetermined { result = .blocked }
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "this CLI").lastPathComponent
        return PermissionSnapshot(
            service: service.rawValue, permission: after.label,
            requestMethod: service.canRequestDialog ? "native_system_dialog" : "system_settings_only",
            requestAttempted: attempted, requestResult: result, settingsURL: service.settingsURL,
            recovery: after == .authorized
                ? "Permission is allowed. Run your command to check access."
                : after == .writeOnly
                    ? "\(service.displayName) access is write-only: events can be added but not read. Open System Settings > Privacy & Security > \(service.displayName), and set \(executable) to Full Access."
                    : result == .blocked
                        ? "macOS did not grant this request and privacy remains undecided. The launching host may be missing a required privacy entitlement or purpose description. Open Settings or retry from a host that supports this service; this is not a confirmed user denial."
                        : result == .timedOut
                            ? "The request is still unresolved. Respond to the macOS dialog, then retry; a timeout is not a denial."
                            : "Grant \(service.displayName) access to \(executable) (or, when it runs in-process, to the launching application) in System Settings > Privacy & Security. Denied access is not re-prompted automatically."
        )
    }

    public func ensureAuthorized(service: TCCService, timeoutSeconds: Double = 60) throws {
        let status = inspect(service: service, request: true, timeoutSeconds: timeoutSeconds)
        guard status.permission == TCCStatus.authorized.label else {
            if status.requestResult == .timedOut {
                throw PlatformError.permissionRequestPending(
                    "\(service.displayName) authorization is waiting for a user response. Respond to the native dialog and retry."
                )
            }
            if status.permission == TCCStatus.unknown.label || status.requestResult == .unavailable
                || status.requestResult == .blocked
            {
                throw PlatformError.privateBackendUnavailable(
                    "macOS could not authorize \(service.displayName). The launching host may block system prompts; inspect permissions and its privacy entitlements, or use System Settings. No user denial or access is assumed."
                )
            }
            if status.permission == TCCStatus.notDetermined.label && status.requestResult == .granted {
                throw PlatformError.permissionRequestPending(
                    "The request was accepted, but privacy preflight has not confirmed authorization. Retry after the native decision is recorded."
                )
            }
            throw PlatformError.permissionDenied(status.recovery)
        }
    }
}

extension TCCStatus {
    public var label: String {
        switch self {
        case .authorized: "authorized"
        case .denied: "denied"
        case .notDetermined: "not_determined"
        case .writeOnly: "write_only"
        case .unknown: "unknown"
        }
    }
}

extension TCCService {
    public var canRequestDialog: Bool { self != .fullDiskAccess }
    public var settingsURL: String {
        let pane: String
        switch self {
        case .calendar: pane = "Privacy_Calendars"
        case .contacts: pane = "Privacy_Contacts"
        case .reminders: pane = "Privacy_Reminders"
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        }
        return "x-apple.systempreferences:com.apple.preference.security?" + pane
    }
    public var purpose: String {
        switch self {
        case .calendar: "Read and manage calendar events that you request through Gesher."
        case .contacts: "Read and manage contacts that you request through Gesher."
        case .reminders: "Read and manage reminder lists, sections and tasks that you request through Gesher."
        case .fullDiskAccess: "Read protected app data (such as Notes or Freeform) that you request through Gesher."
        }
    }
}
