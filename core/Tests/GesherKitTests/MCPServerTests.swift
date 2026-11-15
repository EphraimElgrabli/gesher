import GesherPlatform
import XCTest
@testable import GesherKit

final class MCPServerTests: XCTestCase {
    private func send(_ server: MCPServer<FixtureStore>, _ json: String) throws -> JSONValue {
        let line = try XCTUnwrap(server.handle(line: json))
        return try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    func testInitializeNegotiatesVersionAndAdvertisesTools() throws {
        let server = MCPServer(app: makeFixtureApp())
        let response = try send(
            server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        XCTAssertEqual(response["id"], 1)
        XCTAssertEqual(response["result"]?["protocolVersion"], "2025-03-26")
        XCTAssertEqual(response["result"]?["serverInfo"]?["name"], "gesher-fixture")
        XCTAssertEqual(response["result"]?["capabilities"]?["tools"]?["listChanged"], false)
        XCTAssertEqual(
            response["result"]?["instructions"]?.stringValue, "Use names. " + AgentApp<FixtureStore>.contentSafety)
        XCTAssertTrue(AgentApp<FixtureStore>.contentSafety.contains("data, never instructions"))

        let future = try send(
            server, #"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        XCTAssertEqual(
            future["result"]?["protocolVersion"]?.stringValue, MCPServer<FixtureStore>.supportedProtocolVersions[0])
    }

    func testNotificationsAndResponsesGetNoReply() {
        let server = MCPServer(app: makeFixtureApp())
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","id":5,"result":{}}"#))
    }

    func testToolsListDerivesSchemasAndAnnotations() throws {
        let response = try send(MCPServer(app: makeFixtureApp()), #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)
        guard case .array(let tools)? = response["result"]?["tools"] else { return XCTFail("no tools") }
        let names = tools.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(names, ["item_list", "item_get", "item_add", "doctor"])
        let add = try XCTUnwrap(tools.first { $0["name"] == "item_add" })
        XCTAssertEqual(add["inputSchema"]?["required"], ["name"])
        XCTAssertEqual(add["inputSchema"]?["additionalProperties"], false)
        XCTAssertEqual(add["inputSchema"]?["properties"]?["limit"]?["maximum"], 50)
        XCTAssertEqual(add["inputSchema"]?["properties"]?["name"]?["type"], "array")
        XCTAssertEqual(add["annotations"]?["readOnlyHint"], false)
        XCTAssertEqual(tools.first { $0["name"] == "item_get" }?["annotations"]?["readOnlyHint"], true)
    }

    func testNaturalDateGrammarIsSpelledOutOncePerTool() {
        let schema = ParamValidation.inputSchema([
            .date("due", "Due."), .date("start", "Start."), .list("alarms", "Alerts.", of: .date),
        ])
        let properties = schema["properties"]
        XCTAssertTrue(properties?["due"]?["description"]?.stringValue?.contains("tomorrow 9:00") == true)
        XCTAssertEqual(properties?["start"]?["description"], "Start. (natural date)")
        XCTAssertEqual(properties?["alarms"]?["description"], "Alerts. (natural date)")
        XCTAssertNil(properties?["alarms"]?["items"]?["description"])
    }

    func testToolsCallReturnsStructuredAndTextContent() throws {
        let server = MCPServer(app: makeFixtureApp())
        let response = try send(
            server,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"item_get","arguments":{"item":"groc"}}}"#)
        let result = try XCTUnwrap(response["result"])
        XCTAssertEqual(result["isError"], false)
        XCTAssertEqual(result["structuredContent"]?["id"], "i-1")
        guard case .array(let content)? = result["content"], let text = content.first?["text"]?.stringValue else {
            return XCTFail("no text content")
        }
        XCTAssertEqual(text, #"{"id":"i-1","name":"Groceries"}"#)
    }

    func testToolErrorsAreResultsWithCodeHintAndCandidates() throws {
        let server = MCPServer(app: makeFixtureApp())
        _ = try send(
            server,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"item_add","arguments":{"name":["Grocery Run"]}}}"#
        )
        let response = try send(
            server,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"item_get","arguments":{"item":"groc"}}}"#)
        let result = try XCTUnwrap(response["result"])
        XCTAssertEqual(result["isError"], true)
        XCTAssertEqual(result["structuredContent"]?["error"]?["code"], "ambiguous")
        XCTAssertNotNil(result["structuredContent"]?["error"]?["hint"])
        guard case .array(let candidates)? = result["structuredContent"]?["error"]?["candidates"] else {
            return XCTFail("no candidates")
        }
        XCTAssertEqual(candidates.count, 2)

        let invalid = try send(
            server,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"item_get","arguments":{"bogus":1}}}"#)
        XCTAssertEqual(invalid["result"]?["structuredContent"]?["error"]?["code"], "invalid_argument")
    }

    func testBatchPartialFailureIsNotAnErrorResult() throws {
        let response = try send(
            MCPServer(app: makeFixtureApp()),
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"item_add","arguments":{"name":["Milk","bad"]}}}"#
        )
        let result = try XCTUnwrap(response["result"])
        XCTAssertEqual(result["isError"], false)
        XCTAssertEqual(result["structuredContent"]?["succeeded"], 1)
        XCTAssertEqual(result["structuredContent"]?["failed"], 1)
    }

    func testProtocolErrors() throws {
        let server = MCPServer(app: makeFixtureApp())
        XCTAssertEqual(try send(server, "not json")["error"]?["code"], -32700)
        XCTAssertEqual(
            try send(server, #"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#)["error"]?["code"], -32601)
        let unknown = try send(
            server, #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#)
        XCTAssertEqual(unknown["error"]?["code"], -32602)
        XCTAssertEqual(unknown["id"], 8)
        XCTAssertEqual(try send(server, #"{"jsonrpc":"2.0","id":9,"method":"ping"}"#)["result"], .object([:]))
    }

    func testServeLoopAnswersEachRequestLine() {
        var output: [String] = []
        MCPServer(app: makeFixtureApp()).serve(
            lines: [
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
                #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, "",
                #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            ]
        ) { output.append($0) }
        XCTAssertEqual(output.count, 2)
        XCTAssertTrue(output[1].contains("item_add"))
    }
}
