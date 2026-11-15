import Foundation

/// Help text derived from the operation declarations.
enum CLIHelp {
    static func app<Context>(_ app: AgentApp<Context>) -> String {
        let width = (app.operations.map(\.name.count).max() ?? 0) + 2
        var lines = ["\(app.executable) — \(app.summary)", "", "Usage: \(app.executable) <command> [options]", ""]
        lines.append("Commands:")
        for operation in app.operations {
            let tag = operation.effect == .read ? "" : " [\(operation.effect.rawValue)]"
            lines.append(
                "  " + operation.name.padding(toLength: width, withPad: " ", startingAt: 0) + operation.summary + tag)
        }
        lines += [
            "",
            "Built-in:",
            "  mcp                 Serve these commands as MCP tools over stdio",
            "  schema [command]    JSON tool descriptions (same as MCP tools/list)",
            "  --version",
            "",
            "Options for every command:",
            "  --format json|pretty  JSON (default, compact) or human-readable text",
            "  --json '{...}'        Pass all parameters as one JSON object (as MCP would)",
            "  --input FILE|-        Read that JSON object from a file or stdin",
            "",
            "Selectors accept a name (case/accent-insensitive, unique prefix) or an id.",
            "Run '\(app.executable) <command> --help' for parameters and examples.",
        ]
        return lines.joined(separator: "\n")
    }

    static func operation<Context>(_ operation: AnyOperation<Context>, executable: String) -> String {
        let positional = operation.params.first(where: \.positional)
        var usage = "\(executable) \(operation.name)"
        if let positional { usage += positional.required ? " <\(positional.name)>" : " [\(positional.name)]" }
        if operation.params.contains(where: { !$0.positional }) { usage += " [options]" }
        var lines = [operation.summary, "", "Usage: \(usage)"]
        if !operation.params.isEmpty {
            lines += ["", "Parameters:"]
            let labels = operation.params.map { param -> String in
                let placeholder = param.kind.placeholder
                return param.flag + (placeholder.isEmpty ? "" : " \(placeholder)")
            }
            let width = (labels.map(\.count).max() ?? 0) + 2
            for (param, label) in zip(operation.params, labels) {
                var notes: [String] = []
                if param.required { notes.append("required") }
                if param.positional { notes.append("or bare value") }
                if param.isArray { notes.append("repeatable") }
                if let value = param.defaultValue, value != .bool(false) {
                    notes.append("default \(value.stringValue ?? value.compactText())")
                }
                let suffix = notes.isEmpty ? "" : " (\(notes.joined(separator: ", ")))"
                lines.append(
                    "  " + label.padding(toLength: width, withPad: " ", startingAt: 0) + param.summary + suffix)
            }
        }
        if !operation.examples.isEmpty {
            lines += ["", "Examples:"] + operation.examples.map { "  \(executable) \($0)" }
        }
        lines += ["", "Effect: \(operation.effect.rawValue). MCP tool: \(operation.toolName)."]
        return lines.joined(separator: "\n")
    }
}

/// Generic `--format pretty` rendering for outputs without a custom renderer: an indented,
/// YAML-like view of the JSON. Domain operations may override with `pretty(_:)`.
public enum PrettyRenderer {
    public static func render(_ value: JSONValue) -> String {
        var lines: [String] = []
        emit(value, indent: "", into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func scalar(_ value: JSONValue) -> String? {
        switch value {
        case .null: "—"
        case .bool(let value): value ? "yes" : "no"
        case .number: value.compactText()
        case .string(let value): value
        default: nil
        }
    }

    private static func emit(_ value: JSONValue, indent: String, into lines: inout [String]) {
        switch value {
        case .object(let object):
            for key in object.keys.sorted() {
                let child = object[key]!
                if let text = scalar(child) {
                    lines.append("\(indent)\(key): \(text)")
                } else {
                    lines.append("\(indent)\(key):")
                    emit(child, indent: indent + "  ", into: &lines)
                }
            }
        case .array(let items):
            for item in items {
                if let text = scalar(item) {
                    lines.append("\(indent)- \(text)")
                } else {
                    var nested: [String] = []
                    emit(item, indent: indent + "  ", into: &nested)
                    if let first = nested.first {
                        lines.append(indent + "- " + first.dropFirst(indent.count + 2))
                        lines += nested.dropFirst()
                    }
                }
            }
        default:
            lines.append(indent + (scalar(value) ?? ""))
        }
    }
}
