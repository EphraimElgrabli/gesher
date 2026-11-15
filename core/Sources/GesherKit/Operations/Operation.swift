import GesherPlatform
import Foundation

/// What an operation does to user data. Drives MCP tool annotations and documentation.
public enum OperationEffect: String, Sendable {
    /// Reads only (network lookups included).
    case read
    /// Creates or changes data; never removes it.
    case write
    /// Removes or irreversibly replaces data. Selectors should use `MatchPolicy.exactName`.
    case destructive
}

/// One typed operation, exposed both as a CLI subcommand (`<app>-cli <path...> --flags`) and as an
/// MCP tool (`<path joined by _>`). Both front ends validate arguments against `params`, decode
/// the same `Input`, call `run`, and encode the same `Output`, so they cannot drift.
///
/// ```swift
/// struct CurrentWeather: AgentOperation {
///     struct Input: Decodable, Sendable { var location: String? }
///     static let path = ["current"]
///     static let summary = "Current conditions for a place (default: your saved location)."
///     static let params: [Param] = [.string("location", "Place name, saved location or 'lat,lon'.", positional: true)]
///     static let examples = ["current Haifa"]
///     static func run(_ input: Input, _ context: WeatherContext) throws -> CurrentOutput { ... }
/// }
/// ```
public protocol AgentOperation: SendableMetatype {
    associatedtype Input: Decodable & Sendable
    associatedtype Output: Encodable & Sendable
    associatedtype Context

    /// CLI words, e.g. `["location", "add"]`. The MCP tool name is `location_add`.
    static var path: [String] { get }
    /// One line, imperative, user-facing. Becomes the CLI help line and the MCP tool description.
    static var summary: String { get }
    static var params: [Param] { get }
    static var effect: OperationEffect { get }
    /// True when repeating the call with the same input has no further effect.
    static var idempotent: Bool { get }
    /// CLI argument strings after the executable name. Shown in help and decoded by tests.
    static var examples: [String] { get }

    /// Checks the decoded input before the context (and any private framework) is created.
    /// Throw `AgentError.invalid` for input the parameter declarations cannot express.
    static func validate(_ input: Input) throws
    static func run(_ input: Input, _ context: Context) throws -> Output
    /// Human rendering for `--format pretty`. Return nil to use the generic renderer.
    static func pretty(_ output: Output) -> String?
}

extension AgentOperation {
    public static var effect: OperationEffect { .read }
    public static var idempotent: Bool { effect == .read }
    public static var examples: [String] { [] }
    public static func pretty(_ output: Output) -> String? { nil }
    public static func validate(_ input: Input) throws {}
}

/// Input for operations without parameters.
public struct NoInput: Decodable, Sendable {}

/// The encoded result of one operation call.
public struct OperationResult: Sendable {
    public let value: JSONValue
    public let pretty: String?
    /// Set for batch outputs; any failure makes the CLI exit 1.
    public let failed: Int
    public let succeeded: Int
}

/// Type-erased operation bound to an app's `Context`.
public struct AnyOperation<Context>: Sendable {
    public let path: [String]
    public let summary: String
    public let params: [Param]
    public let effect: OperationEffect
    public let idempotent: Bool
    public let examples: [String]
    private let invoke: @Sendable (JSONValue, () throws -> Context) throws -> OperationResult

    public init<Op: AgentOperation>(_ operation: Op.Type) where Op.Context == Context {
        path = Op.path
        summary = Op.summary
        params = Op.params
        effect = Op.effect
        idempotent = Op.idempotent
        examples = Op.examples
        let name = Op.path.joined(separator: " ")
        let params = Op.params
        invoke = { arguments, context in
            let input = try Self.decode(Op.Input.self, arguments, params: params, operation: name)
            try Op.validate(input)
            let output = try Op.run(input, try context())
            let partial = output as? PartialFailureReporting
            return OperationResult(
                value: try JSONValue.encode(output), pretty: Op.pretty(output), failed: partial?.failed ?? 0,
                succeeded: partial?.succeeded ?? 1)
        }
    }

    init(
        path: [String], summary: String, params: [Param], effect: OperationEffect,
        invoke: @escaping @Sendable (JSONValue, () throws -> Context) throws -> OperationResult
    ) {
        self.path = path
        self.summary = summary
        self.params = params
        self.effect = effect
        self.idempotent = effect == .read
        self.examples = []
        self.invoke = invoke
    }

    public var name: String { path.joined(separator: " ") }
    public var toolName: String { path.joined(separator: "_").replacingOccurrences(of: "-", with: "_") }
    public var inputSchema: JSONValue { ParamValidation.inputSchema(params) }

    /// Validates, decodes and runs. Throws `AgentError` for invalid input. The context is only
    /// created after the input is valid (and never for built-ins that do not need it).
    public func call(_ arguments: JSONValue?, context: () throws -> Context) throws -> OperationResult {
        try invoke(arguments ?? .object([:]), context)
    }

    /// Validates and decodes without running; used by tests to check examples and schemas.
    public func validate(_ arguments: JSONValue?) throws {
        _ = try ParamValidation.normalize(arguments, params: params, operation: name)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ arguments: JSONValue, params: [Param], operation: String) throws
        -> T
    {
        let normalized = try ParamValidation.normalize(arguments, params: params, operation: operation)
        do {
            return try normalized.decode(type)
        } catch let error as AgentError {
            throw error
        } catch let DecodingError.keyNotFound(key, _) {
            throw AgentError.invalid("Missing parameter '\(key.stringValue)' for \(operation).")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            let key = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw AgentError.invalid("Invalid value for '\(key)' in \(operation): \(context.debugDescription)")
        } catch let DecodingError.dataCorrupted(context) {
            let key = context.codingPath.map(\.stringValue).joined(separator: ".")
            if let underlying = context.underlyingError as? AgentError { throw underlying }
            throw AgentError.invalid("Invalid value for '\(key)' in \(operation): \(context.debugDescription)")
        }
    }
}

/// A natural-language date parameter value. Decoding parses with `DateInput` in the user's time
/// zone; invalid text fails with `invalid_argument` and an example-bearing hint.
public struct NaturalDate: Decodable, Sendable, Equatable {
    public let resolved: ResolvedDate
    public var date: Date { resolved.date }
    public var hasTime: Bool { resolved.hasTime }

    public init(_ text: String, input: DateInput = DateInput()) throws {
        resolved = try input.parse(text)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(text)
        } catch let error as AgentError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.message, underlyingError: error))
        }
    }
}
