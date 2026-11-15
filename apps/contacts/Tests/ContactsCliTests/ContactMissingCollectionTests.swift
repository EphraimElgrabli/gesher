import Foundation
import XCTest
@testable import ContactsCore

private final class ContactCollectionsFixture: NSObject {
    var broken = false
    @objc var givenName: String { "fixture" }
    @objc var familyName: String { "" }
    @objc var phoneNumbers: NSArray { broken ? ["undecodable entry"] : [] }
    @objc var emailAddresses: NSArray { [] }
}

final class ContactMissingCollectionTests: XCTestCase {
    func testMissingCollectionIsNotPresentedAsEmpty() {
        let read = ContactsReadRepository(runtime: ContactsRuntime())
        XCTAssertThrowsError(try read.snapshot(NSObject()))
    }
    func testUndecodableEntryIsNotSilentlyDropped() {
        let read = ContactsReadRepository(runtime: ContactsRuntime())
        let fixture = ContactCollectionsFixture()
        fixture.broken = true
        XCTAssertThrowsError(try read.snapshot(fixture))
    }
    func testDecodedEmptyCollectionsAreKnownEmpty() throws {
        let read = ContactsReadRepository(runtime: ContactsRuntime())
        let value = try read.snapshot(ContactCollectionsFixture())
        XCTAssertEqual(value.phones, [])
        XCTAssertEqual(value.emails, [])
    }
}
