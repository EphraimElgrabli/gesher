import CoreData
import Foundation
import GesherKit
import GesherPlatform
import ObjCRuntimeSupport
import XCTest

@testable import NotesCli
@testable import NotesCore

final class NotesTableEditTests: XCTestCase {
    let cells = [["Item", "Packed"], ["Charger", "✓"]]

    func testExpectedCellsForRowsAndColumns() throws {
        XCTAssertEqual(
            try NoteTableEdit.inserting(.row, at: nil, values: ["Passport"], into: cells),
            [["Item", "Packed"], ["Charger", "✓"], ["Passport", ""]])
        XCTAssertEqual(
            try NoteTableEdit.inserting(.row, at: 1, values: ["Tickets", "✓"], into: cells),
            [["Item", "Packed"], ["Tickets", "✓"], ["Charger", "✓"]])
        XCTAssertEqual(
            try NoteTableEdit.inserting(.column, at: 1, values: ["Bag"], into: cells),
            [["Item", "Bag", "Packed"], ["Charger", "", "✓"]])
        XCTAssertEqual(
            try NoteTableEdit.inserting(.column, at: nil, values: [], into: cells),
            [["Item", "Packed", ""], ["Charger", "✓", ""]])
    }

    func testInvalidInsertsAreRefused() {
        XCTAssertThrowsError(try NoteTableEdit.inserting(.row, at: 3, values: [], into: cells))
        XCTAssertThrowsError(try NoteTableEdit.inserting(.row, at: -1, values: [], into: cells))
        XCTAssertThrowsError(try NoteTableEdit.inserting(.row, at: nil, values: ["a", "b", "c"], into: cells))
        XCTAssertThrowsError(try NoteTableEdit.inserting(.row, at: nil, values: [], into: [["a", "b"], ["c"]]))
        let full = Array(repeating: ["a", "b"], count: NoteTableEdit.maxRows)
        XCTAssertThrowsError(try NoteTableEdit.inserting(.row, at: nil, values: [], into: full))
        let wide = [Array(repeating: "a", count: NoteTableEdit.maxColumns)]
        XCTAssertThrowsError(try NoteTableEdit.inserting(.column, at: nil, values: [], into: wide))
    }

    func testOperationsValidateBeforeOpeningNotes() {
        let app = NotesApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
        let tools = Dictionary(uniqueKeysWithValues: app.operations.map { ($0.toolName, $0.effect) })
        XCTAssertEqual(tools["table_add_row"], .write)
        XCTAssertEqual(tools["table_add_column"], .write)
        for args in [
            ["table", "add-row", "x"], ["table", "add-row", "x", "--at", "0", "--if-revision", "r"],
            ["table", "add-column", "x", "--table", "0", "--if-revision", "r"],
        ] {
            XCTAssertEqual(app.run(args, stdout: { _ in }, stderr: { _ in }), 64, "\(args)")
        }
    }

    /// The real Notes table code against an in-memory store: append, insert and add a column,
    /// each verified by reading the note back.
    func testInsertRowsAndColumnsInMemory() throws {
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
        let runtime = NotesRuntime(inMemoryContext: context)
        let read = NotesReadRepository(runtime: runtime)
        let write = NotesWriteRepository(runtime: runtime, readRepository: read)
        let folder = try write.createFolder(
            title: "Fixture", accountID: runtime.objectIDString(from: account as AnyObject))
        let document = NoteDocument(paragraphs: [
            .init(style: .title, runs: [.init(text: "Packing")]),
            .init(style: .body, runs: [], table: cells),
        ])
        let created = try write.createNote(folderID: folder.id, title: "Packing", document: document)
        let table = try XCTUnwrap(created.tables?.first)

        let appended = try write.insertTableLine(
            id: created.id, tableID: table.id, axis: .row, index: nil, values: ["Passport"],
            ifRevision: try XCTUnwrap(created.revision))
        XCTAssertEqual(appended.tables?.first?.cells, [["Item", "Packed"], ["Charger", "✓"], ["Passport", ""]])
        XCTAssertEqual(appended.body, created.body)

        let inserted = try write.insertTableLine(
            id: created.id, tableID: table.id, axis: .row, index: 1, values: ["Tickets", "✓"],
            ifRevision: try XCTUnwrap(appended.revision))
        XCTAssertEqual(inserted.tables?.first?.cells.map(\.first), ["Item", "Tickets", "Charger", "Passport"])

        let widened = try write.insertTableLine(
            id: created.id, tableID: table.id, axis: .column, index: nil, values: ["Bag", "Carry-on"],
            ifRevision: try XCTUnwrap(inserted.revision))
        XCTAssertEqual(
            widened.tables?.first?.cells,
            [["Item", "Packed", "Bag"], ["Tickets", "✓", "Carry-on"], ["Charger", "✓", ""], ["Passport", "", ""]])

        XCTAssertThrowsError(
            try write.insertTableLine(
                id: created.id, tableID: table.id, axis: .row, index: nil, values: [],
                ifRevision: try XCTUnwrap(created.revision))
        ) { XCTAssertEqual(($0 as? AgentError)?.code, "revision_conflict") }
        XCTAssertEqual(try read.fetchNote(id: created.id).tables, widened.tables, "a refused write changes nothing")
        try write.deleteNote(id: created.id)
        try write.deleteFolder(id: folder.id)
    }
}
