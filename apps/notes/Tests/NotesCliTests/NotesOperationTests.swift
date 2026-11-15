import GesherKit
import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport
import XCTest
@testable import NotesCli
@testable import NotesCore

final class NotesOperationTests: XCTestCase {
    private func appWithoutContext() -> AgentApp<NotesContext> {
        NotesApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
    }

    private func run(_ app: AgentApp<NotesContext>, _ args: [String]) -> (code: Int32, json: JSONValue?) {
        var out: [String] = []
        let code = app.run(args, stdout: { out.append($0) }, stderr: { _ in })
        let text = out.joined(separator: "\n")
        return (code, try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)))
    }

    func testExamplesToolsAndEffects() {
        let app = NotesApp.make()
        XCTAssertEqual(app.exampleFailures(), [])
        let tools = app.operations.map(\.toolName)
        for name in [
            "account_list", "folder_list", "folder_create", "folder_move", "folder_delete", "note_list", "note_get",
            "note_search", "note_create", "note_append", "note_prepend", "note_update", "note_move", "note_pin",
            "note_delete", "note_restore", "checklist_add", "checklist_check", "tag_list", "attachment_list",
            "permissions",
        ] {
            XCTAssertTrue(tools.contains(name), name)
        }
        let effects = Dictionary(app.operations.map { ($0.toolName, $0.effect) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(effects["note_delete"], .destructive)
        XCTAssertEqual(effects["folder_delete"], .destructive)
        XCTAssertEqual(effects["note_update"], .destructive)
        XCTAssertEqual(effects["note_get"], .read)
    }

    func testInvalidInputFailsBeforeOpeningNotes() {
        let app = appWithoutContext()
        XCTAssertEqual(run(app, ["note", "list", "--limit", "0"]).code, 64)
        XCTAssertEqual(run(app, ["note", "get"]).code, 64)
        XCTAssertEqual(run(app, ["note", "get", "x", "--content", "html"]).code, 64)
        XCTAssertEqual(run(app, ["note", "delete"]).code, 64)
        XCTAssertEqual(run(app, ["table", "set-cell", "x", "--row", "1", "--column", "1", "--text", "a"]).code, 64)
        XCTAssertEqual(run(app, ["note", "create", "--document", "[1]"]).code, 64)
        XCTAssertEqual(run(app, ["note", "list", "--folderr", "x"]).code, 64)
        // Hidden, system and credential files are never attached; exports stay out of ~/Library.
        let attach = run(app, ["attachment", "add", "--note", "x", "/etc/hosts"])
        XCTAssertEqual(attach.code, 64)
        XCTAssertEqual(attach.json?["error"]?["code"], "file_not_allowed")
        let export = run(app, ["attachment", "export", "x", "--attachment", "a", "--to", "~/Library/LaunchAgents"])
        XCTAssertEqual(export.code, 64)
        XCTAssertEqual(export.json?["error"]?["code"], "file_not_allowed")
    }

    // MARK: Markdown

    private func content(_ document: NoteDocument) -> NoteContent {
        NoteContent(
            paragraphs: document.paragraphs.map {
                .init(
                    style: $0.style, runs: $0.runs, checked: $0.checked, indent: $0.indent, quote: $0.quote,
                    table: $0.table)
            })
    }

    func testMarkdownRoundTrip() throws {
        let markdown = [
            "## Section", "Plain **bold** and *italic* and ~~gone~~ with [a link](https://example.com).",
            "- bullet", "  - nested", "1. first", "2. second", "- [ ] milk", "- [x] bread", "> quoted", "```",
            "let x = 1", "```", "| שם | כמות |", "| --- | --- |", "| שמן זית | 2 |", "שלום 🧭",
        ].joined(separator: "\n")
        let parsed = try NoteMarkdown.parse(markdown).document
        XCTAssertNoThrow(try parsed.validate())
        XCTAssertEqual(content(parsed).markdown(), markdown)
        let styles = parsed.paragraphs.map(\.style)
        XCTAssertEqual(
            styles,
            [
                .heading, .body, .bullet, .bullet, .numbered, .numbered, .checklist, .checklist, .body, .monospaced,
                .body, .body,
            ])
        XCTAssertEqual(parsed.paragraphs[3].indent, 1)
        XCTAssertEqual(parsed.paragraphs[7].checked, true)
        XCTAssertEqual(parsed.paragraphs[10].table, [["שם", "כמות"], ["שמן זית", "2"]])
        XCTAssertEqual(parsed.paragraphs[1].runs.first(where: { $0.bold == true })?.text, "bold")
        XCTAssertEqual(parsed.paragraphs[1].runs.first(where: { $0.link != nil })?.text, "a link")
    }

    func testMarkdownTitleExtractionAndLiterals() throws {
        let parsed = try NoteMarkdown.parse("\n# Groceries\n\n\nmilk\n", extractTitle: true)
        XCTAssertEqual(parsed.title, "Groceries")
        XCTAssertEqual(parsed.document.paragraphs.map(\.runs.first?.text), ["milk"])
        // Unbalanced markers, snake_case and unsafe links stay literal.
        let runs = NoteMarkdown.inline("2 * 3 = 6, my_var, [x](javascript:alert(1))")
        XCTAssertEqual(runs.map(\.text).joined(), "2 * 3 = 6, my_var, [x](javascript:alert(1))")
        XCTAssertTrue(runs.allSatisfy { $0.italic == nil && $0.link == nil })
        XCTAssertThrowsError(try NoteMarkdown.parse("   \n"))
    }

    func testHashtagsBecomeTagRuns() throws {
        let runs = NoteMarkdown.inline("Trip #travel-2026 and C# or #1 and a#b")
        XCTAssertEqual(runs.filter { $0.tag == true }.map(\.text), ["#travel-2026"])
        XCTAssertEqual(runs.map(\.text).joined(), "Trip #travel-2026 and C# or #1 and a#b")
        XCTAssertEqual(NoteMarkdown.inline("\\#literal").first?.tag, nil)
        XCTAssertEqual(
            content(NoteDocument(paragraphs: [.init(style: .body, runs: runs)])).markdown(),
            "Trip #travel-2026 and C# or #1 and a#b")
        XCTAssertTrue(NoteMarkdown.isTagName("ideas_2"))
        XCTAssertFalse(NoteMarkdown.isTagName("2ideas"))
        XCTAssertThrowsError(
            try NoteDocument(paragraphs: [.init(style: .body, runs: [.init(text: "a b", tag: true)])]).validate())
    }

    func testPlainTextRendering() throws {
        let parsed = try NoteMarkdown.parse("- a\n1. b\n- [x] c\n| a | b |\n|---|---|\n| 1 | 2 |").document
        XCTAssertEqual(content(parsed).plainText(), "• a\n1. b\n[x] c\na | b\n1 | 2")
    }

    // MARK: Output

    func testCompactOutputOmitsInternalFields() throws {
        let summary = NoteSummarySnapshot(
            id: "n1", title: "Fixture", snippet: " ", folderID: "f1", folderTitle: "Notes", accountID: "a1",
            isLocked: false, isPinned: false, isInRecentlyDeleted: false, creationDate: nil,
            modificationDate: Date(timeIntervalSince1970: 0))
        let json = try JSONValue.encode(NoteItem(summary))
        XCTAssertEqual(json["id"], "n1")
        XCTAssertNil(json["accountID"])
        XCTAssertNil(json["folderID"])
        XCTAssertNil(json["pinned"])
        XCTAssertNil(json["snippet"])
        let locked = NoteDetailSnapshot(
            summary: NoteSummarySnapshot(
                id: "n2", title: "Secret", snippet: nil, folderID: "f1", folderTitle: "Notes", accountID: "a1",
                isLocked: true, isPinned: true, isInRecentlyDeleted: false, creationDate: nil, modificationDate: nil),
            title: "Secret", content: nil, revision: nil, tags: [], attachments: [])
        let out = try JSONValue.encode(NoteOut(locked, content: "markdown"))
        XCTAssertEqual(out["locked"], true)
        XCTAssertEqual(out["pinned"], true)
        XCTAssertNil(out["markdown"])
        XCTAssertNil(out["revision"])
    }

    // MARK: Lifecycle (isolated in-memory native store)

    private func inMemoryContext() throws -> NotesContext {
        let loader = NotesRuntime()
        try loader.load()
        let container: AnyClass = try loader.requireClass("ICPersistentContainer")
        let model = try XCTUnwrap(
            ObjCSendId(container, NSSelectorFromString("managedObjectModel")) as? NSManagedObjectModel)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
        let account = NSEntityDescription.insertNewObject(forEntityName: "ICAccount", into: context)
        account.setValue(UUID().uuidString, forKey: "identifier")
        account.setValue("Fixture account", forKey: "name")
        account.setValue(3, forKey: "accountType")
        account.setPrimitiveValue(true, forKey: "didChooseToMigrate")
        if account.responds(to: NSSelectorFromString("createTrashFolder")) {
            ObjCSendVoid(account, NSSelectorFromString("createTrashFolder"))
        }
        try context.save()
        let runtime = NotesRuntime(inMemoryContext: context)
        let read = NotesReadRepository(runtime: runtime)
        return NotesContext(
            runtime: runtime, read: read, write: NotesWriteRepository(runtime: runtime, readRepository: read),
            config: UserConfig(values: [:]))
    }

    func testCLILifecycleInMemory() throws {
        let context = try inMemoryContext()
        let app = NotesApp.make(context: { context })
        func ok(_ args: [String], file: StaticString = #filePath, line: UInt = #line) -> JSONValue {
            let result = run(app, args)
            XCTAssertEqual(result.code, 0, "\(args) -> \(result.json?.compactText() ?? "nil")", file: file, line: line)
            return result.json ?? .null
        }
        let created = ok(["folder", "create", "QA-gesher-notes", "QA-gesher-other"])
        XCTAssertEqual(created["succeeded"], 2)
        let note = ok([
            "note", "create", "# QA-gesher מתכון\n- [ ] olives\n**bold**", "--folder", "QA-gesher-notes",
        ])
        XCTAssertEqual(note["title"], "QA-gesher מתכון")
        let id = try XCTUnwrap(note["id"]?.stringValue)
        XCTAssertEqual(
            ok(["note", "get", "qa gesher מתכון"])["markdown"], "# QA-gesher מתכון\n- [ ] olives\n**bold**")
        let revision = try XCTUnwrap(note["revision"]?.stringValue)
        _ = ok(["note", "append", "--note", id, "tail", "--if-revision", revision])
        XCTAssertEqual(run(app, ["note", "append", "--note", id, "x", "--if-revision", revision]).code, 1)
        _ = ok(["note", "prepend", "--note", id, "## top"])
        let items = ok(["checklist", "add", "--note", id, "lemon", "salt"])
        XCTAssertEqual(items["items"]?.arrayValue?.count, 3)
        let checked = ok(["checklist", "check", "--note", id, "olives", "3"])
        XCTAssertEqual(checked["items"]?.arrayValue?.map { $0["checked"] }, [true, false, true])
        XCTAssertEqual(
            ok(["note", "get", id])["markdown"],
            "# QA-gesher מתכון\n## top\n- [x] olives\n**bold**\ntail\n- [ ] lemon\n- [x] salt")
        XCTAssertEqual(ok(["note", "pin", id])["results"]?[0]?["result"]?["pinned"], true)
        XCTAssertEqual(ok(["note", "list", "--pinned"])["total"], 1)
        let moved = ok(["note", "move", id, "--folder", "QA-gesher-other"])
        XCTAssertEqual(moved["results"]?[0]?["result"]?["folder"], "QA-gesher-other")
        XCTAssertEqual(run(app, ["note", "update", id, "--markdown", "x", "--replace-body"]).code, 64)
        _ = ok(["folder", "move", "QA-gesher-other", "--parent", "QA-gesher-notes"])
        let folders = ok(["folder", "list"])["folders"]?.arrayValue ?? []
        XCTAssertTrue(folders.contains { $0["path"] == "QA-gesher-notes/QA-gesher-other" })
        let deleted = ok(["note", "delete", id])
        let trashed = deleted["results"]?[0]?["result"]?["deleted"]?.stringValue
        if trashed == "recently_deleted" {
            XCTAssertEqual(ok(["note", "list", "--recently-deleted"])["total"], 1)
            _ = ok(["note", "restore", id, "--folder", "QA-gesher-notes"])
            _ = ok(["note", "delete", id])
            _ = ok(["note", "delete", id, "--permanent"])
        }
        XCTAssertEqual(run(app, ["note", "get", id]).code, 1)
        XCTAssertEqual(run(app, ["folder", "delete", "QA-gesher-notes"]).code, 1)  // has a subfolder
        _ = ok(["folder", "delete", "QA-gesher-notes/QA-gesher-other"])
        _ = ok(["folder", "delete", "QA-gesher-notes"])
        XCTAssertEqual(ok(["note", "list"])["total"], 0)
    }
}

extension JSONValue {
    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    fileprivate subscript(index: Int) -> JSONValue? {
        guard let values = arrayValue, values.indices.contains(index) else { return nil }
        return values[index]
    }
}
