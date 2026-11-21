import GesherKit
import GesherPlatform
import Foundation
import SQLite3
import UniformTypeIdentifiers
import XCTest

@testable import FreeformCli
@testable import FreeformCore

// Stand-ins shaped like Coherence's wrappers (matched by type name, as the real ones are).
struct CRRegister<Value> { var ref: CRRegisterRef<Value>? }
final class CRRegisterRef<Value> {
    let _value: Value
    init(_ value: Value) { _value = value }
}
func register<Value>(_ value: Value?) -> CRRegister<Value> { CRRegister(ref: value.map(CRRegisterRef.init)) }

struct FakeBoard {
    var _title: CRRegister<String>
    var rootContainerAffinity: Root
    var boardMetadata: Metadata
    struct Root { var _rootContainerUUID: CRRegister<UUID> }
    struct Metadata { var _creationTime: CRRegister<Double> }
}
struct FakeContainer { var items: [UUID] }
struct FakeCommon {
    var _parentAffinity: CRRegister<Affinity>
    var _locked: CRRegister<Bool>
    struct Affinity { var geometry: Geometry }
    struct Geometry {
        var position: Point
        var size: Size
        var angle: Double
        var widthValid: Bool
        var heightValid: Bool
    }
    struct Point { var x: Double, y: Double }
    struct Size { var width: Double, height: Double }
}
struct FakeLink { var _atomicData: CRRegister<Atomic> }
struct Atomic { var url: URL }
struct FakeSticky {
    var superData: Shape
    struct Shape {
        var superData: Style
        var textStorageCRDTData: Storage
    }
    struct Style { var shapeStyleData: ShapeStyle }
    struct ShapeStyle { var fill: Fill? }
    struct Fill { var color: Color }
    struct Color { var rgbData: RGB }
    struct RGB { var red: Double, green: Double, blue: Double }
    struct Storage { var text: String }
}

/// Maps each blob (its bytes are a key) to a prepared value.
struct FakeDecoder: FreeformRecordDecoding, @unchecked Sendable {
    var values: [String: Any]
    func decode(_ record: FreeformRecord, _ data: Data) -> Reflected? {
        values[String(decoding: data, as: UTF8.self)].map(Reflected.init)
    }
}

/// A synthetic Freeform store in a temporary home directory (never the real one).
final class FixtureStore {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
    let boardID = UUID()
    let rootID = UUID()
    var db: OpaquePointer?
    var values: [String: Any] = [:]

    var database: URL {
        home.appendingPathComponent("Library/Group Containers/group.com.apple.freeform/Boards/boards.db")
    }

