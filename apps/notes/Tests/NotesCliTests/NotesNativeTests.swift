import CoreData
import Foundation
import ObjCRuntimeSupport
import XCTest
@testable import NotesCore

final class NotesNativeTests: XCTestCase {
    func testNativeDocumentSerialization() throws {
        let runtime = NotesRuntime()
        let document = try JSONDecoder().decode(
            NoteDocument.self,
            from: Data(
                #"{"paragraphs":[{"style":"heading","runs":[{"text":"Olive pasta","bold":true,"italic":true,"underline":true}]},{"style":"checklist","checked":true,"runs":[{"text":"Buy olives"}]},{"style":"body","runs":[{"text":"Guide","link":"https://example.com","strikethrough":true}]}]}"#
                    .utf8))
        let text = try document.attributedString(runtime: runtime)
        let cls: AnyClass = try runtime.requireClass("ICTTMergeableAttributedString")
        let allocated = try XCTUnwrap(ObjCAlloc(cls))
        let mergeable = try XCTUnwrap(ObjCSendInitId(allocated, NSSelectorFromString("initWithReplicaID:"), NSUUID()))
        try runtime.replaceText(text, in: mergeable as AnyObject)
        let serialized = try XCTUnwrap(ObjCSendId(mergeable, NSSelectorFromString("serialize")) as? Data)
        let copy = try XCTUnwrap(
            ObjCSendIdId(
                ObjCAlloc(cls)!, NSSelectorFromString("initWithData:replicaID:"), serialized as NSData, NSUUID())
        )
        let restored = try XCTUnwrap(ObjCSendId(copy, NSSelectorFromString("attributedString")) as? NSAttributedString)
        XCTAssertEqual(restored.string, text.string)
        let restoredRuns = NoteTextRun.extract(from: restored, runtime: runtime)
        XCTAssertEqual(restoredRuns.first?.paragraphStyle, 1)
        XCTAssertEqual(restoredRuns.first(where: { $0.text.contains("Buy olives") })?.paragraphStyle, 103)
        XCTAssertEqual(restoredRuns.first(where: { $0.text.contains("Guide") })?.paragraphStyle, 3)
        guard restored.length == text.length else { return }
        XCTAssertEqual(restored.attribute(.init("TTHints"), at: 0, effectiveRange: nil) as? Int, 3)
        XCTAssertEqual(restored.attribute(.init("TTUnderline"), at: 0, effectiveRange: nil) as? Int, 1)
        let checklist = try XCTUnwrap(restored.attribute(.init("TTStyle"), at: 12, effectiveRange: nil))
        XCTAssertTrue(ObjCSendBool(checklist, NSSelectorFromString("isChecklist")))
        let todo = try XCTUnwrap(ObjCSendId(checklist, NSSelectorFromString("todo")))
        XCTAssertTrue(ObjCSendBool(todo, NSSelectorFromString("done")))
    }

    func testInvalidDocumentRejectsLinksAndMultilineRuns() throws {
        for json in [
            #"{"paragraphs":[{"style":"body","runs":[{"text":"bad","link":"javascript:alert(1)"}]}]}"#,
            #"{"paragraphs":[{"style":"body","runs":[{"text":"line\nbreak"}]}]}"#,
            #"{"paragraphs":[]}"#,
        ] {
            let document = try JSONDecoder().decode(NoteDocument.self, from: Data(json.utf8))
            XCTAssertThrowsError(try document.validate())
        }
    }

