import Foundation
import XCTest
import GesherPlatform
@testable import NotesCore

final class NoteDocumentDecoderTests: XCTestCase {
    func testRejectsUnknownFieldsAtEveryLevel() {
        for json in [
            #"{"paragraphs":[],"unexpected":true}"#,
            #"{"paragraphs":[{"style":"body","runs":[],"unknown":1}]}"#,
            #"{"paragraphs":[{"style":"body","runs":[{"text":"hello","unknown":1}]}]}"#,
        ] {
            XCTAssertThrowsError(try NoteDocumentDecoder.decode(from: Data(json.utf8))) { error in
                XCTAssertEqual((error as? PlatformError)?.code, "invalid_argument")
                XCTAssertTrue(error.localizedDescription.contains("Unknown"))
            }
        }
    }
    func testDecodesHebrewTableAndRejectsRaggedGrid() throws {
        let valid = #"{"paragraphs":[{"style":"body","runs":[],"table":[["שם","ערך"],["בדיקה","תקין"]]}]}"#
        XCTAssertEqual(try NoteDocumentDecoder.decode(from: Data(valid.utf8)).paragraphs[0].table?[1][1], "תקין")
        let invalid = #"{"paragraphs":[{"style":"body","runs":[],"table":[["a","b"],["c"]]}]}"#
        XCTAssertThrowsError(try NoteDocumentDecoder.decode(from: Data(invalid.utf8)))
    }
}
