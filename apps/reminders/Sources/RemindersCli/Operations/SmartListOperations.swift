import GesherKit
import GesherPlatform
import Foundation
import RemindersCore

/// A smart list filter as agents write it: like `SmartListFilter`, but lists are names or ids and
/// dates in `date` may be natural ("on friday", "between today and 2026-12-01").
struct FilterInput: Decodable, Sendable {
    var match: String?
    var tags: [String]?
    var excludeTags: [String]?
    var tagsMatch: String?
    var tagged: Bool?
    var date: String?
    var includeOverdue: Bool?
    var time: String?
    var priorities: [String]?
    var flagged: Bool?
    var location: String?
    var lists: [String]?
    var excludeLists: [String]?

    /// Natural days inside `date` become ISO days; relative ranges stay as they are.
    static func normalizedDate(_ text: String, input: DateInput = DateInput()) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        func day(_ value: String) throws -> String { DateOutput.day(try input.parse(value).date) }
        for word in ["on", "before", "after"] where lower.hasPrefix(word + " ") {
            return "\(word) " + (try day(String(trimmed.dropFirst(word.count + 1))))
        }
        if lower.hasPrefix("between "), let range = lower.range(of: " and ") {
            let from = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 8)..<range.lowerBound])
            let to = String(trimmed[range.upperBound...])
            return "between \(try day(from)) and \(try day(to))"
        }
        return lower
    }

    func filter(context: RemindersContext, catalog: ReminderCatalog) throws -> SmartListFilter {
        do {
            let filter = SmartListFilter(
                match: match?.lowercased(), tags: tags, excludeTags: excludeTags, tagsMatch: tagsMatch?.lowercased(),
                tagged: tagged, date: try date.map { try Self.normalizedDate($0) }, includeOverdue: includeOverdue,
                time: time?.lowercased(), priorities: priorities?.map { $0.lowercased() }, flagged: flagged,
                location: location?.lowercased(),
                lists: try lists?.map { try context.list($0, in: catalog).id },
                excludeLists: try excludeLists?.map { try context.list($0, in: catalog).id })
            _ = try filter.nativeData()
            return filter
        } catch let error as ReminderCLIError {
            throw AgentError.invalid(error.localizedDescription, hint: filterHint)
        }
    }
}

let filterHint =
    "filter keys: match (all|any), tags, excludeTags, tagsMatch (all|any), tagged (true = any tag, false = untagged), "
    + "date (any|none|today|'on DAY'|'before DAY'|'after DAY'|'between DAY and DAY'|'next 3 days'|'past 2 weeks'), "
    + "includeOverdue, time (any|none|morning|afternoon|evening|night), priorities (low|medium|high|none), "
    + "flagged (true), location (any|none|car-connected|car-disconnected), lists, excludeLists."

private let filterParam = Param(
    "filter", .object,
    "Smart list filters, e.g. {\"tags\":[\"work\"],\"date\":\"next 7 days\",\"priorities\":[\"high\"],\"match\":\"all\"}. "
        + filterHint)

/// A custom smart list for agents: list ids in the filter are shown as list names.
struct SmartListItem: Encodable, Sendable {
    struct Filter: Encodable, Sendable {
        let match: String?
        let tags: [String]?
        let excludeTags: [String]?
        let tagsMatch: String?
        let tagged: Bool?
        let date: String?
        let includeOverdue: Bool?
        let time: String?
        let priorities: [String]?
        let flagged: Bool?
        let location: String?
        let lists: [String]?
        let excludeLists: [String]?
        let other: [String: String]?
    }
    let id: String
    let name: String
    let emoji: String?
    let color: String?
    let pinned: Bool?
    let filter: Filter
    let open: Int?

    init(_ list: ReminderSmartListSnapshot, catalog: ReminderCatalog?, open: Int? = nil) {
        id = list.id
        name = list.title
        emoji = list.emoji
        color = list.colorHex
        pinned = list.isPinned ? true : nil
        let names: ([String]?) -> [String]? = { ids in ids?.map { id in catalog?.list(id)?.title ?? id } }
        let value = list.filter
        filter = Filter(
            match: value.match, tags: value.tags, excludeTags: value.excludeTags,
            tagsMatch: value.tags == nil ? nil : value.tagsMatch, tagged: value.tagged, date: value.date,
            includeOverdue: value.includeOverdue == true ? true : nil, time: value.time, priorities: value.priorities,
            flagged: value.flagged, location: value.location, lists: names(value.lists),
            excludeLists: names(value.excludeLists), other: value.other)
        self.open = open
    }
}

