import GesherPlatform
import XCTest
@testable import ContactsCore

/// Runs against the private in-memory ABCNContactStore: no user data is read or written.
final class ContactsCoreLifecycleTests: XCTestCase {
    static func memoryRepositories() throws -> (ContactsReadRepository, ContactsWriteRepository) {
        try ContactsRuntime().load()
        let storeClass: AnyClass = try DynamicRuntime.shared.requireClass("ABCNContactStore")
        let store = try DynamicRuntime.shared.requireObject(
            storeClass as AnyObject, selector: "memoryBackedContactStore")
        let runtime = ContactsRuntime(mapperFactory: { store })
        let read = ContactsReadRepository(runtime: runtime)
        return (read, ContactsWriteRepository(runtime: runtime, readRepository: read))
    }

    func testFullContactLifecycle() throws {
        let (read, write) = try Self.memoryRepositories()
        var draft = ContactSnapshot(id: "")
        draft.givenName = "Fixture"
        draft.familyName = "Example"
        draft.nickname = "Fix"
        draft.organization = "Example Org"
        draft.jobTitle = "Tester"
        draft.department = "QA"
        draft.birthday = ContactDay(year: 1990, month: 5, day: 17)
        draft.note = "In-memory only"
        draft.phones = [LabeledText(label: ContactLabel.native("mobile"), value: "+1 555 000 1234")]
        draft.emails = [LabeledText(label: ContactLabel.native("work"), value: "fixture@example.invalid")]
        draft.urls = [LabeledText(label: ContactLabel.native("homepage"), value: "https://example.invalid")]
        draft.addresses = [
            PostalAddress(
                label: ContactLabel.native("home"), street: "1 Example St", city: "Example City", postalCode: "00000",
                country: "Exampleland")
        ]
        draft.dates = [LabeledDay(label: ContactLabel.native("anniversary"), day: ContactDay(month: 6, day: 1))]
        draft.relations = [LabeledText(label: ContactLabel.native("friend"), value: "Other Fixture")]
        draft.socialProfiles = [SocialProfile(service: "Twitter", username: "fixture")]
        let group = try write.createGroup(name: "Fixture Group")
        let created = try write.createContact(draft)
        XCTAssertEqual(
            created.editable,
            {
                var d = draft; d.id = ""; return d.editable
            }())

        var edit = ContactEdit()
        edit.fields[.nickname] = ""
        edit.phones.add = [LabeledText(label: ContactLabel.native("work"), value: "+1 555 000 9999")]
        edit.phones.remove = ["15550001234"]
        edit.emails.add = [LabeledText(label: ContactLabel.native("home"), value: "second@example.invalid")]
        edit.birthday = .some(nil)
        let updated = try write.updateContact(id: created.id, edit: edit)
        XCTAssertEqual(updated.phones.map(\.value), ["+1 555 000 9999"])
        XCTAssertEqual(updated.emails.count, 2)
        XCTAssertNil(updated.birthday)
        XCTAssertEqual(updated.nickname, "")

        let vcard = try write.vCard(ids: [created.id])
        let parsed = try write.parseVCard(vcard)
        XCTAssertEqual(parsed.count, 1)
        let imported = try write.importContact(parsed[0])
        XCTAssertNotEqual(imported.id, created.id)
        XCTAssertEqual(imported.phones, updated.phones)
        XCTAssertNil(try read.meContactID())
        XCTAssertEqual(try write.renameGroup(id: group.id, name: "Fixture Renamed").name, "Fixture Renamed")
        try write.deleteContact(id: created.id)
        try write.deleteContact(id: imported.id)
        try write.deleteGroup(id: group.id)
        XCTAssertEqual(try read.fetchContacts().count, 0)
    }
}
