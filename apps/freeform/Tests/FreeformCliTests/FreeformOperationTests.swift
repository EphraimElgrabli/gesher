import GesherKit
import GesherPlatform
import Foundation
import XCTest

@testable import FreeformCli
@testable import FreeformCore

/// Search and error paths against the synthetic store (never the user's boards).
final class FreeformOperationTests: XCTestCase {
    func run(_ args: [String], _ context: @escaping () throws -> FreeformContext) -> (Int32, JSONValue?, String) {
        var out = ""
        let code = FreeformApp.make(context: context).run(args, stdout: { out = $0 }, stderr: { _ in })
        return (code, try? JSONDecoder().decode(JSONValue.self, from: Data(out.utf8)), out)
    }

    func fixtureWithContent() throws -> FixtureStore {
        let fixture = try FixtureStore()
        fixture.addItem(
            kind: .sticky, common: FixtureStore.common(x: 10, y: 20, width: 200, height: 200),
            specific: FakeSticky(
                superData: .init(
                    superData: .init(
                        shapeStyleData: .init(fill: .init(color: .init(rgbData: .init(red: 1, green: 0.8, blue: 0))))),
                    textStorageCRDTData: .init(text: "Pack the Café list\n"))))
        fixture.addItem(
            kind: .link, common: FixtureStore.common(x: 300, y: 20, width: 250, height: 150),
            specific: FakeLink(_atomicData: register(Atomic(url: URL(string: "https://www.apple.com/")!))))
        return fixture
    }

    func testSearchMatchesWordsIgnoringCaseAndAccents() throws {
        let fixture = try fixtureWithContent()
        let context = fixture.context()
        let (code, json, out) = run(["search", "cafe PACK"], { context })
        XCTAssertEqual(code, 0, out)
        let items = json?["items"]?.arrayValue ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?["title"], "QA-gesher-board")
        XCTAssertEqual(items.first?["board"]?.stringValue, fixture.boardID.uuidString)
        XCTAssertEqual(items.first?["item"]?["type"], "sticky")
        XCTAssertEqual(json?["boards"]?.arrayValue?.count, 0)
        XCTAssertNil(json?["more"])

        XCTAssertEqual(
            run(["search", "apple.com"], { context }).1?["items"]?.arrayValue?.first?["item"]?["type"], "link")
        XCTAssertEqual(run(["search", "cafe", "--type", "link"], { context }).1?["items"]?.arrayValue?.count, 0)
        XCTAssertEqual(run(["search", "gesher board"], { context }).1?["boards"]?.arrayValue?.count, 1)
        let none = run(["search", "nothing here"], { context })
        XCTAssertEqual(none.0, 0, "no match is an empty result, not an error")
        XCTAssertEqual(none.1?["items"]?.arrayValue?.count, 0)
    }

    func testSearchLimitReportsTheRest() throws {
        let fixture = try fixtureWithContent()
        let context = fixture.context()
        // "a" appears in both items (the sticky's text and the link's URL): one is returned, one is left.
        let (code, json, out) = run(["search", "a", "--limit", "1"], { context })
        XCTAssertEqual(code, 0, out)
        XCTAssertEqual(json?["items"]?.arrayValue?.count, 1)
        XCTAssertEqual(json?["more"], 1)
    }

    func testSearchWithoutWordsFailsBeforeTheStore() {
        let noContext: () throws -> FreeformContext = {
            XCTFail("context must not be created")
            throw AgentError.invalid("unexpected")
        }
        for args in [
            ["search", "  "], ["search", "!!!"], ["search", "x", "--limit", "0"], ["search", "x", "--type", "x"],
        ] {
            XCTAssertEqual(run(args, noContext).0, 64, args.joined(separator: " "))
        }
    }

    func testUnknownBoardIsNotFoundWithAHint() throws {
        let fixture = try fixtureWithContent()
        let context = fixture.context()
        let (code, json, _) = run(["boards", "get", "No such board"], { context })
        XCTAssertEqual(code, 1)
        XCTAssertEqual(json?["error"]?["code"], "not_found")
        XCTAssertNotNil(json?["error"]?["hint"])
        XCTAssertEqual(run(["items", "add", "No such board", "--text", "x"], { context }).0, 1)
    }

    func testBoardSharedWithYouIsReadOnly() throws {
        let fixture = try fixtureWithContent()
        fixture.markSharedWithMe()
        var launched = false
        let context = fixture.context(launch: { launched = true })
        let (code, json, _) = run(["items", "add", "QA-gesher-board", "--text", "x"], { context })
        XCTAssertEqual(code, 1)
        XCTAssertEqual(json?["error"]?["code"], "read_only")
        XCTAssertFalse(launched)
        XCTAssertEqual(
            run(["boards", "list"], { context }).1?["boards"]?.arrayValue?.first?["shared"], "participant")
    }

    /// When Freeform never takes the import, the write is reported as unverified (read before
    /// retrying), never as success.
    func testUnimportedContentIsNotReportedAsSaved() throws {
        let fixture = try fixtureWithContent()
        let context = FreeformContext(
            store: fixture.context().store, launchApp: {}, importTimeout: 0.3)
        let (code, json, out) = run(["items", "add", "QA-gesher-board", "--text", "QA"], { context })
        XCTAssertEqual(code, 1, out)
        let message = json?["error"]?["message"]?.stringValue ?? ""
        XCTAssertTrue(message.contains("not imported"), message)
        XCTAssertNotNil(json?["error"]?["hint"])
    }
}