    init() throws {
        try FileManager.default.createDirectory(
            at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        let schema = """
            CREATE TABLE boards(board_identifier BLOB PRIMARY KEY, owner_name TEXT, data BLOB, last_activity_time REAL,
              tombstoned INT, tombstone_date REAL, hide_from_recently_deleted INT, parent_identifier BLOB, ckshare_data BLOB);
            CREATE TABLE boards_metadata(board_identifier BLOB PRIMARY KEY, is_favorite INT);
            CREATE TABLE board_items(item_uuid BLOB, parent_uuid BLOB, board_identifier BLOB, item_type INT,
              common_data BLOB, specific_data BLOB, tombstoned INT);
            CREATE TABLE folders(identifier BLOB PRIMARY KEY, data BLOB, title TEXT, parent_identifier BLOB, tombstone INT);
            """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)
        values["board"] = FakeBoard(
            _title: register("QA-gesher-board"), rootContainerAffinity: .init(_rootContainerUUID: register(rootID)),
            boardMetadata: .init(_creationTime: register(700_000_000)))
        insert("INSERT INTO boards VALUES (?, '', CAST('board' AS BLOB), 700000100, 0, 0, 0, NULL, NULL)", [boardID])
        values["deletedBoard"] = FakeBoard(
            _title: register("QA-gesher-old"), rootContainerAffinity: .init(_rootContainerUUID: register(UUID())),
            boardMetadata: .init(_creationTime: register(690_000_000)))
        insert(
            "INSERT INTO boards VALUES (?, '', CAST('deletedBoard' AS BLOB), 700000050, 1, 700000060, 0, NULL, NULL)",
            [UUID()])
        insert("INSERT INTO boards_metadata VALUES (?, 1)", [boardID])
        insert(
            "INSERT INTO board_items VALUES (?, NULL, ?, 2, NULL, CAST('root' AS BLOB), 0)", [rootID, boardID])
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: home)
    }

    func insert(_ sql: String, _ ids: [UUID]) {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK, sql)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, id) in ids.enumerated() {
            let blob = withUnsafeBytes(of: id.uuid) { Data($0) }
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(index + 1), $0.baseAddress, 16, transient) }
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE, sql)
        sqlite3_finalize(statement)
    }

    /// Marks the fixture board as shared by its owner (Freeform stores the CloudKit share).
    func markShared() {
        XCTAssertEqual(sqlite3_exec(db, "UPDATE boards SET ckshare_data = x'00'", nil, nil, nil), SQLITE_OK)
    }

    /// Marks the fixture board as shared with the user by someone else.
    func markSharedWithMe() {
        XCTAssertEqual(
            sqlite3_exec(db, "UPDATE boards SET owner_name = 'QA-gesher-owner', ckshare_data = x'00'", nil, nil, nil),
            SQLITE_OK)
    }

    /// Adds a canvas item the way Freeform stores one (common + specific blobs, listed in the root).
    func addItem(kind: FreeformItemKind, common: FakeCommon, specific: Any) {
        let id = UUID()
        values["common-\(id)"] = common
        values["specific-\(id)"] = specific
        insert(
            "INSERT INTO board_items VALUES (?, ?, ?, \(kind.rawValue), CAST('common-\(id)' AS BLOB), CAST('specific-\(id)' AS BLOB), 0)",
            [id, rootID, boardID])
        let order = (values["root"] as? FakeContainer)?.items ?? []
        values["root"] = FakeContainer(items: order + [id])
    }

    func context(launch: @escaping () throws -> Void = {}) -> FreeformContext {
        let decoder = { [unowned self] in FakeDecoder(values: self.values) as FreeformRecordDecoding }
        return FreeformContext(
            store: FreeformStore(home: home, decoder: decoder), authoringAvailable: { false }, launchApp: launch,
            importTimeout: 2)
    }

    static func common(x: Double, y: Double, width: Double, height: Double) -> FakeCommon {
        FakeCommon(
            _parentAffinity: register(
                .init(
                    geometry: .init(
                        position: .init(x: x, y: y), size: .init(width: width, height: height), angle: 0,
                        widthValid: true, heightValid: true))), _locked: register(nil))
    }
}

final class FreeformCliTests: XCTestCase {
    func run(_ args: [String], _ context: @escaping () throws -> FreeformContext) -> (Int32, JSONValue?, String) {
        var out = ""
        let code = FreeformApp.make(context: context).run(args, stdout: { out = $0 }, stderr: { _ in })
        return (code, try? JSONDecoder().decode(JSONValue.self, from: Data(out.utf8)), out)
    }

    func testExamplesToolNamesAndEffects() {
        let app = FreeformApp.make()
        XCTAssertEqual(app.exampleFailures(), [])
        XCTAssertEqual(
            app.operations.map(\.toolName),
            [
                "doctor", "boards_list", "boards_get", "items_list", "search", "boards_create", "boards_rename",
                "boards_favorite", "boards_delete", "boards_restore", "items_add", "items_add_text", "items_add_shape",
                "items_add_sticky", "items_connect", "items_update", "items_delete", "items_duplicate", "items_group",
                "items_ungroup", "items_align", "diagram_create",
                "permissions",
            ])
        XCTAssertEqual(
            app.operations.filter { $0.effect == .destructive }.map(\.toolName), ["boards_delete", "items_delete"])
    }

    func testReflectedLooksThroughRegistersAndOptionals() {
        let value = Reflected(FixtureStore.common(x: 1.5, y: 2, width: 30, height: 40))
        XCTAssertEqual(value["parentAffinity.geometry.position.x"]?.double, 1.5)
        XCTAssertEqual(value["parentAffinity.geometry.size.height"]?.double, 40)
        XCTAssertNil(value["locked"], "an unset register is absent")
        XCTAssertNil(value["parentAffinity.missing"])
        XCTAssertEqual(Reflected(FakeContainer(items: [UUID(), UUID()]))["items"]?.elements.count, 2)
    }

    func testColorHex() {
        XCTAssertEqual(FreeformColor(red: 1, green: 0.5, blue: 0, alpha: 1).hex, "#FF8000")
        XCTAssertEqual(FreeformColor(red: 0, green: 0, blue: 0, alpha: 0.5).hex, "#00000080")
    }

