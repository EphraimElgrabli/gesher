import GesherPlatform
import Foundation

/// A Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0), serving one
/// app's operations as tools. Requests are handled synchronously on the calling (main) thread,
/// which private frameworks such as NotesShared require.
///
/// Implemented: `initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`.
/// Tool failures are results with `isError: true` and a structured `{"error": {...}}`;
/// protocol failures are JSON-RPC errors.
public final class MCPServer<Context> {
    public static var supportedProtocolVersions: [String] { ["2025-06-18", "2025-03-26", "2024-11-05"] }

    private let app: AgentApp<Context>

    public init(app: AgentApp<Context>) { self.app = app }

    /// Serves stdin/stdout until EOF. Anything else that writes to stdout during a tool call
    /// (a stray print, a framework log) is redirected to stderr so it cannot corrupt the stream.
    public func serve() {
        let protocolOutput = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        let handle = FileHandle(fileDescriptor: protocolOutput, closeOnDealloc: true)
        serve(lines: AnyIterator { readLine(strippingNewline: true) }) { line in
            handle.write(Data((line + "\n").utf8))
        }
    }

    public func serve<Lines: Sequence>(lines: Lines, write: (String) -> Void) where Lines.Element == String {
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if let response = handle(line: line) { write(response) }
        }
    }

    /// Handles one incoming line; returns the response line, or nil for notifications.
    public func handle(line: String) -> String? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return Self.error(id: .null, code: -32700, message: "Parse error").compactText()
        }
        if case .array(let batch) = message {
            let responses = batch.compactMap(handle(message:))
            return responses.isEmpty ? nil : JSONValue.array(responses).compactText()
        }
        return handle(message: message)?.compactText()
    }

    func handle(message: JSONValue) -> JSONValue? {
        guard case .object(let object) = message else {
            return Self.error(id: .null, code: -32600, message: "Invalid Request")
        }
        guard case .string(let method)? = object["method"] else { return nil }  // a response; ignore
        guard let id = object["id"] else { return nil }  // a notification
        let params = object["params"]
        switch method {
        case "initialize":
            let requested = params?["protocolVersion"]?.stringValue
            let version =
                requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
                ?? Self.supportedProtocolVersions[0]
            var result: [String: JSONValue] = [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string("gesher-\(app.name)"), "version": .string(Gesher.version)],
            ]
            if !app.instructions.isEmpty { result["instructions"] = .string(app.instructions) }
            return Self.result(id: id, .object(result))
        case "ping":
            return Self.result(id: id, .object([:]))
        case "tools/list":
            return Self.result(id: id, ["tools": .array(app.operations.map(Self.toolDescription))])
        case "tools/call":
            guard case .string(let name)? = params?["name"] else {
                return Self.error(id: id, code: -32602, message: "tools/call requires params.name")
            }
            guard app.operations.contains(where: { $0.toolName == name }) else {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            return Self.result(id: id, callTool(name, arguments: params?["arguments"]))
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func callTool(_ name: String, arguments: JSONValue?) -> JSONValue {
        do {
            let result = try app.call(tool: name, arguments: arguments)
            let structured: JSONValue
            if case .object = result.value {
                structured = result.value
            } else {
                structured = ["items": result.value]
            }
            return [
                "content": [["type": "text", "text": .string(result.value.compactText())]],
                "structuredContent": structured,
                "isError": .bool(result.failed > 0 && result.succeeded == 0),
            ]
        } catch {
            let payload: JSONValue = (try? JSONValue.encode(["error": AgentError.from(error)])) ?? .null
            return [
                "content": [["type": "text", "text": .string(payload.compactText())]],
                "structuredContent": payload, "isError": true,
            ]
        }
    }

    static func toolDescription(_ operation: AnyOperation<Context>) -> JSONValue {
        [
            "name": .string(operation.toolName),
            "description": .string(operation.summary),
            "inputSchema": operation.inputSchema,
            "annotations": [
                "readOnlyHint": .bool(operation.effect == .read),
                "destructiveHint": .bool(operation.effect == .destructive),
                "idempotentHint": .bool(operation.idempotent),
            ],
        ]
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }
}
