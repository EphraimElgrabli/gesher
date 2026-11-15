import Foundation
import XCTest
@testable import NotesCore

final class NoteParagraphEditTests: XCTestCase {
    func testUTF16RangesAndTrailingNewline() throws {
        let text = "Title\nשלום 🧭\nLast\n" as NSString
        let range = try NoteParagraphEdit.range(in: text, index: 1)
        XCTAssertEqual(text.substring(with: range), "שלום 🧭\n")
        XCTAssertEqual(text.substring(with: try NoteParagraphEdit.range(in: text, index: 2)), "Last\n")
        XCTAssertThrowsError(try NoteParagraphEdit.range(in: text, index: 3))
        XCTAssertThrowsError(try NoteParagraphEdit.range(in: text, index: -1))
    }

    func testEmptyParagraphAndNoFinalNewline() throws {
        let text = "Title\n\nBody" as NSString
        XCTAssertEqual(text.substring(with: try NoteParagraphEdit.range(in: text, index: 1)), "\n")
        XCTAssertEqual(text.substring(with: try NoteParagraphEdit.range(in: text, index: 2)), "Body")
    }
}
