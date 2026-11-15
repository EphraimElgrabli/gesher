import GesherPlatform
import Foundation

/// Converts CLI arguments to the same JSON object an MCP client would send.
///
/// - `--name value`, `--name=value`, camelCase or kebab-case names
/// - booleans: `--flag`, `--no-flag`, `--flag=false`
/// - lists: repeat the flag (`--id a --id b`), or several bare values for a positional list
/// - bare values fill the operation's positional parameter
/// - `--json '{...}'` or `--input FILE|-` supplies the whole object (flags given too override it)
/// - `--` ends flag parsing; negative numbers are values, not flags
enum CLIArguments {
    static func parse(_ args: [String], params: [Param], operation: String) throws -> JSONValue {
        var object: [String: JSONValue] = [:]
        let positional = params.first(where: \.positional)
        var index = 0
        var flagsEnded = false

        func param(named raw: String) throws -> Param {
            if let match = params.first(where: { $0.flag == "--" + raw || $0.name == raw }) { return match }
            let suggestion = params.min {
                NameMatcher.distance(raw, String($0.flag.dropFirst(2)))
                    < NameMatcher.distance(raw, String($1.flag.dropFirst(2)))
            }
            throw AgentError(
                code: "invalid_argument", message: "Unknown option --\(raw) for \(operation).",
                hint: (suggestion.map { "Did you mean \($0.flag)? " } ?? "") + "Options: "
                    + params.map(\.flag).joined(separator: " "))
        }

        func assign(_ param: Param, _ value: JSONValue) throws {
            if param.isArray {
                if case .array(let existing)? = object[param.name] {
                    object[param.name] = .array(existing + [value])
                } else {
                    object[param.name] = .array([value])
                }
            } else if object[param.name] != nil {
                throw AgentError.invalid("\(param.flag) was given more than once.", hint: param.summary)
            } else {
                object[param.name] = value
            }
        }

        while index < args.count {
            let token = args[index]
            index += 1
            if flagsEnded || !token.hasPrefix("--") || Double(token) != nil {
                if token == "--" && !flagsEnded {
                    flagsEnded = true
                    continue
                }
                guard let positional else {
                    throw AgentError.invalid(
                        "Unexpected argument '\(token)' for \(operation).",
                        hint: "Options: " + params.map(\.flag).joined(separator: " "))
                }
                try assign(positional, .string(token))
                continue
            }
            var name = String(token.dropFirst(2))
            var inline: String?
            if let equals = name.firstIndex(of: "=") {
                inline = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            if name == "json" || name == "input" {
                guard let text = inline ?? (index < args.count ? args[index] : nil) else {
                    throw AgentError.invalid("--\(name) needs a value.")
                }
                if inline == nil { index += 1 }
                let base = try readJSON(name == "json" ? text : try readFile(text))
                for (key, value) in base where object[key] == nil { object[key] = value }
                continue
            }
            if name.hasPrefix("no-"), inline == nil,
                let negated = params.first(where: { $0.isBoolean && $0.flag == "--" + name.dropFirst(3) })
            {
                try assign(negated, .bool(false))
                continue
            }
            let target = try param(named: name)
            if target.isBoolean, inline == nil {
                if index < args.count, ["true", "false"].contains(args[index].lowercased()) {
                    try assign(target, .string(args[index]))
                    index += 1
                } else {
                    try assign(target, .bool(true))
                }
                continue
            }
            guard let value = inline ?? (index < args.count ? args[index] : nil) else {
                throw AgentError.invalid("\(target.flag) needs a value.", hint: target.summary)
            }
            if inline == nil { index += 1 }
            try assign(target, .string(value))
        }
        return .object(object)
    }

    private static func readFile(_ path: String) throws -> String {
        if path == "-" {
            return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw AgentError.invalid("Cannot read input file \(path).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func readJSON(_ text: String) throws -> [String: JSONValue] {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
            let object = value.objectValue
        else {
            throw AgentError.invalid("Input must be a JSON object.", hint: "Example: --json '{\"name\":\"value\"}'")
        }
        return object
    }
}

extension CLIArguments {
    /// Splits a documented example into words, honoring single and double quotes.
    static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var inWord = false
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if character == " " {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
