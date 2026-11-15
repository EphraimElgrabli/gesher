import GesherKit
import GesherPlatform
import XCTest

@testable import ContactsCli
@testable import ContactsCore

/// CLI/MCP operations over the private in-memory ABCNContactStore (no user data involved).
final class ContactsOperationTests: XCTestCase {
    var backupDirectory: URL!

    override func setUpWithError() throws {
        backupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contacts-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: backupDirectory)
    }

    func makeApp() throws -> AgentApp<ContactsContext> {
        let (read, write) = try ContactsCoreLifecycleTests.memoryRepositories()
        let directory = backupDirectory!
        let context = ContactsContext(
            runtime: ContactsRuntime(), read: read, write: write, config: UserConfig(values: [:]),
            backupDirectory: directory, now: { DateOutput.parse("2026-05-10T09:00:00Z")! })
        return ContactsApp.make(context: { context })
    }

    @discardableResult
    func run(_ app: AgentApp<ContactsContext>, _ args: [String], exit expected: Int32 = 0) -> JSONValue {
        var output = ""
        let code = app.run(args, stdout: { output += $0 }, stderr: { _ in })
        XCTAssertEqual(code, expected, "\(args): \(output)")
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))) ?? .null
    }

    func testExamplesValidate() {
        XCTAssertEqual(ContactsApp.make().exampleFailures(), [])
    }

    func testInvalidInputExits64WithoutCreatingContext() {
        let app = ContactsApp.make(context: {
            XCTFail("context must not be created")
            throw AgentError.invalid("unreachable")
        })
        for args in [["search"], ["update"], ["birthdays", "--days", "999"], ["create", "--bogus", "x"]] {
            XCTAssertEqual(app.run(args, stdout: { _ in }, stderr: { _ in }), 64, "\(args)")
        }
    }

    func testExportIsAWriteThatRefusesUnsafeFiles() throws {
        let export = try XCTUnwrap(ContactsApp.make().operations.first { $0.toolName == "export" })
        XCTAssertEqual(export.effect, .write)
        XCTAssertFalse(export.params.contains { $0.name == "overwrite" })
        let app = ContactsApp.make(context: {
            XCTFail("context must not be created")
            throw AgentError.invalid("unreachable")
        })
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for args in [
            ["export", "x", "--file", home + "/.zshrc"], ["export", "x", "--file", home + "/Desktop/notes.txt"],
            ["export", "x", "--file", home + "/Library/LaunchAgents/x.vcf"],
            ["export", "x", "--file", home + "/.config/x.vcf"],
        ] {
            XCTAssertEqual(app.run(args, stdout: { _ in }, stderr: { _ in }), 64, "\(args)")
        }
    }

    func testToolNames() {
        let names = Set(ContactsApp.make().operations.map(\.toolName))
        for name in [
            "search", "list", "get", "me", "create", "update", "delete", "birthdays", "duplicates", "export", "import",
            "group_list", "group_create", "group_rename", "group_delete", "group_add", "group_remove",
        ] {
            XCTAssertTrue(names.contains(name), name)
        }
    }

    func testValueParsing() throws {
        XCTAssertEqual(try ValueText.phone("work: +972 4-123-4567").label, "_$!<Work>!$_")
        XCTAssertEqual(try ValueText.phone("054-1234567").label, "_$!<Mobile>!$_")
        XCTAssertEqual(try ValueText.url("https://example.invalid").value, "https://example.invalid")
        XCTAssertEqual(try ValueText.email("עבודה: a@example.invalid").label, "עבודה")
        let address = try ValueText.address("work: 1 Example St, Example City, 12345, Exampleland")
        XCTAssertEqual(
            [address.street, address.city, address.postalCode, address.country],
            ["1 Example St", "Example City", "12345", "Exampleland"])
        XCTAssertEqual(try ValueText.social("https://www.linkedin.com/in/fixture").service, "LinkedIn")
        XCTAssertEqual(try ValueText.date("anniversary: --06-01").day, ContactDay(month: 6, day: 1))
        XCTAssertThrowsError(try ValueText.email("not an email"))
    }

    func testPhoneMatching() {
        XCTAssertTrue(PhoneMatcher.matches("+972 54-123-4567", "054-1234567"))
        XCTAssertTrue(PhoneMatcher.matches("00972541234567", "(054) 123 4567"))
        XCTAssertTrue(PhoneMatcher.matches("+1 (555) 000-1234", "555-000-1234"))
        XCTAssertFalse(PhoneMatcher.matches("054-1234567", "054-1234568"))
        XCTAssertTrue(PhoneMatcher.contains("+972 54-123-4567", query: "1234"))
    }

    func testContactLifecycleThroughCLI() throws {
        let app = try makeApp()
        let created = run(
            app,
            [
                "create", "--first-name", "QA-gesher-Fixture", "--last-name", "Example", "--phone",
                "mobile: +972 54-000-0001", "--email", "work: fixture@example.invalid", "--birthday", "1990-05-17",
                "--related", "spouse: Other Fixture", "--company", "Example Org",
            ])
        let id = try XCTUnwrap(created["id"]?.stringValue)
        XCTAssertEqual(created["phones"]?.arrayValue?.first?["label"]?.stringValue, "mobile")
        XCTAssertNil(created["similar"])

        // Phone selectors in any format, name search, Hebrew-safe normalization.
        XCTAssertEqual(
            run(app, ["get", "054-000-0001"])["results"]?.arrayValue?.first?["result"]?["id"]?.stringValue, id)
        XCTAssertEqual(run(app, ["search", "0540000001"])["total"]?.doubleValue, 1)
        XCTAssertEqual(run(app, ["search", "qa gesher"])["contacts"]?.arrayValue?.count, 1)

        // Add/remove single values without rewriting the rest.
        let updated = run(
            app,
            [
                "update", id, "--add-phone", "work: 04-000-0002", "--remove-phone", "+972540000001", "--add-email",
                "home: second@example.invalid", "--job-title", "Tester",
            ])
        XCTAssertEqual(updated["phones"]?.arrayValue?.map { $0["value"]?.stringValue }, ["04-000-0002"])
        XCTAssertEqual(updated["emails"]?.arrayValue?.count, 2)
        XCTAssertEqual(updated["jobTitle"]?.stringValue, "Tester")
        XCTAssertEqual(updated["related"]?.arrayValue?.first?["label"]?.stringValue, "spouse")
        // A removal that matches nothing changes nothing and is an input error.
        run(app, ["update", id, "--remove-email", "missing@example.invalid", "--nickname", "X"], exit: 64)
        XCTAssertNil(run(app, ["get", id])["results"]?.arrayValue?.first?["result"]?["nickname"])

        // Birthdays: 2026-05-10 is "today" in this context.
        let birthdays = run(app, ["birthdays", "--days", "10"])
        XCTAssertEqual(birthdays["upcoming"]?.arrayValue?.first?["inDays"]?.doubleValue, 7)
        XCTAssertEqual(birthdays["upcoming"]?.arrayValue?.first?["turns"]?.doubleValue, 36)

        // A second card with the same phone is reported as similar, and as a duplicate.
        let twin = run(app, ["create", "--first-name", "QA-gesher-Twin", "--phone", "+972 4 000 0002"])
        XCTAssertEqual(twin["similar"]?.arrayValue?.first?["id"]?.stringValue, id)
        XCTAssertEqual(
            run(app, ["duplicates"])["duplicates"]?.arrayValue?.first?["reasons"], .array([.string("phone")]))

        // vCard round trip: export inline, import skips the existing contact.
        let vcard = try XCTUnwrap(run(app, ["export", id])["vcard"]?.stringValue)
        XCTAssertTrue(vcard.contains("BEGIN:VCARD"))
        // To a file: only new .vcf files, never replacing one.
        let file = backupDirectory.appendingPathComponent("QA-gesher.vcf")
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        XCTAssertEqual(run(app, ["export", id, "--file", file.path])["count"]?.doubleValue, 1)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("BEGIN:VCARD"))
        try Data("keep".utf8).write(to: file)
        run(app, ["export", id, "--file", file.path], exit: 64)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "keep", "an existing file is never replaced")
        let preview = run(app, ["import", "--vcard", vcard, "--dry-run"])
        XCTAssertEqual(preview["preview"]?["existing"]?.arrayValue?.count, 1)
        let skipped = run(app, ["import", "--vcard", vcard], exit: 1)
        XCTAssertEqual(
            skipped["imported"]?["results"]?.arrayValue?.first?["error"]?["code"]?.stringValue, "already_exists")

        // Destructive selectors are exact: a prefix does not delete.
        run(app, ["delete", "QA-apple"], exit: 1)
        let deleted = run(app, ["delete", id, "QA-gesher-Twin"])
        XCTAssertEqual(deleted["succeeded"]?.doubleValue, 2)
        XCTAssertNil(deleted["backup"])
        XCTAssertEqual(run(app, ["list"])["total"]?.doubleValue, 0)
    }

    func testBulkDeleteWritesBackupFirst() throws {
        let app = try makeApp()
        let ids = (1...6).compactMap {
            run(app, ["create", "--first-name", "QA-gesher-Bulk\($0)"])["id"]?.stringValue
        }
        let deleted = run(app, ["delete"] + ids)
        XCTAssertEqual(deleted["succeeded"]?.doubleValue, 6)
        let path = try XCTUnwrap(deleted["backup"]?.stringValue)
        let backup = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(backup.components(separatedBy: "BEGIN:VCARD").count - 1, 6)
    }

    func testGroupLifecycle() throws {
        let app = try makeApp()
        let created = run(app, ["group", "create", "QA-gesher-Group"])
        XCTAssertEqual(created["succeeded"]?.doubleValue, 1)
        run(app, ["group", "create", "QA-gesher-Group"], exit: 1)
        XCTAssertEqual(run(app, ["group", "list"])["groups"]?.arrayValue?.first?["members"]?.doubleValue, 0)
        XCTAssertEqual(
            run(app, ["group", "rename", "QA-gesher-Group", "--name", "QA-gesher-Renamed"])["name"]?
                .stringValue,
            "QA-gesher-Renamed")
        run(app, ["group", "delete", "QA-gesher"], exit: 1)  // exact names only
        XCTAssertEqual(run(app, ["group", "delete", "QA-gesher-Renamed"])["succeeded"]?.doubleValue, 1)
        XCTAssertEqual(run(app, ["group", "list"])["groups"]?.arrayValue?.count, 0)
    }

    func testOutputOmitsEmptyAndInternalFields() throws {
        var contact = ContactSnapshot(id: "c1")
        contact.givenName = "Fixture"
        contact.phones = [LabeledText(label: "_$!<Mobile>!$_", value: "+1 555 000 0000")]
        let json = try JSONValue.encode(ContactOutput(contact)).compactText()
        XCTAssertEqual(
            json,
            #"{"firstName":"Fixture","id":"c1","name":"Fixture","phones":[{"label":"mobile","value":"+1 555 000 0000"}]}"#
        )
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
