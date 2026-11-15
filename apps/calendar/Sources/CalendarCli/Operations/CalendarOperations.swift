import GesherKit
import GesherPlatform
import CalendarCore
import Foundation

private let colorParam = Param.string("color", "#RRGGBB or red, orange, yellow, green, blue, purple, brown, gray.")

enum ListCalendars: AgentOperation {
    struct Input: Decodable, Sendable {
        var writable: Bool
    }

    static let path = ["calendar", "list"]
    static let summary =
        "Calendars with account, kind (icloud, local, subscribed, birthdays, holidays...), color, writable and default."
    static let params: [Param] = [.boolean("writable", "Only calendars new events can be added to.")]
    static let examples = ["calendar list", "calendar list --writable"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> CalendarsOutput {
        CalendarsOutput(
            calendars: try context.read.fetchCalendars().filter { !input.writable || $0.writable }.map(
                CalendarOutput.init))
    }
}

enum ListAccounts: AgentOperation {
    static let path = ["account", "list"]
    static let summary = "Accounts that hold calendars (for choosing where a new calendar goes)."
    static let params: [Param] = []
    static let examples = ["account list"]

    static func run(_ input: NoInput, _ context: CalendarContext) throws -> AccountsOutput {
        AccountsOutput(accounts: try context.read.fetchSources().map(AccountOutput.init))
    }
}

enum CreateCalendar: AgentOperation {
    struct Input: Decodable, Sendable {
        var title: String
        var color: ColorText?
        var account: String?
    }

    static let path = ["calendar", "create"]
    static let summary = "Create an event calendar in an account (default: the account of your default calendar)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("title", "Calendar name.", required: true, positional: true), colorParam,
        .string("account", "Account name or id (see account list)."),
    ]
    static let examples = ["calendar create 'Side project' --color purple", "calendar create Trips --account iCloud"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> CalendarOutput {
        let color = input.color?.hex
        let sources = try context.read.fetchSources().filter { !$0.disabled && ![4, 5].contains($0.sourceType) }
        let account: CalendarSourceSnapshot
        if let selector = input.account ?? context.config.value("calendar", "account") {
            account = try EntityResolver.resolve(
                selector, in: sources, type: "account", id: \.id, name: \.title, detail: { AccountOutput($0).kind })
        } else if let defaultSource = try context.read.fetchCalendars().first(where: { $0.isDefault })?.sourceID,
            let match = sources.first(where: { $0.id == defaultSource })
        {
            account = match
        } else if sources.count == 1 {
            account = sources[0]
        } else {
            throw AgentError(
                code: "invalid_argument", message: "Say which account should hold the calendar.",
                hint: "Retry with account set to one of the candidates.",
                candidates: sources.map { Candidate(id: $0.id, name: $0.title, detail: AccountOutput($0).kind) })
        }
        return CalendarOutput(
            try context.write.createCalendar(title: input.title, colorHex: color, sourceID: account.id))
    }
}

enum UpdateCalendar: AgentOperation {
    struct Input: Decodable, Sendable {
        var calendar: String
        var title: String?
        var color: ColorText?
    }

    static let path = ["calendar", "update"]
    static let summary = "Rename and/or recolor a calendar."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("calendar", "Calendar name or id.", required: true, positional: true),
        .string("title", "New name."), colorParam,
    ]
    static let examples = ["calendar update 'Side project' --title 'Side projects' --color #3B82F6"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> CalendarOutput {
        let calendar = try context.writableCalendar(input.calendar)
        return CalendarOutput(
            try context.write.updateCalendar(id: calendar.id, title: input.title, colorHex: input.color?.hex))
    }
}

enum DeleteCalendar: AgentOperation {
    struct Input: Decodable, Sendable {
        var calendar: String
    }

    static let path = ["calendar", "delete"]
    static let summary =
        "Delete a calendar and all its events (exact name or id). Calendars with more than 5 events are backed up first."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [.string("calendar", "Exact calendar name or id.", required: true, positional: true)]
    static let examples = ["calendar delete 'Side projects'"]

    static func run(_ input: Input, _ context: CalendarContext) throws -> DeletedCalendarOutput {
        let calendar = try context.calendar(input.calendar, policy: .exactName)
        guard calendar.writable else {
            throw AgentError(
                code: "read_only_calendar",
                message: "'\(calendar.title)' is \(calendar.kind.rawValue) and cannot be deleted here.",
                hint: "Remove subscriptions and special calendars in Calendar settings.")
        }
        // Count (and if needed back up) events from two years back to two years ahead.
        let today = context.gregorian.startOfDay(for: context.now())
        let events = try context.read.fetchEvents(
            start: context.gregorian.date(byAdding: .year, value: -2, to: today)!,
            end: context.gregorian.date(byAdding: .year, value: 2, to: today)!, calendarIDs: [calendar.id])
        var backup: String?
        if events.count > BackupStore.threshold {
            backup = try context.backups.save(
                "calendar",
                CalendarBackup(
                    calendar: CalendarOutput(calendar),
                    events: events.map { EventOutput($0, zone: context.timeZone, detail: true) }))
        }
        try context.write.deleteCalendar(id: calendar.id)
        return DeletedCalendarOutput(
            id: calendar.id, title: calendar.title, deletedEvents: events.count, backup: backup)
    }

    struct CalendarBackup: Encodable {
        let calendar: CalendarOutput
        let events: [EventOutput]
    }
}
