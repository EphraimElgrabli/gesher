import GesherPlatform
import Foundation

/// One input parameter of an operation. The list of `Param`s is the single declaration from
/// which the CLI flags, the CLI help, the MCP `inputSchema` and argument validation are derived.
/// `name` must equal the corresponding `Input` property (its JSON key).
public struct Param: Sendable {
    public indirect enum Kind: Sendable, Equatable {
        case string
        case integer(min: Int?, max: Int?)
        case number(min: Double?, max: Double?)
        case boolean
        /// A natural date expression, see `DateInput`.
        case date
        case choice([String])
        case array(Kind)
        /// Free-form JSON object; the operation's `Input` decodes it.
        case object
    }

    public let name: String
    public let kind: Kind
    public let summary: String
    public let required: Bool
    public let defaultValue: JSONValue?
    /// CLI only: bare (non-flag) arguments fill this parameter. At most one per operation.
    public let positional: Bool

    public init(
        _ name: String, _ kind: Kind, _ summary: String, required: Bool = false, default defaultValue: JSONValue? = nil,
        positional: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.summary = summary
        self.required = required
        self.defaultValue = defaultValue
        self.positional = positional
    }

    public static func string(
        _ name: String, _ summary: String, required: Bool = false, default value: String? = nil,
        positional: Bool = false
    ) -> Param {
        Param(name, .string, summary, required: required, default: value.map(JSONValue.string), positional: positional)
    }

    public static func integer(
        _ name: String, _ summary: String, required: Bool = false, default value: Int? = nil, min: Int? = nil,
        max: Int? = nil
    ) -> Param {
        Param(
            name, .integer(min: min, max: max), summary, required: required,
            default: value.map { .number(Double($0)) })
    }

    public static func number(
        _ name: String, _ summary: String, required: Bool = false, min: Double? = nil, max: Double? = nil
    ) -> Param {
        Param(name, .number(min: min, max: max), summary, required: required)
    }

    public static func boolean(_ name: String, _ summary: String, default value: Bool = false) -> Param {
        Param(name, .boolean, summary, default: .bool(value))
    }

    public static func date(_ name: String, _ summary: String, required: Bool = false) -> Param {
        Param(name, .date, summary, required: required)
    }

    public static func choice(
        _ name: String, _ values: [String], _ summary: String, required: Bool = false, default value: String? = nil
    ) -> Param {
        Param(name, .choice(values), summary, required: required, default: value.map(JSONValue.string))
    }

    /// A list parameter. On the CLI it is given by repeating the flag (or several bare values when positional).
    public static func list(
        _ name: String, _ summary: String, of kind: Kind = .string, required: Bool = false, positional: Bool = false
    ) -> Param {
        Param(name, .array(kind), summary, required: required, positional: positional)
    }

    /// `--time-zone` for `timeZone`.
    public var flag: String {
        "--"
            + name.reduce(into: "") { result, character in
                if character.isUppercase {
                    result += "-" + character.lowercased()
                } else {
                    result.append(character)
                }
            }
    }

    var isBoolean: Bool { kind == .boolean }
    var isArray: Bool {
        if case .array = kind { return true }
        return false
    }
}

extension Param.Kind {
    var jsonSchema: [String: JSONValue] {
        switch self {
        case .string: return ["type": "string"]
        case .integer(let min, let max):
            var schema: [String: JSONValue] = ["type": "integer"]
            if let min { schema["minimum"] = .number(Double(min)) }
            if let max { schema["maximum"] = .number(Double(max)) }
            return schema
        case .number(let min, let max):
            var schema: [String: JSONValue] = ["type": "number"]
            if let min { schema["minimum"] = .number(min) }
            if let max { schema["maximum"] = .number(max) }
            return schema
        case .boolean: return ["type": "boolean"]
        case .date:
            return [
                "type": "string",
                "description": "Natural date: today, tomorrow 9:00, friday 18:30, in 2 hours, 2026-11-05T14:00",
            ]
        case .choice(let values): return ["type": "string", "enum": .array(values.map(JSONValue.string))]
        case .array(let item): return ["type": "array", "items": .object(item.jsonSchema)]
        case .object: return ["type": "object"]
        }
    }

    var placeholder: String {
        switch self {
        case .string: "TEXT"
        case .integer: "N"
        case .number: "NUMBER"
        case .boolean: ""
        case .date: "DATE"
        case .choice(let values): values.joined(separator: "|")
        case .array(let item): item.placeholder
        case .object: "JSON"
        }
    }
}

