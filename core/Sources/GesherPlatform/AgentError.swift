import Foundation

/// A selectable entity offered back to the caller when a selector is ambiguous or unknown.
public struct Candidate: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String?

    public init(id: String, name: String, detail: String? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// The agent-facing error. Every failure an operation reports should be expressible as one:
/// a stable machine `code`, a human `message`, an actionable `hint`, and optional `candidates`.
///
/// Exit codes: 64 for input the caller must change (`invalid_argument`, `ambiguous`),
/// 1 for everything else (backend, permission, not found, unverified write).
public struct AgentError: CLIErrorCodeProviding, LocalizedError, Equatable, Sendable {
    public let code: String
    public let message: String
    public let hint: String?
    public let candidates: [Candidate]
    public let details: [String: String]

    public init(
        code: String, message: String, hint: String? = nil, candidates: [Candidate] = [],
        details: [String: String] = [:]
    ) {
        self.code = code
        self.message = message
        self.hint = hint
        self.candidates = candidates
        self.details = details
    }

    public var errorDescription: String? { message }

    public var exitCode: Int32 { Self.inputCodes.contains(code) ? 64 : 1 }

    static let inputCodes: Set<String> = [
        "invalid_argument", "ambiguous", "unknown_operation", "file_not_allowed", "confirmation_required",
    ]

    public static func invalid(_ message: String, hint: String? = nil) -> AgentError {
        AgentError(code: "invalid_argument", message: message, hint: hint)
    }

    public static func notFound(_ type: String, _ selector: String, suggestions: [Candidate] = []) -> AgentError {
        AgentError(
            code: "not_found", message: "No \(type) matches '\(selector)'.",
            hint: suggestions.isEmpty
                ? "List the available \(type)s and retry with a name or id from the result."
                : "Did you mean one of the candidates? Retry with its name or id.",
            candidates: suggestions, details: ["type": type, "selector": selector])
    }

    public static func ambiguous(_ type: String, _ selector: String, candidates: [Candidate]) -> AgentError {
        AgentError(
            code: "ambiguous", message: "'\(selector)' matches \(candidates.count) \(type)s.",
            hint: "Retry with one candidate's id, or a more specific name.", candidates: candidates,
            details: ["type": type, "selector": selector])
    }

    /// Normalizes any thrown error into an `AgentError`, attaching a default hint per code.
    public static func from(_ error: Error) -> AgentError {
        if let agent = error as? AgentError { return agent }
        if let coded = error as? CLIErrorCodeProviding {
            return AgentError(
                code: coded.code, message: error.localizedDescription, hint: defaultHint(coded.code),
                details: coded.details)
        }
        return AgentError(
            code: "internal_error", message: error.localizedDescription, hint: defaultHint("internal_error"))
    }

    static func defaultHint(_ code: String) -> String? {
        switch code {
        case "invalid_argument": "Check the operation's parameters with --help and retry."
        case "not_found": "List the items first and retry with a name or id from the result."
        case "save_failed":
            "The write may have committed. Read the affected item before retrying; do not recreate it blindly."
        case "permission_denied":
            "Allow access for the launching app in System Settings > Privacy & Security, then restart that app."
        case "permission_request_pending": "Answer the macOS permission dialog, then retry."
        case "unsupported_private_api", "missing_class", "missing_selector", "framework_load_failed":
            "This macOS version does not expose the private API this operation needs; it cannot be retried as is."
        case "fetch_failed", "private_backend_unavailable":
            "The Apple service did not answer. Retry once; if it persists run doctor."
        case "route_unavailable", "route_service_error":
            "No route for this transport. Do not estimate; try another transport or report the limitation."
        default: nil
        }
    }
}

extension AgentError: Encodable {
    private enum CodingKeys: String, CodingKey { case code, message, hint, candidates, details }

    /// Compact: empty candidates/details and a missing hint are omitted.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(hint, forKey: .hint)
        if !candidates.isEmpty { try container.encode(candidates, forKey: .candidates) }
        if !details.isEmpty { try container.encode(details, forKey: .details) }
    }
}
