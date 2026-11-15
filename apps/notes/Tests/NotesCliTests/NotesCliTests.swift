import XCTest
@testable import NotesCore

final class NotesCliTests: XCTestCase {
    func testNoteSnapshotInitialization() {
        let note = NoteSnapshot(
            id: "note-123",
            title: "Meeting Notes",
            snippet: "Discussed project architecture",
            folderID: "folder-456",
            folderTitle: "Work",
            accountID: "iCloud",
            isPasswordProtected: false,
            isPinned: true,
            creationDate: "2026-09-18T10:00:00Z",
            modificationDate: "2026-09-18T11:00:00Z"
        )

        XCTAssertEqual(note.id, "note-123")
        XCTAssertEqual(note.title, "Meeting Notes")
        XCTAssertEqual(note.snippet, "Discussed project architecture")
        XCTAssertEqual(note.folderID, "folder-456")
        XCTAssertEqual(note.folderTitle, "Work")
        XCTAssertTrue(note.isPinned)
        XCTAssertFalse(note.isPasswordProtected)
    }

    func testFolderSnapshotInitialization() {
        let folder = NoteFolderSnapshot(
            id: "folder-1",
            title: "Ideas",
            accountID: "iCloud",
            accountTitle: "Personal iCloud",
            noteCount: 42
        )

        XCTAssertEqual(folder.id, "folder-1")
        XCTAssertEqual(folder.title, "Ideas")
        XCTAssertEqual(folder.noteCount, 42)
    }

    func testNoteMutationProperties() {
        let mutation = NoteMutation(title: "New Title", body: "Sample body text", folderID: "folder-2")
        XCTAssertEqual(mutation.title, "New Title")
        XCTAssertEqual(mutation.body, "Sample body text")
        XCTAssertEqual(mutation.folderID, "folder-2")
    }
}