    /// End to end against a synthetic store: boards list hides Recently Deleted by default, items
    /// list decodes geometry, text, colors, links and stacking order, and the source is unchanged.
    func testBoardsAndItemsFromIsolatedStore() throws {
        let fixture = try FixtureStore()
        fixture.addItem(
            kind: .sticky, common: FixtureStore.common(x: 10, y: 20, width: 200, height: 200),
            specific: FakeSticky(
                superData: .init(
                    superData: .init(
                        shapeStyleData: .init(fill: .init(color: .init(rgbData: .init(red: 1, green: 0.8, blue: 0))))),
                    textStorageCRDTData: .init(text: "QA sticky\n"))))
        fixture.addItem(
            kind: .link, common: FixtureStore.common(x: 300, y: 20, width: 250, height: 150),
            specific: FakeLink(_atomicData: register(Atomic(url: URL(string: "https://www.apple.com/")!))))
        let before = try Data(contentsOf: fixture.database)
        let context = fixture.context()

        let (code, list, out) = run(["boards", "list"], { context })
        XCTAssertEqual(code, 0, out)
        guard case .array(let boards)? = list?["boards"] else { return XCTFail(out) }
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(boards[0]["title"], "QA-gesher-board")
        XCTAssertEqual(boards[0]["favorite"], true)
        XCTAssertEqual(boards[0]["items"], 2)
        XCTAssertNotNil(boards[0]["createdAt"])
        XCTAssertEqual(run(["boards", "list", "--include-deleted"], { context }).1?["boards"]?.arrayValue?.count, 2)

        let (itemsCode, items, itemsOut) = run(["items", "list", "QA-gesher-board"], { context })
        XCTAssertEqual(itemsCode, 0, itemsOut)
        guard case .array(let list2)? = items?["items"], list2.count == 2 else { return XCTFail(itemsOut) }
        XCTAssertEqual(list2[0]["type"], "sticky")
        XCTAssertEqual(list2[0]["text"], "QA sticky")
        XCTAssertEqual(list2[0]["fill"], "#FFCC00")
        XCTAssertEqual(list2[0]["z"], 0)
        XCTAssertEqual(list2[1]["type"], "link")
        XCTAssertEqual(list2[1]["url"], "https://www.apple.com/")
        XCTAssertEqual(list2[1]["x"], 300)
        XCTAssertNil(list2[1]["locked"])
        XCTAssertEqual(
            run(["items", "list", "QA-gesher-board", "--type", "link"], { context }).1?["items"]?.arrayValue?.count,
            1)
        XCTAssertEqual(try Data(contentsOf: fixture.database), before, "the source store is unchanged")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("gesher-freeform-") }
        XCTAssertEqual(leftovers, [], "temporary copies are deleted")
    }

    /// items add writes Freeform's import manifest; a stand-in for Freeform imports it into the
    /// synthetic store, and the operation reads the new item back.
    func testAddItemsWritesManifestAndReadsBack() throws {
        let fixture = try FixtureStore()
        var manifests: [FreeformImporter.Manifest] = []
        let context = fixture.context(launch: {
            let inbox = fixture.home.appendingPathComponent("Library/Group Containers/group.com.apple.freeform/Import")
            for name in try FileManager.default.contentsOfDirectory(atPath: inbox.path) {
                let data = try Data(
                    contentsOf: inbox.appendingPathComponent(name).appendingPathComponent("Manifest.plist"))
                manifests.append(try PropertyListDecoder().decode(FreeformImporter.Manifest.self, from: data))
                try FileManager.default.removeItem(at: inbox.appendingPathComponent(name))
                fixture.addItem(
                    kind: .link, common: FixtureStore.common(x: 0, y: 0, width: 250, height: 150),
                    specific: FakeLink(_atomicData: register(Atomic(url: URL(string: "https://www.apple.com/")!))))
            }
        })
        let (code, json, out) = run(
            ["items", "add", "QA-gesher-board", "--url", "https://www.apple.com/"], { context })
        XCTAssertEqual(code, 0, out)
        XCTAssertEqual(json?["added"]?.arrayValue?.first?["url"], "https://www.apple.com/")
        XCTAssertEqual(manifests.count, 1)
        XCTAssertEqual(manifests.first?.boardUUID, fixture.boardID)
        XCTAssertEqual(manifests.first?.items.first?.url, URL(string: "https://www.apple.com/"))
    }

    /// Files reach everyone on a shared board, so they need the user's explicit confirmation.
    func testFilesToSharedBoardNeedConfirmation() throws {
        let fixture = try FixtureStore()
        fixture.markShared()
        let source = fixture.home.appendingPathComponent("Desktop/qa.png")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        var launches = 0
        let context = fixture.context(launch: {
            launches += 1
            let inbox = fixture.home.appendingPathComponent("Library/Group Containers/group.com.apple.freeform/Import")
            for name in try FileManager.default.contentsOfDirectory(atPath: inbox.path) {
                try FileManager.default.removeItem(at: inbox.appendingPathComponent(name))
                fixture.addItem(
                    kind: .link, common: FixtureStore.common(x: 0, y: 0, width: 100, height: 100),
                    specific: FakeLink(_atomicData: register(Atomic(url: URL(string: "https://www.apple.com/")!))))
            }
        })
        let (refused, json, out) = run(["items", "add", "QA-gesher-board", "--file", source.path], { context })
        XCTAssertEqual(refused, 64, out)
        XCTAssertEqual(json?["error"]?["code"], "confirmation_required")
        XCTAssertEqual(launches, 0, "nothing is handed to Freeform without confirmation")
        // Text needs no confirmation; files do once confirmed.
        let (confirmed, _, confirmedOut) = run(
            ["items", "add", "QA-gesher-board", "--file", source.path, "--confirm-shared"], { context })
        XCTAssertEqual(confirmed, 0, confirmedOut)
        XCTAssertEqual(launches, 1)
    }

    func testHiddenAndCredentialFilesAreRefusedBeforeContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let hidden = root.appendingPathComponent(".ssh/config")
        let key = root.appendingPathComponent("server.pem")
        try FileManager.default.createDirectory(
            at: hidden.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: hidden)
        try Data("x".utf8).write(to: key)
        let noContext: () throws -> FreeformContext = {
            XCTFail("context must not be created")
            throw AgentError.invalid("unexpected")
        }
        for path in [hidden.path, key.path] {
            for args in [
                ["items", "add", "QA-gesher-board", "--file", path], ["boards", "create", "QA", "--file", path],
            ] {
                let (code, json, out) = run(args, noContext)
                XCTAssertEqual(code, 64, out)
                XCTAssertEqual(json?["error"]?["code"], "file_not_allowed")
            }
        }
    }

    func testManifestLayoutMatchesFreeform() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("qa.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        let importer = FreeformImporter(groupContainer: root)
        let id = try importer.submit(
            board: nil, title: "QA-gesher-board", folder: nil,
            contents: [.text("QA"), .link(URL(string: "https://www.apple.com/")!, title: nil), .file(source)])
        let directory = importer.importDirectory.appendingPathComponent(id.uuidString)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: directory.appendingPathComponent("Manifest.plist")), format: nil)
                as? [String: Any])
        XCTAssertEqual(Set(plist.keys), ["title", "items"])
        let items = try XCTUnwrap(plist["items"] as? [[String: Any]])
        XCTAssertEqual(
            items.map { Set($0.keys) },
            [["itemUUID", "attributedText"], ["itemUUID", "url"], ["itemUUID", "title", "url", "mediaUTI"]])
        let manifest = try PropertyListDecoder().decode(
            FreeformImporter.Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("Manifest.plist")))
        let file = try XCTUnwrap(manifest.items.last)
        XCTAssertEqual(file.mediaUTI, .png)
        XCTAssertEqual(file.url?.path, directory.appendingPathComponent(file.itemUUID.uuidString + "/qa.png").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url!.path))
        XCTAssertTrue(importer.isPending(id))
    }

    func testInvalidInputExits64WithoutContext() {
        let noContext: () throws -> FreeformContext = {
            XCTFail("context must not be created")
            throw AgentError.invalid("unexpected")
        }
        for args in [
            ["items", "add", "QA-gesher-board"],
            ["items", "add", "QA-gesher-board", "--url", "file:///etc/hosts"],
            ["items", "add", "QA-gesher-board", "--file", "/nonexistent/QA-gesher"], ["boards", "create", " "],
            ["items", "add", "QA-gesher-board", "--text", " "],
        ] {
            XCTAssertEqual(run(args, noContext).0, 64, args.joined(separator: " "))
        }
    }

    func testMissingStoreIsNotFound() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
        let (code, _, out) = run(["boards", "list"], { FreeformContext(store: FreeformStore(home: home)) })
        XCTAssertEqual(code, 1)
        XCTAssertTrue(out.contains("not_found"))
    }

    /// Read-only: Freeform's model types resolve and conform to Coherence.CRDT on this Mac.
    func testFreeformModelTypesResolve() throws {
        guard FileManager.default.fileExists(atPath: FreeformModelRuntime.appPath) else {
            throw XCTSkip("Freeform is not installed")
        }
        XCTAssertEqual(try FreeformModelRuntime.load().missingTypes(), [])
        XCTAssertNil(try FreeformModelRuntime.load().decode(.board, Data("not a CRDT".utf8)))
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }
}
