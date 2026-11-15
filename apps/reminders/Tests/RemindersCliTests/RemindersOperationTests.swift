import GesherKit
import GesherPlatform
import Foundation
import XCTest
@testable import RemindersCli
@testable import RemindersCore

final class RemindersOperationTests: XCTestCase {
    /// An app whose context must not be created: input validation happens first.
    private func appWithoutContext() -> AgentApp<RemindersContext> {
        RemindersApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
    }

    private func run(_ app: AgentApp<RemindersContext>, _ args: [String]) -> (code: Int32, out: String) {
        var out: [String] = []
        let code = app.run(args, stdout: { out.append($0) }, stderr: { _ in })
        return (code, out.joined(separator: "\n"))
    }

    func testExamplesToolNamesAndEffects() {
        let app = RemindersApp.make()
        XCTAssertEqual(app.exampleFailures(), [])
        XCTAssertEqual(
            app.operations.map(\.toolName),
            [
                "lists", "tasks", "task_get", "tags", "task_create", "task_update", "task_complete", "task_delete",
                "task_restore", "deleted_tasks", "task_purge", "list_create", "list_update", "list_delete",
                "section_create", "section_update",
                "section_delete", "attachment_add", "attachment_remove", "attachment_export", "smart_lists",
                "smart_list_create", "smart_list_update", "smart_list_delete", "templates", "template_create",
                "template_apply", "template_delete", "doctor", "permissions",
            ])
        let destructive = app.operations.filter { $0.effect == .destructive }.map(\.toolName)
        XCTAssertEqual(
            destructive,
            [
                "task_delete", "task_purge", "list_delete", "section_delete", "attachment_remove", "smart_list_delete",
                "template_delete",
            ])
        XCTAssertTrue(app.operations.filter { $0.effect == .read }.allSatisfy(\.idempotent))
    }

