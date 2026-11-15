import GesherPlatform
import XCTest
@testable import GesherKit

final class AgentAppCLITests: XCTestCase {
    private func run(_ app: AgentApp<FixtureStore>, _ args: [String]) -> (code: Int32, out: String, err: String) {
        var out: [String] = []
        var err: [String] = []
        let code = app.run(args, stdout: { out.append($0) }, stderr: { err.append($0) })
        return (code, out.joined(separator: "\n"), err.joined(separator: "\n"))
    }

    func testOperationRunsWithPositionalNameAndCompactJSON() {
        let result = run(makeFixtureApp(), ["item", "get", "groceries"])
        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(result.out, #"{"id":"i-1","name":"Groceries"}"#)
    }

    func testHebrewSelector() {
        XCTAssertEqual(run(makeFixtureApp(), ["item", "get", "קניות"]).out, #"{"id":"i-2","name":"קניות לבית"}"#)
    }

    func testInvalidInputExits64WithHint() throws {
        let result = run(makeFixtureApp(), ["item", "add", "Milk", "--limit", "500"])
        XCTAssertEqual(result.code, 64)
        let error = try JSONDecoder().decode(JSONValue.self, from: Data(result.out.utf8))["error"]
        XCTAssertEqual(error?["code"], "invalid_argument")
        XCTAssertNotNil(error?["hint"])

        let unknown = run(makeFixtureApp(), ["item", "add", "Milk", "--limt", "5"])
        XCTAssertEqual(unknown.code, 64)
        XCTAssertTrue(unknown.out.contains("Did you mean --limit?"))
    }

    func testNotFoundExits1AndUnknownCommandExits64() {
        XCTAssertEqual(run(makeFixtureApp(), ["item", "get", "zzzz"]).code, 1)
        let unknown = run(makeFixtureApp(), ["itme", "list"])
        XCTAssertEqual(unknown.code, 64)
        XCTAssertTrue(unknown.out.contains("unknown_operation"))
    }

    func testBatchPartialFailureExits1ButPrintsAllResults() throws {
        let result = run(makeFixtureApp(), ["item", "add", "Milk", "bad", "Eggs"])
        XCTAssertEqual(result.code, 1)
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(result.out.utf8))
        XCTAssertEqual(value["succeeded"], 2)
        XCTAssertEqual(value["failed"], 1)
    }

    func testJSONInputEqualsFlags() {
        let app = makeFixtureApp()
        let viaJSON = run(app, ["item", "add", "--json", #"{"name":["A"],"dryRun":true}"#])
        let viaFlags = run(app, ["item", "add", "A", "--dry-run"])
        XCTAssertEqual(viaJSON.out, viaFlags.out)
        XCTAssertEqual(run(app, ["item", "list"]).out.components(separatedBy: "\"id\"").count - 1, 2)
    }

    func testObjectParamAcceptsJSONTextFromCLI() throws {
        let param = Param("document", .object, "A JSON object.")
        let value = try ParamValidation.normalize(
            .object(["document": .string(#"{"a":[1]}"#)]), params: [param], operation: "x")
        XCTAssertEqual(value["document"]?["a"], [1])
        XCTAssertThrowsError(
            try ParamValidation.normalize(.object(["document": .string("[1]")]), params: [param], operation: "x"))
    }

    func testPrettyFormatAndHelp() {
        let app = makeFixtureApp()
        let pretty = run(app, ["item", "get", "Groceries", "--format", "pretty"])
        XCTAssertTrue(pretty.out.contains("name: Groceries"))
        let prettyError = run(app, ["--format=pretty", "item", "get", "nothing-here"])
        XCTAssertTrue(prettyError.err.contains("hint:"))
        XCTAssertTrue(run(app, ["--help"]).out.contains("item add"))
        let help = run(app, ["item", "add", "--help"])
        XCTAssertTrue(help.out.contains("--dry-run"))
        XCTAssertTrue(help.out.contains("fixture-cli item add Milk Eggs --limit 5"))
        XCTAssertTrue(run(app, ["schema", "item", "get"]).out.contains(#""name":"item_get""#))
    }

    func testDoctorDoesNotNeedContext() {
        let app = AgentApp<FixtureStore>(
            name: "fixture", summary: "", operations: [],
            context: { throw AgentError(code: "framework_load_failed", message: "no") })
        XCTAssertEqual(run(app, ["doctor"]).code, 0)
    }

    func testValidateRunsBeforeTheContextIsCreated() {
        enum Rename: AgentOperation {
            struct Input: Decodable, Sendable { let name: String? }
            static let path = ["rename"]
            static let summary = "Rename."
            static let params: [Param] = [.string("name", "New name.")]
            static func validate(_ input: Input) throws {
                if input.name == nil { throw AgentError.invalid("Nothing to change.") }
            }
            static func run(_ input: Input, _ store: FixtureStore) throws -> FixtureItem {
                FixtureItem(id: "i-1", name: input.name ?? "")
            }
        }
        var created = 0
        let app = AgentApp<FixtureStore>(
            name: "fixture", summary: "", operations: [AnyOperation(Rename.self)],
            context: {
                created += 1
                return FixtureStore()
            })
        XCTAssertEqual(run(app, ["rename"]).code, 64)
        XCTAssertEqual(created, 0)
        XCTAssertEqual(run(app, ["rename", "--name", "x"]).code, 0)
        XCTAssertEqual(created, 1)
    }

    /// Every documented example must parse and validate against the declared parameters.
    func testExamplesValidate() {
        XCTAssertEqual(makeFixtureApp().exampleFailures(), [])
        XCTAssertEqual(CLIArguments.split(#"a 'b c' "d" ''"#), ["a", "b c", "d", ""])
    }
}
