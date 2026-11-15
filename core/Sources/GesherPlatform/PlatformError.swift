import Foundation

public enum PlatformError: CLIErrorCodeProviding, LocalizedError, Sendable {
    case frameworkLoadFailed([String])
    case missingClass(String)
    case missingSelector(className: String, selector: String)
    case storeInitializationFailed(String)
    case fetchFailed(String)
    case routeUnavailable(String)
    case objectNotFound(type: String, id: String)
    case invalidArgument(String)
    case unsupportedPrivateAPI(selector: String, reason: String)
    case saveFailed(String)
    case mutationUnverified(type: String, id: String, reason: String)
    case permissionDenied(String)
    case permissionRequestPending(String)
    case privateBackendUnavailable(String)
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .frameworkLoadFailed(let paths):
            return "Could not load private framework from: \(paths.joined(separator: ", "))"
        case .missingClass(let name):
            return "Private class is missing: \(name)"
        case .missingSelector(let className, let selector):
            return "Private selector is missing: \(className).\(selector)"
        case .storeInitializationFailed(let message):
            return "Could not initialize store: \(message)"
        case .routeUnavailable(let message):
            return message
        case .fetchFailed(let message):
            return message
        case .objectNotFound(let type, let id):
            return "\(type) not found: \(id)"
        case .invalidArgument(let message):
            return message
        case .unsupportedPrivateAPI(let selector, let reason):
            return "Unsupported private API selector \(selector): \(reason)"
        case .saveFailed(let message):
            return message
        case .mutationUnverified(_, _, let reason):
            return reason
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .permissionRequestPending(let message):
            return message
        case .privateBackendUnavailable(let message):
            return message
        case .internalError(let message):
            return message
        }
    }

    public var code: String {
        switch self {
        case .frameworkLoadFailed:
            return "framework_load_failed"
        case .missingClass:
            return "missing_class"
        case .missingSelector:
            return "missing_selector"
        case .storeInitializationFailed:
            return "store_initialization_failed"
        case .routeUnavailable:
            return "route_unavailable"
        case .fetchFailed:
            return "fetch_failed"
        case .objectNotFound:
            return "not_found"
        case .invalidArgument:
            return "invalid_argument"
        case .unsupportedPrivateAPI:
            return "unsupported_private_api"
        case .saveFailed, .mutationUnverified:
            return "save_failed"
        case .permissionDenied:
            return "permission_denied"
        case .permissionRequestPending:
            return "permission_request_pending"
        case .privateBackendUnavailable:
            return "private_backend_unavailable"
        case .internalError:
            return "internal_error"
        }
    }

    public var details: [String: String] {
        switch self {
        case .frameworkLoadFailed(let paths):
            return ["paths": paths.joined(separator: ",")]
        case .missingClass(let name):
            return ["class": name]
        case .missingSelector(let className, let selector):
            return ["class": className, "selector": selector]
        case .privateBackendUnavailable(let message):
            return ["reason": message]
        case .storeInitializationFailed(let message):
            return ["reason": message]
        case .objectNotFound(let type, let id):
            return ["type": type, "id": id]
        case .mutationUnverified(let type, let id, let reason):
            return ["type": type, "affectedID": id, "phase": "post_write_verification", "reason": reason]
        case .unsupportedPrivateAPI(let selector, let reason):
            return ["selector": selector, "reason": reason]
        case .permissionDenied(let message):
            return ["reason": message]
        default:
            return [:]
        }
    }
}