extension RemindersContext {
    func smartList(_ selector: String, policy: MatchPolicy = .fuzzy) throws -> ReminderSmartListSnapshot {
        try EntityResolver.resolve(
            selector, in: try read.fetchSmartLists(), type: "smart list", id: \.id, name: \.title, policy: policy)
    }

    func template(_ selector: String, policy: MatchPolicy = .fuzzy) throws -> ReminderTemplateSnapshot {
        try EntityResolver.resolve(
            selector, in: try read.fetchTemplates(), type: "template", id: \.id, name: \.title, policy: policy)
    }

    func defaultAccountID(_ catalog: ReminderCatalog) throws -> String {
        guard
            let account = catalog.accounts.first(where: { $0.isDefault == true })?.id ?? catalog.accounts.first?.id
        else { throw AgentError(code: "not_found", message: "No Reminders account is available.") }
        return account
    }
}

enum ListSmartLists: AgentOperation {
    struct Input: Decodable, Sendable {
        var counts: Bool
    }

    static let path = ["smart-lists"]
    static let summary = "Custom smart lists with their filters (tags, date, time, priority, flag, location, lists)."
    static let params: [Param] = [.boolean("counts", "Also count each smart list's open tasks.")]
    static let examples = ["smart-lists", "smart-lists --counts"]

    struct Output: Encodable, Sendable {
        let smartLists: [SmartListItem]
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> Output {
        let catalog = try context.catalog(taskLists: [])
        let lists = try context.read.fetchSmartLists()
        return Output(
            smartLists: try lists.map { list in
                SmartListItem(
                    list, catalog: catalog,
                    open: input.counts
                        ? try context.read.fetchSmartListTaskIDs(id: list.id, includeCompleted: false).count : nil)
            })
    }
}

enum CreateSmartList: AgentOperation {
    struct Input: Decodable, Sendable {
        var name: String
        var filter: FilterInput
        var color: String?
        var emoji: String?
    }

    static let path = ["smart-list", "create"]
    static let summary = "Create a custom smart list from filters (as 'Make into Smart List' does in the app)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("name", "Name of the smart list.", required: true, positional: true),
        Param(filterParam.name, filterParam.kind, filterParam.summary, required: true),
        .string("color", "Hex color, e.g. #FF9500."), .string("emoji", "One emoji, or a Reminders symbol name."),
    ]
    static let examples = [
        "smart-list create 'Work this week' --filter '{\"tags\":[\"work\"],\"date\":\"next 7 days\"}'",
        "smart-list create Urgent --filter '{\"priorities\":[\"high\"],\"flagged\":true,\"match\":\"any\"}'",
    ]

    static func validate(_ input: Input) throws {
        if let color = input.color { _ = try ReminderColor.agentValidated(color) }
        if let date = input.filter.date { _ = try FilterInput.normalizedDate(date) }
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> SmartListItem {
        let catalog = try context.catalog(taskLists: [])
        let filter = try input.filter.filter(context: context, catalog: catalog)
        guard !filter.isEmpty else {
            throw AgentError.invalid("A smart list needs at least one filter.", hint: filterHint)
        }
        let created = try context.write.createSmartList(
            accountID: try context.defaultAccountID(catalog), name: input.name, filter: filter, emoji: input.emoji,
            colorHex: input.color)
        return SmartListItem(created, catalog: catalog)
    }
}

enum UpdateSmartList: AgentOperation {
    struct Input: Decodable, Sendable {
        var smartList: String
        var name: String?
        var filter: FilterInput?
        var color: String?
        var emoji: String?
    }

    static let path = ["smart-list", "update"]
    static let summary = "Rename, restyle or replace the filters of a custom smart list."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("smartList", "Smart list (name or id).", required: true, positional: true),
        .string("name", "New name."),
        Param(filterParam.name, filterParam.kind, "New filters (replace all of them). " + filterHint),
        .string("color", "Hex color, e.g. #FF9500."), .string("emoji", "One emoji, or a Reminders symbol name."),
    ]
    static let examples = ["smart-list update 'Work this week' --filter '{\"tags\":[\"work\"],\"date\":\"today\"}'"]

    static func validate(_ input: Input) throws {
        if let color = input.color { _ = try ReminderColor.agentValidated(color) }
        guard input.name != nil || input.filter != nil || input.color != nil || input.emoji != nil else {
            throw AgentError.invalid("Nothing to change.", hint: "Give name, filter, color or emoji.")
        }
    }

