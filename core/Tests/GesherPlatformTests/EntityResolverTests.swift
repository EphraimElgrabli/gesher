import XCTest
@testable import GesherPlatform

final class EntityResolverTests: XCTestCase {
    struct Item { let id: String; let title: String }
    let items = [
        Item(id: "a", title: "Shared"), Item(id: "b", title: "Shared"), Item(id: "c", title: "Unique"),
        Item(id: "d", title: "🛒 Shopping List"), Item(id: "e", title: "Café Paris"),
        Item(id: "f", title: "רשימת קניות"), Item(id: "g", title: "Work Projects"), Item(id: "h", title: "Work Ideas"),
    ]

    private func resolve(_ selector: String, policy: MatchPolicy = .fuzzy) throws -> Item {
        try EntityResolver.resolve(selector, in: items, type: "list", id: \.id, name: \.title, policy: policy)
    }

    func testIDAndExactName() throws {
        XCTAssertEqual(try resolve("Unique").id, "c")
        XCTAssertEqual(try resolve("a").id, "a")
        let colliding = try EntityResolver.resolve(
            "a", in: items + [Item(id: "z", title: "a")], type: "list", id: \.id, name: \.title)
        XCTAssertEqual(colliding.id, "a")
    }

    func testCaseDiacriticsEmojiAndPunctuationAreIgnored() throws {
        XCTAssertEqual(try resolve("unique").id, "c")
        XCTAssertEqual(try resolve("cafe paris").id, "e")
        XCTAssertEqual(try resolve("shopping list").id, "d")
        XCTAssertEqual(try resolve("  SHOPPING-list ").id, "d")
    }

    func testHebrewIgnoresNiqqudAndBidiMarks() throws {
        XCTAssertEqual(try resolve("רְשִׁימַת קְנִיּוֹת").id, "f")
        XCTAssertEqual(try resolve("\u{200F}רשימת קניות\u{200F}").id, "f")
        XCTAssertEqual(try resolve("קניות").id, "f")
    }

    func testPrefixAndWords() throws {
        XCTAssertEqual(try resolve("shop").id, "d")
        XCTAssertEqual(try resolve("work proj").id, "g")
    }

    func testAmbiguityListsCandidates() {
        XCTAssertThrowsError(try resolve("Shared")) { error in
            let agent = error as? AgentError
            XCTAssertEqual(agent?.code, "ambiguous")
            XCTAssertEqual(agent?.candidates.map(\.id), ["a", "b"])
            XCTAssertEqual(agent?.exitCode, 64)
        }
        XCTAssertThrowsError(try resolve("work")) { error in
            XCTAssertEqual((error as? AgentError)?.candidates.map(\.id), ["g", "h"])
        }
    }

    func testNotFoundSuggestsAndExactPolicyRefusesFuzzy() {
        XCTAssertThrowsError(try resolve("Uniqeu")) { error in
            let agent = error as? AgentError
            XCTAssertEqual(agent?.code, "not_found")
            XCTAssertEqual(agent?.exitCode, 1)
            XCTAssertFalse(agent?.candidates.isEmpty ?? true)
        }
        XCTAssertThrowsError(try resolve("shop", policy: .exactName))
        XCTAssertEqual(try resolve("shopping list", policy: .exactName).id, "d")
    }

    func testResolveAllCollapsesDuplicates() throws {
        let resolved = try EntityResolver.resolveAll(
            ["Unique", "c", "cafe"], in: items, type: "list", id: \.id, name: \.title)
        XCTAssertEqual(resolved.map(\.id), ["c", "e"])
    }
}
