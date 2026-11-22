import Foundation
@testable import FreeformCore
import GesherKit
import GesherPlatform
import XCTest

@testable import FreeformCli

/// End-to-end native authoring and lifecycle tests against an isolated temporary Freeform store.
/// Never touches the user's real group container or personal boards.
final class FreeformNativeAuthoringTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        guard FreeformNativeBridge.status().isAvailable else {
            throw XCTSkip("Native Freeform authoring is not available on this Freeform build.")
        }
        tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "QA-gesher-native-\(UUID().uuidString)", isDirectory: true)
        let boardsDir = tempHome.appendingPathComponent(
            "Library/Group Containers/group.com.apple.freeform/Boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDir, withIntermediateDirectories: true)
        // Bootstrap an empty native boards.db in the isolated directory using Freeform's own store.
        let bridge = try FreeformNativeBridge.load()
        try bridge.withStore(at: boardsDir) { _ in }
    }

    override func tearDownWithError() throws {
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
    }

    private func makeContext(appRunning: Bool = false) -> FreeformContext {
        let store = FreeformStore(home: tempHome)
        let writer = FreeformWriter(store: store, isAppRunning: { appRunning })
        return FreeformContext(
            store: store,
            writer: writer,
            authoringAvailable: { !appRunning && FreeformNativeBridge.status().isAvailable },
            launchApp: {},
            importTimeout: 1)
    }

    private func run(_ args: [String], appRunning: Bool = false) -> (Int32, JSONValue?, String) {
        let context = makeContext(appRunning: appRunning)
        var out = ""
        let code = FreeformApp.make(context: { context }).run(args, stdout: { out = $0 }, stderr: { _ in })
        return (code, try? JSONDecoder().decode(JSONValue.self, from: Data(out.utf8)), out)
    }

    /// Issue #1 Acceptance Criterion 1: create a board with 5 separately editable nodes at requested
    /// coordinates and 4 bound connectors, read back exact values, edit one node's text/color/position,
    /// delete one node with documented connector behavior, and confirm unrelated items are unchanged.
    func testFiveNodesFourBoundConnectorsEditAndDeleteLifecycle() throws {
        let (createCode, createJSON, createOut) = run(["boards", "create", "QA-gesher-ac1"])
        XCTAssertEqual(createCode, 0, createOut)
        let boardID = try XCTUnwrap(createJSON?["board"]?["id"]?.stringValue)

        // 1. Add 5 separately editable nodes (including Hebrew RTL text) at explicit coordinates.
        let (n1Code, n1JSON, n1Out) = run([
            "items", "add-text", boardID, "--text", "כותרת בעברית", "--x", "100", "--y", "80", "--width", "240",
            "--height", "60",
        ])
        XCTAssertEqual(n1Code, 0, n1Out)
        let n1 = try XCTUnwrap(n1JSON?["item"]?["id"]?.stringValue)
        XCTAssertEqual(n1JSON?["item"]?["type"], "text")
        XCTAssertEqual(n1JSON?["item"]?["text"], "כותרת בעברית")
        XCTAssertEqual(n1JSON?["item"]?["x"], 100)
        XCTAssertEqual(n1JSON?["item"]?["y"], 80)

        let (n2Code, n2JSON, n2Out) = run([
            "items", "add-shape", boardID, "--shape", "rounded_rectangle", "--text", "Service A", "--x", "100", "--y",
            "220", "--width", "220", "--height", "120", "--fill", "#3B82F6",
        ])
        XCTAssertEqual(n2Code, 0, n2Out)
        let n2 = try XCTUnwrap(n2JSON?["item"]?["id"]?.stringValue)
        XCTAssertEqual(n2JSON?["item"]?["type"], "shape")
        XCTAssertEqual(n2JSON?["item"]?["text"], "Service A")
        XCTAssertEqual(n2JSON?["item"]?["fill"], "#3B82F6")

        let (n3Code, n3JSON, n3Out) = run([
            "items", "add-shape", boardID, "--shape", "diamond", "--text", "Valid?", "--x", "420", "--y", "220",
            "--width", "180", "--height", "120", "--fill", "orange",
        ])
        XCTAssertEqual(n3Code, 0, n3Out)
        let n3 = try XCTUnwrap(n3JSON?["item"]?["id"]?.stringValue)

        let (n4Code, n4JSON, n4Out) = run([
            "items", "add-sticky", boardID, "--text", "פתקית עברית", "--x", "700", "--y", "100", "--fill", "yellow",
        ])
        XCTAssertEqual(n4Code, 0, n4Out)
        let n4 = try XCTUnwrap(n4JSON?["item"]?["id"]?.stringValue)
        XCTAssertEqual(n4JSON?["item"]?["type"], "sticky")
        XCTAssertEqual(n4JSON?["item"]?["text"], "פתקית עברית")

        let (n5Code, n5JSON, n5Out) = run([
            "items", "add-shape", boardID, "--shape", "circle", "--text", "Done", "--x", "700", "--y", "340", "--width",
            "140", "--height", "140", "--fill", "green",
        ])
        XCTAssertEqual(n5Code, 0, n5Out)
        let n5 = try XCTUnwrap(n5JSON?["item"]?["id"]?.stringValue)

        // 2. Add 4 bound connectors.
        var connectorIDs: [String] = []
        for (from, to) in [(n1, n2), (n2, n3), (n3, n4), (n3, n5)] {
            let (cCode, cJSON, cOut) = run(["items", "connect", boardID, "--from", from, "--to", to])
            XCTAssertEqual(cCode, 0, cOut)
            XCTAssertEqual(cJSON?["item"]?["type"], "connector")
            XCTAssertEqual(cJSON?["item"]?["from"]?.stringValue, from)
            XCTAssertEqual(cJSON?["item"]?["to"]?.stringValue, to)
            connectorIDs.append(try XCTUnwrap(cJSON?["item"]?["id"]?.stringValue))
        }

        // 3. Read back all 9 items via items list and check pagination.
        let (listCode, listJSON, listOut) = run(["items", "list", boardID])
        XCTAssertEqual(listCode, 0, listOut)
        XCTAssertEqual(listJSON?["total"], 9)
        XCTAssertEqual(listJSON?["items"]?.arrayValue?.count, 9)
        let revisionBeforeEdit = try XCTUnwrap(listJSON?["revision"]?.stringValue)

        let (pageCode, pageJSON, pageOut) = run(["items", "list", boardID, "--limit", "4", "--offset", "2"])
        XCTAssertEqual(pageCode, 0, pageOut)
        XCTAssertEqual(pageJSON?["total"], 9)
        XCTAssertEqual(pageJSON?["offset"], 2)
        XCTAssertEqual(pageJSON?["more"], 3)
        XCTAssertEqual(pageJSON?["items"]?.arrayValue?.count, 4)

        // 4. Update node 2's text, fill color and position with optimistic concurrency check.
        let (updCode, updJSON, updOut) = run([
            "items", "update", boardID, "--item", n2, "--text", "API Gateway", "--fill", "#EF4444", "--x", "150",
            "--y", "260", "--if-revision", revisionBeforeEdit,
        ])
        XCTAssertEqual(updCode, 0, updOut)
        XCTAssertEqual(updJSON?["item"]?["text"], "API Gateway")
        XCTAssertEqual(updJSON?["item"]?["fill"], "#EF4444")
        XCTAssertEqual(updJSON?["item"]?["x"], 150)
        XCTAssertEqual(updJSON?["item"]?["y"], 260)

        // Stale revision must fail cleanly with revision_mismatch.
        let (staleCode, staleJSON, staleOut) = run([
            "items", "update", boardID, "--item", n2, "--x", "999", "--if-revision", revisionBeforeEdit,
        ])
        XCTAssertEqual(staleCode, 1, staleOut)
        XCTAssertEqual(staleJSON?["error"]?["code"], "revision_mismatch")

        // 5. Delete node 4 and verify unrelated items remain intact.
        let (delCode, delJSON, delOut) = run(["items", "delete", boardID, "--item", n4])
        XCTAssertEqual(delCode, 0, delOut)
        XCTAssertEqual(delJSON?["deleted"]?.arrayValue?.first?.stringValue, n4)

        let (afterCode, afterJSON, afterOut) = run(["items", "list", boardID])
        XCTAssertEqual(afterCode, 0, afterOut)
        let remaining = afterJSON?["items"]?.arrayValue ?? []
        XCTAssertFalse(remaining.contains { $0["id"]?.stringValue == n4 })
        let remainingN1 = try XCTUnwrap(remaining.first { $0["id"]?.stringValue == n1 })
        XCTAssertEqual(remainingN1["text"], "כותרת בעברית")
        XCTAssertEqual(remainingN1["x"], 100)
        let remainingN2 = try XCTUnwrap(remaining.first { $0["id"]?.stringValue == n2 })
        XCTAssertEqual(remainingN2["text"], "API Gateway")
        XCTAssertEqual(remainingN2["fill"], "#EF4444")
        let remainingN5 = try XCTUnwrap(remaining.first { $0["id"]?.stringValue == n5 })
        XCTAssertEqual(remainingN5["text"], "Done")
    }

    func testBatchDiagramAutoLayoutAndExplicitCoordinates() throws {
        let (createCode, createJSON, createOut) = run(["boards", "create", "QA-gesher-diagram"])
        XCTAssertEqual(createCode, 0, createOut)
        let boardID = try XCTUnwrap(createJSON?["board"]?["id"]?.stringValue)

        let spec =
            #"{"direction":"left-right","nodes":[{"key":"root","type":"shape","shape":"rounded_rectangle","text":"Start","fill":"blue"},{"key":"a","type":"shape","shape":"diamond","text":"Branch A","fill":"orange"},{"key":"b","type":"sticky","text":"Note B","fill":"yellow"},{"key":"c","type":"text","text":"End"}],"edges":[{"from":"root","to":"a"},{"from":"root","to":"b"},{"from":"a","to":"c"}]}"#
        let (code, json, out) = run(["diagram", "create", boardID, "--spec", spec])
        XCTAssertEqual(code, 0, out)
        let nodes = try XCTUnwrap(json?["nodes"]?.objectValue)
        XCTAssertEqual(nodes.count, 4)
        let edges = try XCTUnwrap(json?["edges"]?.arrayValue)
        XCTAssertEqual(edges.count, 3)

        // Verify left-to-right layered auto-layout placed layer 1 to the right of root (layer 0), and layer 2 to the right of layer 1.
        let rootX = try XCTUnwrap(nodes["root"]?["x"]?.doubleValue)
        let aX = try XCTUnwrap(nodes["a"]?["x"]?.doubleValue)
        let cX = try XCTUnwrap(nodes["c"]?["x"]?.doubleValue)
        XCTAssertLessThan(rootX, aX)
        XCTAssertLessThan(aX, cX)

        // Verify edges are actually bound to the created node IDs.
        let rootID = try XCTUnwrap(nodes["root"]?["id"]?.stringValue)
        let aID = try XCTUnwrap(nodes["a"]?["id"]?.stringValue)
        XCTAssertTrue(edges.contains { $0["from"]?.stringValue == rootID && $0["to"]?.stringValue == aID })
    }

    func testBoardLifecycleRenameFavoriteDeleteRestore() throws {
        let (createCode, createJSON, createOut) = run(["boards", "create", "QA-gesher-life"])
        XCTAssertEqual(createCode, 0, createOut)
        let boardID = try XCTUnwrap(createJSON?["board"]?["id"]?.stringValue)

        let (renCode, renJSON, renOut) = run(["boards", "rename", boardID, "--title", "QA-gesher-renamed"])
        XCTAssertEqual(renCode, 0, renOut)
        XCTAssertEqual(renJSON?["board"]?["title"], "QA-gesher-renamed")

        let (favCode, favJSON, favOut) = run(["boards", "favorite", boardID])
        XCTAssertEqual(favCode, 0, favOut)
        XCTAssertEqual(favJSON?["board"]?["favorite"], true)

        let (unfavCode, unfavJSON, unfavOut) = run(["boards", "favorite", boardID, "--off"])
        XCTAssertEqual(unfavCode, 0, unfavOut)
        XCTAssertEqual(unfavJSON?["board"]?["favorite"], false)

        let (delCode, delJSON, delOut) = run(["boards", "delete", "QA-gesher-renamed"])
        XCTAssertEqual(delCode, 0, delOut)
        XCTAssertEqual(delJSON?["board"]?["deleted"], true)

        let (listActiveCode, listActiveJSON, _) = run(["boards", "list"])
        XCTAssertEqual(listActiveCode, 0)
        XCTAssertFalse((listActiveJSON?["boards"]?.arrayValue ?? []).contains { $0["id"]?.stringValue == boardID })

        let (restCode, restJSON, restOut) = run(["boards", "restore", boardID])
        XCTAssertEqual(restCode, 0, restOut)
        XCTAssertNil(restJSON?["board"]?["deleted"])
    }

    func testLockedProtectionDuplicateGroupUngroupAlignAndAppRunningGuard() throws {
        let (createCode, createJSON, createOut) = run(["boards", "create", "QA-gesher-ops"])
        XCTAssertEqual(createCode, 0, createOut)
        let boardID = try XCTUnwrap(createJSON?["board"]?["id"]?.stringValue)

        let (_, s1JSON, _) = run(["items", "add-shape", boardID, "--text", "One", "--x", "50", "--y", "100"])
        let (_, s2JSON, _) = run(["items", "add-shape", boardID, "--text", "Two", "--x", "350", "--y", "260"])
        let s1 = try XCTUnwrap(s1JSON?["item"]?["id"]?.stringValue)
        let s2 = try XCTUnwrap(s2JSON?["item"]?["id"]?.stringValue)

        // Lock item 1 -> subsequent update or delete must be refused with item_locked until unlocked.
        let (lockCode, lockJSON, lockOut) = run(["items", "update", boardID, "--item", s1, "--locked", "true"])
        XCTAssertEqual(lockCode, 0, lockOut)
        XCTAssertEqual(lockJSON?["item"]?["locked"], true)

        let (blockedUpdCode, blockedUpdJSON, _) = run(["items", "update", boardID, "--item", s1, "--x", "99"])
        XCTAssertEqual(blockedUpdCode, 1)
        XCTAssertEqual(blockedUpdJSON?["error"]?["code"], "item_locked")

        let (blockedDelCode, blockedDelJSON, _) = run(["items", "delete", boardID, "--item", s1])
        XCTAssertEqual(blockedDelCode, 1)
        XCTAssertEqual(blockedDelJSON?["error"]?["code"], "item_locked")

        let (unlockCode, unlockJSON, _) = run(["items", "update", boardID, "--item", s1, "--locked", "false"])
        XCTAssertEqual(unlockCode, 0)
        XCTAssertNil(unlockJSON?["item"]?["locked"])

        // Align top: both items share y == 100.
        let (alignCode, alignJSON, alignOut) = run([
            "items", "align", boardID, "--item", s1, "--item", s2, "--mode", "top",
        ])
        XCTAssertEqual(alignCode, 0, alignOut)
        for item in alignJSON?["items"]?.arrayValue ?? [] {
            XCTAssertEqual(item["y"], 100)
        }

        // Duplicate item 1 with offset.
        let (dupCode, dupJSON, dupOut) = run([
            "items", "duplicate", boardID, "--item", s1, "--dx", "40", "--dy", "60",
        ])
        XCTAssertEqual(dupCode, 0, dupOut)
        XCTAssertEqual(dupJSON?["items"]?.arrayValue?.count, 1)
        XCTAssertEqual(dupJSON?["items"]?.arrayValue?.first?["x"], 90)
        XCTAssertEqual(dupJSON?["items"]?.arrayValue?.first?["y"], 160)

        // Group and ungroup items 1 & 2.
        let (grpCode, grpJSON, grpOut) = run(["items", "group", boardID, "--item", s1, "--item", s2])
        XCTAssertEqual(grpCode, 0, grpOut)
        let groupID = try XCTUnwrap(grpJSON?["item"]?["id"]?.stringValue)
        XCTAssertEqual(grpJSON?["item"]?["type"], "group")

        let (ungrpCode, ungrpJSON, ungrpOut) = run(["items", "ungroup", boardID, "--group", groupID])
        XCTAssertEqual(ungrpCode, 0, ungrpOut)
        XCTAssertEqual(ungrpJSON?["items"]?.arrayValue?.count, 2)

        // Writes while Freeform.app is running must fail cleanly with app_running.
        let (runCode, runJSON, _) = run(
            ["items", "add-text", boardID, "--text", "Blocked"], appRunning: true)
        XCTAssertEqual(runCode, 1)
        XCTAssertEqual(runJSON?["error"]?["code"], "app_running")
    }

    func testTablesDescriptionsReplaceShapeScenesFoldersAndExport() throws {
        let (createCode, createJSON, createOut) = run(["boards", "create", "QA-gesher-p1"])
        XCTAssertEqual(createCode, 0, createOut)
        let boardID = try XCTUnwrap(createJSON?["board"]?["id"]?.stringValue)

        // 1. Add native table (with RTL)
        let (tCode, tJSON, tOut) = run([
            "items", "add-table", boardID, "--rows", "3", "--columns", "4", "--x", "100", "--y", "100", "--rtl",
        ])
        XCTAssertEqual(tCode, 0, tOut)
        XCTAssertEqual(tJSON?["item"]?["type"], "table")

        // 2. Add shape, then replace shape kind & set accessibility description
        let (_, sJSON, _) = run([
            "items", "add-shape", boardID, "--shape", "rectangle", "--text", "Component", "--x", "100", "--y", "380",
            "--fill", "blue",
        ])
        let shapeID = try XCTUnwrap(sJSON?["item"]?["id"]?.stringValue)
        let (updCode, updJSON, updOut) = run([
            "items", "update", boardID, "--item", shapeID, "--shape", "star", "--description", "Core service node",
        ])
        XCTAssertEqual(updCode, 0, updOut)
        XCTAssertEqual(updJSON?["item"]?["description"], "Core service node")

        // 3. Scenes CRUD: create, list, update, delete
        let (scCreateCode, scCreateJSON, scCreateOut) = run([
            "scenes", "create", boardID, "--name", "Overview", "--x", "0", "--y", "0", "--width", "1000", "--height",
            "700",
        ])
        XCTAssertEqual(scCreateCode, 0, scCreateOut)
        let sceneID = try XCTUnwrap(scCreateJSON?["scene"]?["id"]?.stringValue)
        XCTAssertEqual(scCreateJSON?["scene"]?["name"], "Overview")

        let (scListCode, scListJSON, scListOut) = run(["scenes", "list", boardID])
        XCTAssertEqual(scListCode, 0, scListOut)
        XCTAssertEqual(scListJSON?["scenes"]?.arrayValue?.count, 1)

        let (scUpdCode, scUpdJSON, scUpdOut) = run([
            "scenes", "update", boardID, "--scene", sceneID, "--name", "Architecture", "--width", "1400",
        ])
        XCTAssertEqual(scUpdCode, 0, scUpdOut)
        XCTAssertEqual(scUpdJSON?["scene"]?["name"], "Architecture")
        XCTAssertEqual(scUpdJSON?["scene"]?["width"], 1400)

        let (scDelCode, scDelJSON, scDelOut) = run(["scenes", "delete", boardID, "--scene", sceneID])
        XCTAssertEqual(scDelCode, 0, scDelOut)
        XCTAssertEqual(scDelJSON?["deletedScene"]?.stringValue, sceneID)
        let (_, scAfterJSON, _) = run(["scenes", "list", boardID])
        XCTAssertEqual(scAfterJSON?["scenes"]?.arrayValue?.count, 0)

        // 4. Native PDF & PNG export via CRLCanvasImager (works even when appRunning == true!)
        let pdfPath = tempHome.appendingPathComponent("out.pdf").path
        let pngPath = tempHome.appendingPathComponent("out.png").path
        let (pdfCode, pdfJSON, pdfOut) = run(
            ["boards", "export", boardID, "--output", pdfPath, "--kind", "pdf"], appRunning: true)
        XCTAssertEqual(pdfCode, 0, pdfOut)
        XCTAssertGreaterThan(pdfJSON?["bytes"]?.doubleValue ?? 0, 100)
        let pdfBytes = try Data(contentsOf: URL(fileURLWithPath: pdfPath))
        XCTAssertTrue(pdfBytes.starts(with: Array("%PDF-".utf8)))

        let (pngCode, pngJSON, pngOut) = run(
            ["boards", "export", boardID, "--output", pngPath, "--kind", "png"], appRunning: true)
        XCTAssertEqual(pngCode, 0, pngOut)
        XCTAssertGreaterThan(pngJSON?["bytes"]?.doubleValue ?? 0, 100)
        let pngBytes = try Data(contentsOf: URL(fileURLWithPath: pngPath))
        XCTAssertTrue(pngBytes.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        // 5. Folders list returns valid JSON array
        let (fCode, fJSON, fOut) = run(["folders", "list"])
        XCTAssertEqual(fCode, 0, fOut)
        XCTAssertNotNil(fJSON?["folders"]?.arrayValue)
    }
}

private extension JSONValue {
    var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}
