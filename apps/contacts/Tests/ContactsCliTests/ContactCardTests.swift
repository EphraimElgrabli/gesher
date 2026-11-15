import GesherKit
import GesherPlatform
import XCTest

@testable import ContactsCli
@testable import ContactsCore

/// Card operations' validation and the pure helpers behind them (no store involved).
final class ContactCardTests: XCTestCase {
    func run(_ args: [String]) -> (Int32, String) {
        var output = ""
        let app = ContactsApp.make(context: { throw AgentError.invalid("context must not be created") })
        let code = app.run(args, stdout: { output += $0 }, stderr: { _ in })
        return (code, output)
    }

    func testCardOperationsValidateBeforeTheStore() {
        XCTAssertEqual(run(["photo", "Fixture"]).0, 64)  // neither --file nor --clear
        XCTAssertEqual(run(["photo", "Fixture", "--file", "a.png", "--clear"]).0, 64)
        XCTAssertEqual(run(["link", "Fixture"]).0, 64)  // one contact
        XCTAssertEqual(run(["me", "set"]).0, 64)  // missing contact
    }

    func testImageSnifferAcceptsImagesOnly() {
        XCTAssertTrue(ImageSniffer.isImage(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])))
        XCTAssertTrue(ImageSniffer.isImage(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        XCTAssertTrue(ImageSniffer.isImage(Data([0, 0, 0, 0x18]) + Data("ftypheic".utf8)))
        XCTAssertFalse(ImageSniffer.isImage(Data("BEGIN:VCARD".utf8)))
    }

    func testVCardInputIsSplitPerCard() {
        let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:One\r\nEND:VCARD\r\nBEGIN:VCARD\nFN:Two\nEND:VCARD\n"
        let cards = ContactsWriteRepository.splitCards(Data(text.utf8))
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(String(decoding: cards[1], as: UTF8.self).contains("FN:Two"))
    }

    func testSaveMismatchNamesFieldsNotValues() {
        var a = ContactSnapshot(id: "")
        a.givenName = "Fixture"
        var b = a
        b.jobTitle = "Other"
        XCTAssertEqual(ContactsWriteRepository.differingFields(a, b), ["jobTitle"])
    }
}
