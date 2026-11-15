import Foundation

/// Output of an operation that acts on many items. Items are processed independently: one
/// failure does not stop the others, and each failure carries its own error and hint.
public struct BatchResult<Item: Encodable & Sendable>: Encodable, Sendable, PartialFailureReporting {
    public struct Entry: Encodable, Sendable {
        public let input: String
        public let result: Item?
        public let error: AgentError?
    }

    public let results: [Entry]
    public let succeeded: Int
    public let failed: Int

    public init(results: [Entry]) {
        self.results = results
        self.succeeded = results.filter { $0.error == nil }.count
        self.failed = results.count - succeeded
    }
}

/// Lets the CLI/MCP layer report partial failure (exit 1, `isError` only when nothing succeeded)
/// while still printing every result.
public protocol PartialFailureReporting {
    var succeeded: Int { get }
    var failed: Int { get }
}

public enum Batch {
    public static func run<Input, Item: Encodable & Sendable>(
        _ inputs: [Input], label: (Input) -> String, _ body: (Input) throws -> Item
    ) -> BatchResult<Item> {
        BatchResult(
            results: inputs.map { input in
                do {
                    return .init(input: label(input), result: try body(input), error: nil)
                } catch {
                    return .init(input: label(input), result: nil, error: AgentError.from(error))
                }
            })
    }
}
