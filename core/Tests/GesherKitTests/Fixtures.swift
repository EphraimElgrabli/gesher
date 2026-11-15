import GesherPlatform
@testable import GesherKit

/// A tiny in-memory app used to exercise the CLI and MCP front ends.
final class FixtureStore {
    var items = [FixtureItem(id: "i-1", name: "Groceries"), FixtureItem(id: "i-2", name: "קניות לבית")]
}

struct FixtureItem: Codable, Sendable, Equatable {
    let id: String
    let name: String
    var note: String?
}

enum ListItems: AgentOperation {
    struct Output: Encodable, Sendable { let items: [FixtureItem] }
    static let path = ["item", "list"]
    static let summary = "List items."
    static let params: [Param] = []
    static func run(_ input: NoInput, _ store: FixtureStore) throws -> Output { Output(items: store.items) }
}

enum GetItem: AgentOperation {
    struct Input: Decodable, Sendable { let item: String }
    static let path = ["item", "get"]
    static let summary = "Get one item by name or id."
    static let params: [Param] = [.string("item", "Item name or id.", required: true, positional: true)]
    static let examples = ["item get Groceries"]
    static func run(_ input: Input, _ store: FixtureStore) throws -> FixtureItem {
        try EntityResolver.resolve(input.item, in: store.items, type: "item", id: \.id, name: \.name)
    }
}

enum AddItems: AgentOperation {
    struct Input: Decodable, Sendable {
        let name: [String]
        let limit: Int
        let dryRun: Bool
        let due: NaturalDate?
    }
    static let path = ["item", "add"]
    static let summary = "Add items."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .list("name", "Names to add.", required: true, positional: true),
        .integer("limit", "Maximum to add.", default: 10, min: 1, max: 50),
        .boolean("dryRun", "Validate only."),
        .date("due", "Due date."),
    ]
    static let examples = ["item add Milk Eggs --limit 5", "item add --name Milk --dry-run --due tomorrow"]
    static func run(_ input: Input, _ store: FixtureStore) throws -> BatchResult<FixtureItem> {
        Batch.run(Array(input.name.prefix(input.limit)), label: { $0 }) { name in
            guard !name.isEmpty, name != "bad" else { throw AgentError.invalid("Name '\(name)' is not allowed.") }
            let item = FixtureItem(id: "i-\(store.items.count + 1)", name: name)
            if !input.dryRun { store.items.append(item) }
            return item
        }
    }
}

func makeFixtureApp() -> AgentApp<FixtureStore> {
    let store = FixtureStore()
    return AgentApp(
        name: "fixture", summary: "Fixture app.", instructions: "Use names.",
        operations: [AnyOperation(ListItems.self), AnyOperation(GetItem.self), AnyOperation(AddItems.self)],
        context: { store })
}