/// Validation and coercion shared by CLI and MCP: unknown keys and missing required parameters
/// are rejected with a hint, strings are coerced to numbers/booleans where declared, a scalar is
/// accepted where a list is expected, and declared defaults are filled in.
enum ParamValidation {
    static func normalize(_ arguments: JSONValue?, params: [Param], operation: String) throws -> JSONValue {
        let object: [String: JSONValue]
        switch arguments {
        case nil, .null?: object = [:]
        case .object(let value)?: object = value
        default: throw AgentError.invalid("Arguments for \(operation) must be a JSON object.")
        }
        var result: [String: JSONValue] = [:]
        let byName = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0) })
        for (key, value) in object {
            guard let param = byName[key] else {
                throw AgentError(
                    code: "invalid_argument", message: "Unknown parameter '\(key)' for \(operation).",
                    hint: "Valid parameters: " + params.map(\.name).joined(separator: ", ") + ".")
            }
            if value == .null { continue }
            result[key] = try coerce(value, to: param.kind, param: param)
        }
        for param in params where result[param.name] == nil {
            if let value = param.defaultValue {
                result[param.name] = value
            } else if param.required {
                throw AgentError.invalid(
                    "Missing required parameter '\(param.name)' for \(operation).",
                    hint: "\(param.name): \(param.summary)")
            }
        }
        return .object(result)
    }

    static func coerce(_ value: JSONValue, to kind: Param.Kind, param: Param) throws -> JSONValue {
        func fail(_ expected: String) -> AgentError {
            AgentError.invalid(
                "Parameter '\(param.name)' expects \(expected), got \(value.compactText()).", hint: param.summary)
        }
        switch (kind, value) {
        case (.string, .string), (.date, .string), (.object, .object): return value
        case (.object, .string(let text)):
            // CLI flags carry objects as JSON text.
            guard let object = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
                object.objectValue != nil
            else { throw fail("a JSON object") }
            return object
        case (.string, .number(let number)), (.date, .number(let number)):
            return .string(number.rounded() == number ? String(Int64(number)) : String(number))
        case (.integer(let min, let max), _):
            let number: Double?
            switch value {
            case .number(let value): number = value
            case .string(let text): number = Double(text.trimmingCharacters(in: .whitespaces))
            default: number = nil
            }
            guard let number, number.rounded() == number else { throw fail("an integer") }
            if let min, Int(number) < min { throw fail("an integer ≥ \(min)") }
            if let max, Int(number) > max { throw fail("an integer ≤ \(max)") }
            return .number(number)
        case (.number(let min, let max), _):
            let number: Double?
            switch value {
            case .number(let value): number = value
            case .string(let text): number = Double(text.trimmingCharacters(in: .whitespaces))
            default: number = nil
            }
            guard let number, number.isFinite else { throw fail("a number") }
            if let min, number < min { throw fail("a number ≥ \(min)") }
            if let max, number > max { throw fail("a number ≤ \(max)") }
            return .number(number)
        case (.boolean, .bool): return value
        case (.boolean, .string(let text)):
            switch text.lowercased() {
            case "true", "yes", "1", "on": return .bool(true)
            case "false", "no", "0", "off": return .bool(false)
            default: throw fail("true or false")
            }
        case (.choice(let values), .string(let text)):
            if let match = values.first(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                return .string(match)
            }
            throw fail("one of " + values.joined(separator: ", "))
        case (.array(let item), .array(let values)):
            return .array(try values.map { try coerce($0, to: item, param: param) })
        case (.array(let item), _):
            return .array([try coerce(value, to: item, param: param)])
        default:
            throw fail(kind.placeholder.isEmpty ? "a boolean" : kind.placeholder.lowercased())
        }
    }

    static func inputSchema(_ params: [Param]) -> JSONValue {
        var properties: [String: JSONValue] = [:]
        // The natural-date grammar is spelled out once per tool; later date parameters refer to it.
        var dateGrammarShown = false
        for param in params {
            var schema = param.kind.jsonSchema
            var extra = schema["description"]?.stringValue.map { " (\($0))" } ?? ""
            if param.kind == .date || param.kind == .array(.date) {
                let grammar = Param.Kind.date.jsonSchema["description"]?.stringValue ?? "natural date"
                extra = dateGrammarShown ? " (natural date)" : " (\(grammar))"
                dateGrammarShown = true
                if case .array = param.kind, var items = schema["items"]?.objectValue {
                    items.removeValue(forKey: "description")
                    schema["items"] = .object(items)
                }
            }
            schema["description"] = .string(param.summary + extra)
            if let value = param.defaultValue, value != .bool(false) { schema["default"] = value }
            properties[param.name] = .object(schema)
        }
        var schema: [String: JSONValue] = [
            "type": "object", "properties": .object(properties), "additionalProperties": false,
        ]
        let required = params.filter(\.required).map { JSONValue.string($0.name) }
        if !required.isEmpty { schema["required"] = .array(required) }
        return .object(schema)
    }
}
