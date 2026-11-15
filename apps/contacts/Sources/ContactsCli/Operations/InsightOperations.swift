import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

enum UpcomingBirthdays: AgentOperation {
    struct Input: Decodable, Sendable {
        var days: Int
        var dates: Bool
        var group: String?
    }

    struct Entry: Encodable, Sendable {
        let id: String
        let name: String
        let occasion: String
        let date: String
        let next: String
        let inDays: Int
        let turns: Int?
    }

    struct Output: Encodable, Sendable {
        let upcoming: [Entry]
        let from: String
        let days: Int
    }

    static let path = ["birthdays"]
    static let summary = "Upcoming birthdays (and optionally anniversaries/other dates), soonest first, with age."
    static let params: [Param] = [
        .integer("days", "Look this many days ahead (0 = today only).", default: 30, min: 0, max: 366),
        .boolean("dates", "Also include anniversaries and other contact dates."),
        .string("group", "Only members of this group (name or id)."),
    ]
    static let examples = ["birthdays", "birthdays --days 7 --dates", "birthdays --group Family --days 60"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> Output {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: context.now())
        let group = try input.group.map { try context.group($0) }
        let contacts = try context.read.fetchContacts(groupID: group?.id)
        let entries = contacts.flatMap { contact in
            var occasions: [(String, ContactDay)] = contact.birthday.map { [("birthday", $0)] } ?? []
            if input.dates {
                occasions += contact.dates.map { (displayLabel($0.label) ?? "date", $0.day) }
            }
            return occasions.compactMap { occasion, day -> Entry? in
                guard let next = nextOccurrence(day, after: today, calendar: calendar) else { return nil }
                let inDays = calendar.dateComponents([.day], from: today, to: next).day ?? 0
                guard inDays <= input.days else { return nil }
                let nextYear = calendar.component(.year, from: next)
                return Entry(
                    id: contact.id, name: contact.fullName, occasion: occasion, date: day.text,
                    next: DateOutput.day(next), inDays: inDays, turns: day.year.map { nextYear - $0 })
            }
        }
        return Output(
            upcoming: entries.sorted { ($0.inDays, $0.name) < ($1.inDays, $1.name) },
            from: DateOutput.day(today), days: input.days)
    }

    /// Next date on or after `today`; Feb 29 falls on Feb 28 in common years.
    static func nextOccurrence(_ day: ContactDay, after today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        for candidate in [year, year + 1] {
            var components = DateComponents(year: candidate, month: day.month, day: day.day)
            if day.month == 2, day.day == 29,
                calendar.range(
                    of: .day, in: .month, for: calendar.date(from: DateComponents(year: candidate, month: 2))!)?
                    .count == 28
            {
                components.day = 28
            }
            if let date = calendar.date(from: components), date >= today { return date }
        }
        return nil
    }
}

enum Duplicates {
    /// Existing contacts with the same full name, or sharing a phone number or email.
    static func similar(to contact: ContactSnapshot, in contacts: [ContactSnapshot]) -> [ContactSnapshot] {
        contacts.filter { !reasons(contact, $0).isEmpty }
    }

    static func reasons(_ a: ContactSnapshot, _ b: ContactSnapshot) -> [String] {
        var result: [String] = []
        let nameA = NameMatcher.normalize(a.fullName)
        if nameA.count > 1, nameA == NameMatcher.normalize(b.fullName), a.fullName != "No Name" {
            result.append("name")
        }
        if a.phones.contains(where: { phone in
            PhoneMatcher.key(phone.value).count >= 7
                && b.phones.contains { PhoneMatcher.matches(phone.value, $0.value) }
        }) {
            result.append("phone")
        }
        let emails = Set(a.emails.map { $0.value.lowercased() })
        if b.emails.contains(where: { emails.contains($0.value.lowercased()) }) { result.append("email") }
        return result
    }
}

enum FindDuplicates: AgentOperation {
    struct Input: Decodable, Sendable {
        var group: String?
        var limit: Int
    }

    struct Cluster: Encodable, Sendable {
        let reasons: [String]
        let contacts: [ContactSummary]
    }

    struct Output: Encodable, Sendable {
        let duplicates: [Cluster]
        let total: Int
    }

    static let path = ["duplicates"]
    static let summary =
        "Suggest likely duplicate contacts (same name, phone or email). Read-only: review, then update/delete yourself."
    static let params: [Param] = [
        .string("group", "Only look within this group (name or id)."),
        .integer("limit", "Maximum clusters.", default: 50, min: 1, max: 500),
    ]
    static let examples = ["duplicates", "duplicates --group Work"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> Output {
        let group = try input.group.map { try context.group($0) }
        let contacts = try context.read.fetchContacts(groupID: group?.id)
        // Union-find over contacts sharing a normalized name, phone key or email.
        var parent = Array(contacts.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        var owners: [String: [Int]] = [:]
        for (index, contact) in contacts.enumerated() {
            var keys: [String] = []
            let name = NameMatcher.normalize(contact.fullName)
            if name.count > 1, contact.fullName != "No Name" { keys.append("name:" + name) }
            keys += contact.phones.map { PhoneMatcher.key($0.value) }.filter { $0.count >= 7 }
                .map { "phone:" + $0.suffix(7) }
            keys += contact.emails.map { "email:" + $0.value.lowercased() }
            // Keys only find candidates; a pair is joined when it really shares a name, number or email.
            for key in Set(keys) {
                for other in owners[key, default: []]
                where !Duplicates.reasons(contact, contacts[other]).isEmpty {
                    parent[root(index)] = root(other)
                }
                owners[key, default: []].append(index)
            }
        }
        let clusters = Dictionary(grouping: contacts.indices, by: root).values.filter { $0.count > 1 }
            .map { indices -> Cluster in
                let members = indices.map { contacts[$0] }
                let reasons = Set(
                    members.indices.flatMap { i in
                        members.indices.filter { $0 > i }.flatMap { Duplicates.reasons(members[i], members[$0]) }
                    })
                return Cluster(reasons: reasons.sorted(), contacts: members.map(ContactSummary.init))
            }
            .sorted { ($0.contacts.first?.name ?? "") < ($1.contacts.first?.name ?? "") }
        return Output(duplicates: Array(clusters.prefix(input.limit)), total: clusters.count)
    }
}