    func testInvalidInputFailsBeforeOpeningReminders() {
        let app = appWithoutContext()
        let cases: [[String]] = [
            ["tasks", "--view", "someday"],
            ["tasks", "--section", "A"],
            ["task", "create"],
            ["task", "create", "x", "--priority", "urgent"],
            ["task", "create", "x", "--repeats", "fortnightly"],
            ["task", "create", "x", "--repeat-count", "3"],
            ["task", "create", "x", "--early-alert", "soon"],
            ["task", "create", "x", "--url", "example.com"],
            ["task", "create", "x", "--due", "someday"],
            ["task", "create", "--json", #"{"items":[{"title":"a","colour":"red"}]}"#],
            ["task", "create", "--json", #"{"items":[{"due":"today"}]}"#],
            ["task", "update", "x"],
            ["task", "update", "x", "--position", "top", "--before", "y"],
            ["task", "update", "a", "b", "--title", "c"],
            ["task", "update", "x", "--clear", "everything"],
            ["task", "delete"],
            ["list", "create", "x", "--color", "purple"],
            ["list", "create", "x", "--kind", "group", "--group", "y"],
            ["list", "update", "x"],
            ["section", "update", "--list", "x", "y"],
            ["attachment", "add", "--task", "x", "/etc/hosts"],
            ["attachment", "export", "--task", "x", "--to", "~/Library/LaunchAgents"],
        ]
        for args in cases {
            XCTAssertEqual(run(app, args).code, 64, args.joined(separator: " "))
        }
        XCTAssertTrue(run(app, ["tasks", "--veiw", "today"]).out.contains("Did you mean --view?"))
        let ssh = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh").path
        if FileManager.default.fileExists(atPath: ssh + "/known_hosts") {
            XCTAssertTrue(
                run(app, ["attachment", "add", "--task", "x", ssh + "/known_hosts"]).out.contains("file_not_allowed"))
        }
    }

    func testRecurrenceGrammar() throws {
        func rule(_ text: String) throws -> RecurrenceMutation? {
            if case .set(let rule)? = try MutationBuilder.recurrence(text, until: nil, count: nil) { return rule }
            return nil
        }
        XCTAssertEqual(try rule("daily")?.frequency, .daily)
        XCTAssertEqual(try rule("every 2 weeks")?.interval, 2)
        XCTAssertEqual(try rule("weekdays")?.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(try rule("weekly on mon, thu")?.weekdays, [2, 5])
        XCTAssertEqual(try rule("monthly on 1,15,last")?.daysOfMonth, [-1, 1, 15])
        XCTAssertEqual(try rule("every friday")?.weekdays, [6])
        XCTAssertEqual(try MutationBuilder.recurrence("none", until: nil, count: nil), .clear)
        XCTAssertThrowsError(try rule("weekly on 15"))
        XCTAssertThrowsError(try rule("hourly"))
    }

    func testCompactTaskOutputOmitsInternalAndEmptyFields() throws {
        let list = ReminderListSnapshot(id: "REMCDList:1", title: "Inbox", accountID: "acc")
        let section = ReminderSectionSnapshot(id: "REMCDListSection:1", listID: list.id, title: "Today")
        let task = ReminderTaskSnapshot(
            id: "REMCDReminder:1", listID: list.id, sectionID: section.id, title: "Pay rent", priority: 1,
            due: ReminderDate(date: Date(timeIntervalSince1970: 1_900_000_000), hasTime: false, timeZone: nil),
            recurrence: ReminderRecurrenceSnapshot(frequency: "monthly", interval: 1, daysOfMonth: [1]),
            assigneeID: nil, order: 3)
        let catalog = ReminderCatalog(accounts: [], lists: [list], sections: [section], tasks: [task])
        let json = try JSONValue.encode(TaskItem(task, catalog: catalog, now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(json["list"], "Inbox")
        XCTAssertEqual(json["section"], "Today")
        XCTAssertEqual(json["priority"], "high")
        XCTAssertEqual(json["repeats"], "monthly on day 1")
        for absent in [
            "flagged", "completed", "notes", "url", "tags", "parent", "order", "listID", "overdue", "assigned",
        ] {
            XCTAssertNil(json[absent], absent)
        }
        XCTAssertEqual(Priority(native: 3), .high)
        XCTAssertEqual(Priority(native: 9), .low)
        XCTAssertEqual(Priority(native: 0), .none)
    }

    func testViewsMatchTheApp() {
        let now = Date()
        let filter = ViewFilter(now: now)
        let today = ReminderTaskSnapshot(
            id: "a", listID: "l", title: "a",
            due: ReminderDate(date: Calendar.current.startOfDay(for: now), hasTime: false, timeZone: nil))
        let later = ReminderTaskSnapshot(
            id: "b", listID: "l", title: "b", isFlagged: true,
            due: ReminderDate(date: now.addingTimeInterval(3 * 86_400), hasTime: true, timeZone: nil))
        let done = ReminderTaskSnapshot(id: "c", listID: "l", title: "c", isCompleted: true)
        XCTAssertTrue(filter.matches(today, view: .today))
        XCTAssertFalse(filter.matches(today, view: .overdue))
        XCTAssertFalse(filter.matches(later, view: .today))
        XCTAssertTrue(filter.matches(later, view: .scheduled))
        XCTAssertTrue(filter.matches(later, view: .flagged))
        XCTAssertFalse(filter.matches(done, view: .all))
        XCTAssertTrue(filter.matches(done, view: .completed))
    }

    func testBackupRoundTripInIsolatedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(directory: directory)
        let list = ReminderListSnapshot(id: "REMCDList:1", title: "Inbox", accountID: "acc")
        let task = ReminderTaskSnapshot(id: "REMCDReminder:1", listID: list.id, title: "Fixture", tags: ["x"])
        let path = try store.save(
            operation: "delete", tasks: [task],
            catalog: ReminderCatalog(accounts: [], lists: [list], sections: [], tasks: [task]))
        let loaded = try store.load("latest")
        XCTAssertEqual(loaded.path, path)
        XCTAssertEqual(loaded.file.tasks.first?.task, task)
        XCTAssertEqual(loaded.file.tasks.first?.list, "Inbox")
        XCTAssertThrowsError(try store.load("missing.json"))
    }
}