    func testNativeNoteLifecycleInMemory() throws {
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
        let created = try write.createNote(folderID: folder.id, title: "Test pasta", body: "Olives and lemon")
        XCTAssertEqual(created.body, "Test pasta\nOlives and lemon\n")
        XCTAssertEqual(created.formatting?.first?.paragraphStyle, 0)
        XCTAssertEqual(created.formatting?.first(where: { $0.text.contains("Olives") })?.paragraphStyle, 3)
        let matchingTitle = NoteDocument(paragraphs: [
            .init(style: .title, runs: [.init(text: "Single title")]),
            .init(style: .body, runs: [.init(text: "Content")]),
        ])
        let singleTitle = try write.createNote(folderID: folder.id, title: "Single title", document: matchingTitle)
        XCTAssertEqual(singleTitle.body, "Single title\nContent\n")
        XCTAssertThrowsError(
            try write.createNote(folderID: folder.id, title: "Different title", document: matchingTitle))
        try write.deleteNote(id: singleTitle.id)
        let updated = try write.updateNote(id: created.id, mutation: .init(title: "New title"))
        XCTAssertEqual(updated.body, "New title\nOlives and lemon\n")
        XCTAssertThrowsError(try write.createNote(folderID: "missing-folder", title: "No accidental folder"))
        XCTAssertThrowsError(
            try write.updateNote(id: created.id, mutation: .init(title: "Unsaved", folderID: "missing-folder")))
        XCTAssertEqual(try read.fetchNote(id: created.id).title, "New title")
        let destination = try write.createFolder(title: "Destination", accountID: folder.accountID)
        let moved = try write.updateNote(id: created.id, mutation: .init(folderID: destination.id))
        XCTAssertEqual(moved.folderID, destination.id)
        XCTAssertEqual(moved.body, updated.body)
        let renamedFolder = try write.renameFolder(id: destination.id, title: "Renamed destination")
        XCTAssertEqual(renamedFolder.title, "Renamed destination")
        let rich = try JSONDecoder().decode(
            NoteDocument.self,
            from: Data(
                #"{"paragraphs":[{"style":"heading","runs":[{"text":"Kitchen","highlight":2}]},{"style":"body","runs":[],"table":[["Servings","Pasta"],["2","200 g"]]}]}"#
                    .utf8))
        let withTable = try write.updateNote(id: created.id, mutation: .init(), document: rich)
        XCTAssertTrue(withTable.formatting?.contains { $0.highlight == 2 } ?? false)
        XCTAssertEqual(withTable.tables?.first?.cells, [["Servings", "Pasta"], ["2", "200 g"]])
        let longTitle = String(repeating: "כותרת ארוכה מאוד ", count: 12).trimmingCharacters(in: .whitespaces)
        let longNote = try write.createNote(folderID: folder.id, title: longTitle, document: rich)
        XCTAssertEqual(longNote.title, longTitle)
        let renamedLong = try write.updateNote(
            id: longNote.id, mutation: .init(title: longTitle + " שונה"), ifRevision: longNote.revision)
        XCTAssertEqual(renamedLong.title, longTitle + " שונה")
        XCTAssertEqual(renamedLong.tables, longNote.tables)
        let replacedLongBody = try write.updateNote(id: longNote.id, mutation: .init(body: "תוכן חדש"))
        XCTAssertEqual(replacedLongBody.title, renamedLong.title)
        try write.deleteNote(id: longNote.id)
        let revision = try XCTUnwrap(withTable.revision)
        let appended = try write.appendNote(id: created.id, text: "גבינה", ifRevision: revision)
        XCTAssertEqual(appended.body, (withTable.body ?? "") + "גבינה\n")
        XCTAssertEqual(appended.tables?.first?.cells, withTable.tables?.first?.cells)
        XCTAssertTrue(appended.formatting?.contains { $0.highlight == 2 } ?? false)
        XCTAssertThrowsError(try write.appendNote(id: created.id, text: "stale", ifRevision: revision))
        XCTAssertThrowsError(
            try write.updateNote(id: created.id, mutation: .init(title: "stale"), ifRevision: revision))
        XCTAssertEqual(try read.fetchNote(id: created.id).body, appended.body)
        let summary = try XCTUnwrap(read.fetchNotes(includeBody: false).first { $0.id == created.id })
        XCTAssertNil(summary.body)
        XCTAssertNil(summary.formatting)
        XCTAssertNil(summary.tables)
        XCTAssertNil(summary.revision)
        XCTAssertEqual(try read.fetchNote(id: created.id).body, appended.body)
        let child = try write.createFolder(title: "Subfolder", parentID: destination.id)
        XCTAssertEqual(child.parentID, destination.id)
        try write.deleteFolder(id: child.id)
        let tableID = try XCTUnwrap(withTable.formatting?.compactMap(\.attachmentID).first)
        let attachmentClass: AnyClass = try runtime.requireClass("ICAttachment")
        let attachments = try XCTUnwrap(
            ObjCSendIdIdArg(attachmentClass, NSSelectorFromString("allAttachmentsInContext:"), context) as? [NSObject])
        let attachment = try XCTUnwrap(attachments.first { runtime.objectIDString(from: $0) == tableID })
        let tableModel = try XCTUnwrap(runtime.objectValue(from: attachment, selectors: ["tableModel"]))
        let table = try XCTUnwrap(runtime.objectValue(from: tableModel, selectors: ["table"]))
        let selector = NSSelectorFromString("stringForColumnIndex:rowIndex:")
        let method = try XCTUnwrap(class_getInstanceMethod(type(of: table), selector))
        let cell = unsafeBitCast(
            method_getImplementation(method), to: (@convention(c) (AnyObject, Selector, UInt, UInt) -> AnyObject?).self)
        let savedCell = try XCTUnwrap(cell(table, selector, 1, 1))
        XCTAssertEqual(runtime.stringValue(from: savedCell, selectors: ["string"]), "200 g")
        try write.deleteNote(id: created.id)
        XCTAssertThrowsError(try read.fetchNote(id: created.id))
        try write.deleteFolder(id: destination.id)
        try write.deleteFolder(id: folder.id)
        XCTAssertThrowsError(try read.fetchFolder(id: folder.id))
    }
}