    static func run(_ input: Input, _ context: RemindersContext) throws -> SmartListItem {
        let catalog = try context.catalog(taskLists: [])
        let list = try context.smartList(input.smartList)
        let filter = try input.filter.map { try $0.filter(context: context, catalog: catalog) }
        if filter?.isEmpty == true { throw AgentError.invalid("A smart list needs at least one filter.") }
        let updated = try context.write.updateSmartList(
            id: list.id, name: input.name, filter: filter, emoji: input.emoji, colorHex: input.color)
        return SmartListItem(updated, catalog: catalog)
    }
}

enum DeleteSmartList: AgentOperation {
    struct Input: Decodable, Sendable {
        var smartList: String
    }

    static let path = ["smart-list", "delete"]
    static let summary = "Delete a custom smart list (its tasks are not affected)."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("smartList", "Exact smart list name, or id.", required: true, positional: true)
    ]
    static let examples = ["smart-list delete 'Work this week'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> DeletedItem {
        let list = try context.smartList(input.smartList, policy: .exactName)
        try context.write.deleteSmartList(id: list.id)
        return DeletedItem(id: list.id, title: list.title, deleted: true)
    }
}

// MARK: - Templates

struct TemplateItem: Encodable, Sendable {
    let id: String
    let name: String
    let emoji: String?
    let color: String?
    let sourceList: String?
    let includesCompleted: Bool?

    init(_ template: ReminderTemplateSnapshot, catalog: ReminderCatalog?) {
        id = template.id
        name = template.title
        emoji = template.emoji
        color = template.colorHex
        sourceList = template.sourceListID.flatMap { catalog?.list($0)?.title }
        includesCompleted = template.includesCompleted == true ? true : nil
    }
}

enum ListTemplates: AgentOperation {
    static let path = ["templates"]
    static let summary = "List templates (saved from lists with 'Save as Template')."
    static let params: [Param] = []
    static let examples = ["templates"]

    struct Output: Encodable, Sendable {
        let templates: [TemplateItem]
    }

    static func run(_ input: NoInput, _ context: RemindersContext) throws -> Output {
        let catalog = try context.catalog(taskLists: [])
        return Output(templates: try context.read.fetchTemplates().map { TemplateItem($0, catalog: catalog) })
    }
}

enum CreateTemplate: AgentOperation {
    struct Input: Decodable, Sendable {
        var list: String
        var name: String?
        var includeCompleted: Bool
    }

    static let path = ["template", "create"]
    static let summary = "Save a list as a template (its tasks, subtasks and sections are copied)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("list", "List to save (name or id).", required: true, positional: true),
        .string("name", "Template name. Default: the list's name."),
        .boolean("includeCompleted", "Also copy completed tasks."),
    ]
    static let examples = ["template create 'Packing list'", "template create Trip --name 'Trip checklist'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> TemplateItem {
        let catalog = try context.catalog(taskLists: [])
        let list = try context.list(input.list, in: catalog)
        let template = try context.write.createTemplate(
            listID: list.id, name: input.name ?? list.title, includeCompleted: input.includeCompleted)
        return TemplateItem(template, catalog: catalog)
    }
}

enum ApplyTemplate: AgentOperation {
    struct Input: Decodable, Sendable {
        var template: String
        var name: String?
    }

    static let path = ["template", "apply"]
    static let summary = "Create a new list from a template (its tasks and sections are copied)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("template", "Template (name or id).", required: true, positional: true),
        .string("name", "Name for the new list. Default: the template's name."),
    ]
    static let examples = ["template apply 'Trip checklist' --name 'Trip to Rome'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> ListResult {
        let template = try context.template(input.template)
        var list = try context.write.applyTemplate(id: template.id, accountID: template.accountID)
        if let name = input.name, name != list.title { list = try context.write.updateList(id: list.id, name: name) }
        return ListResult(list, catalog: try context.catalog(taskLists: []))
    }
}

enum DeleteTemplate: AgentOperation {
    struct Input: Decodable, Sendable {
        var template: String
    }

    static let path = ["template", "delete"]
    static let summary = "Delete a template (lists made from it are kept)."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("template", "Exact template name, or id.", required: true, positional: true)
    ]
    static let examples = ["template delete 'Trip checklist'"]

    static func run(_ input: Input, _ context: RemindersContext) throws -> DeletedItem {
        let template = try context.template(input.template, policy: .exactName)
        try context.write.deleteTemplate(id: template.id)
        return DeletedItem(id: template.id, title: template.title, deleted: true)
    }
}
