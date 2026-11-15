import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

enum SearchContacts: AgentOperation {
    struct Input: Decodable, Sendable {
        var query: String
        var field: String
        var group: String?
        var limit: Int
    }

    static let path = ["search"]
    static let summary =
        "Find contacts by name, phone (any format), email, company or note text; best matches first."
    static let params: [Param] = [
        .string(
            "query", "Text to find: a name, part of a phone number, an email, a company.", required: true,
            positional: true),
        .choice("field", ["any", "name", "phone", "email", "company", "note"], "Where to look.", default: "any"),
        .string("group", "Only contacts in this group (name or id)."),
        .integer("limit", "Maximum results.", default: 20, min: 1, max: 500),
    ]
    static let examples = ["search Dana", "search 054-123 --field phone", "search example.com --field email"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> ContactList {
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw AgentError.invalid("The search query is empty.") }
        let group = try input.group.map { try context.group($0) }
        let ranked = try context.read.fetchContacts(groupID: group?.id).compactMap { contact in
            ContactSearch.score(contact, query: query, field: input.field).map { (contact, $0) }
        }.sorted { $0.1 < $1.1 }
        return ContactList(
            contacts: ranked.prefix(input.limit).map { ContactSummary($0.0) }, total: ranked.count,
            group: group?.name)
    }
}

/// Ranking for `search`: 0 exact name, 1 name prefix, 2 name words, 3 other fields.
enum ContactSearch {
    static func score(_ contact: ContactSnapshot, query: String, field: String) -> Int? {
        let normalized = NameMatcher.normalize(query)
        let words = normalized.split(separator: " ")
        func nameScore() -> Int? {
            let names = [
                contact.fullName, "\(contact.familyName) \(contact.givenName)", contact.nickname,
                "\(contact.phoneticGivenName) \(contact.phoneticFamilyName)",
            ].map(NameMatcher.normalize).filter { !$0.isEmpty }
            if names.contains(normalized) { return 0 }
            if names.contains(where: { $0.hasPrefix(normalized) }) { return 1 }
            let nameWords = names.flatMap { $0.split(separator: " ") }
            if !words.isEmpty, words.allSatisfy({ word in nameWords.contains { $0.hasPrefix(word) } }) { return 2 }
            return names.contains(where: { !normalized.isEmpty && $0.contains(normalized) }) ? 2 : nil
        }
        func contains(_ values: [String]) -> Bool {
            !normalized.isEmpty && values.contains { NameMatcher.normalize($0).contains(normalized) }
        }
        let phone =
            contact.phones.contains { PhoneMatcher.contains($0.value, query: query) }
            && query.contains(where: \.isNumber)
        let email = contact.emails.contains { $0.value.localizedCaseInsensitiveContains(query) }
        let company = contains([contact.organization, contact.department, contact.jobTitle])
        let note = contains([contact.note ?? ""])
        switch field {
        case "name": return nameScore()
        case "phone": return phone ? 3 : nil
        case "email": return email ? 3 : nil
        case "company": return company ? 3 : nil
        case "note": return note ? 3 : nil
        default:
            if let score = nameScore() { return score }
            return phone || email || company || note ? 3 : nil
        }
    }
}

enum ListContacts: AgentOperation {
    struct Input: Decodable, Sendable {
        var group: String?
        var limit: Int
        var offset: Int
    }

    static let path = ["list"]
    static let summary = "List contacts alphabetically, optionally only one group's members; paginate with offset."
    static let params: [Param] = [
        .string("group", "Only members of this group (name or id).", positional: true),
        .integer("limit", "Maximum contacts.", default: 50, min: 1, max: 1000),
        .integer("offset", "Skip this many first.", default: 0, min: 0),
    ]
    static let examples = ["list", "list Family", "list --limit 100 --offset 100"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> ContactList {
        let group = try input.group.map { try context.group($0) }
        let contacts = try context.read.fetchContacts(groupID: group?.id)
        return ContactList(
            contacts: contacts.dropFirst(input.offset).prefix(input.limit).map(ContactSummary.init),
            total: contacts.count, group: group?.name)
    }
}

enum GetContacts: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: [String]
    }

    static let path = ["get"]
    static let summary = "Full cards (all phones, emails, addresses, dates, related names, groups) for contacts."
    static let params: [Param] = [
        .list("contact", "Contacts: id, name, phone or email.", required: true, positional: true)
    ]
    static let examples = ["get Dana", "get '+972 54 123 4567' name@example.com"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> BatchResult<ContactOutput> {
        let contacts = try context.read.fetchContacts()
        let groups = try context.groups()
        let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        let membership = try context.read.membership()
        let me = try? context.read.meContactID()
        return Batch.run(input.contact, label: { $0 }) { selector in
            let match = try ContactSelector.resolve(selector, in: contacts, policy: .fuzzy)
            let contact = try context.read.fetchContact(id: match.id)  // full card, photo included
            return ContactOutput(
                contact, groups: (membership[contact.id] ?? []).compactMap { names[$0] }.sorted(),
                me: contact.id == me)
        }
    }
}

enum MeContact: AgentOperation {
    static let path = ["me"]
    static let summary = "The user's own card (\"My Card\" in Contacts)."
    static let params: [Param] = []
    static let examples = ["me"]

    static func run(_ input: NoInput, _ context: ContactsContext) throws -> ContactOutput {
        guard let id = try context.read.meContactID() else {
            throw AgentError(
                code: "not_found", message: "No card is set as My Card.",
                hint: "In Contacts choose Card > Make This My Card, or ask the user which contact is theirs.")
        }
        return ContactOutput(try context.read.fetchContact(id: id), me: true)
    }
}

enum CreateContact: AgentOperation {
    struct Input: Decodable, Sendable {
        var fields: ContactFieldsInput
        var group: [String]?

        enum CodingKeys: String, CodingKey { case group }

        init(from decoder: Decoder) throws {
            fields = try ContactFieldsInput(from: decoder)
            group = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([String].self, forKey: .group)
        }
    }

    static let path = ["create"]
    static let summary =
        "Create a contact with any fields; reports existing contacts that look the same (check before creating twice)."
    static let effect = OperationEffect.write
    static let params: [Param] =
        ContactFieldsInput.params + [.list("group", "Add the new contact to these groups (name or id).")]
    static let examples = [
        "create --first-name Dana --last-name Levi --phone 'mobile: 054-123-4567' --email 'work: dana@example.com'",
        "create --company 'Example Ltd' --kind organization --url example.com --group Work",
        "create --first-name Noa --birthday 1990-05-17 --related 'spouse: Dana' --social 'linkedin: noa'",
    ]

    static func run(_ input: Input, _ context: ContactsContext) throws -> ContactOutput {
        let draft = try input.fields.draft()
        guard
            !(draft.givenName + draft.familyName + draft.organization + draft.nickname).isEmpty
                || !draft.phones.isEmpty || !draft.emails.isEmpty
        else {
            throw AgentError.invalid(
                "A contact needs a name, company, phone or email.", hint: "Pass --first-name, --company or --phone.")
        }
        let existing = try context.read.fetchContacts()
        let groups = try context.groups()
        let targets = try (input.group ?? []).map { try context.group($0, in: groups) }
        let similar = Duplicates.similar(to: draft, in: existing)
        let created = try context.write.createContact(draft, groupIDs: targets.map(\.id))
        var output = ContactOutput(created, groups: targets.map(\.name).sorted())
        output.similar = similar.isEmpty ? nil : similar.map(ContactSummary.init)
        return output
    }
}

enum UpdateContact: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: String
        var fields: ContactFieldsInput
        var addPhone, removePhone, addEmail, removeEmail, addUrl, removeUrl, addAddress, removeAddress: [String]?
        var addDate, removeDate, addRelated, removeRelated, addSocial, removeSocial: [String]?

        enum CodingKeys: String, CodingKey {
            case contact, addPhone, removePhone, addEmail, removeEmail, addUrl, removeUrl, addAddress
            case removeAddress, addDate, removeDate, addRelated, removeRelated, addSocial, removeSocial
        }

        init(from decoder: Decoder) throws {
            fields = try ContactFieldsInput(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contact = try container.decode(String.self, forKey: .contact)
            func list(_ key: CodingKeys) throws -> [String]? {
                try container.decodeIfPresent([String].self, forKey: key)
            }
            (addPhone, removePhone, addEmail, removeEmail) = (
                try list(.addPhone), try list(.removePhone), try list(.addEmail), try list(.removeEmail)
            )
            (addUrl, removeUrl, addAddress, removeAddress) = (
                try list(.addUrl), try list(.removeUrl), try list(.addAddress), try list(.removeAddress)
            )
            (addDate, removeDate, addRelated, removeRelated) = (
                try list(.addDate), try list(.removeDate), try list(.addRelated), try list(.removeRelated)
            )
            (addSocial, removeSocial) = (try list(.addSocial), try list(.removeSocial))
        }

        func edit() throws -> ContactEdit {
            var edit = ContactEdit()
            edit.fields = fields.scalars
            edit.kind = fields.kind.flatMap(ContactKind.init(rawValue:))
            if let birthday = fields.birthday { edit.birthday = .some(try ValueText.birthday(birthday)) }
            func values<T>(_ replace: [String]?, _ add: [String]?, _ remove: [String]?, _ parse: (String) throws -> T)
                throws -> ValueEdit<T>
            {
                ValueEdit(
                    replace: try ContactFieldsInput.parse(replace, parse),
                    add: try ContactFieldsInput.parse(add, parse) ?? [],
                    remove: (remove ?? []).map { ValueText.split($0).value }.filter { !$0.isEmpty })
            }
            edit.phones = try values(fields.phone, addPhone, removePhone, ValueText.phone)
            edit.emails = try values(fields.email, addEmail, removeEmail, ValueText.email)
            edit.urls = try values(fields.url, addUrl, removeUrl, ValueText.url)
            edit.addresses = try values(fields.address, addAddress, removeAddress, ValueText.address)
            edit.dates = try values(fields.date, addDate, removeDate, ValueText.date)
            edit.relations = try values(fields.related, addRelated, removeRelated, ValueText.related)
            edit.socialProfiles = try values(fields.social, addSocial, removeSocial, ValueText.social)
            return edit
        }
    }

    static let path = ["update"]
    static let summary =
        "Change a contact: set fields ('' clears), replace a whole list (phone, email…), or add/remove single values."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] =
        [.string("contact", "Contact: id, exact name, phone or email.", required: true, positional: true)]
        + ContactFieldsInput.params.map { param in
            guard case .array = param.kind else { return param }
            return .list(param.name, "Replaces ALL \(param.name) values (pass '' for none). " + param.summary)
        }
        + [
            .list("addPhone", "Phones to add, 'label: number'."),
            .list("removePhone", "Phones to remove, in any format."),
            .list("addEmail", "Emails to add, 'label: address'."),
            .list("removeEmail", "Emails to remove."),
            .list("addUrl", "URLs to add, 'label: url'."),
            .list("removeUrl", "URLs to remove."),
            .list("addAddress", "Addresses to add, 'label: street; city; state; postal code; country'."),
            .list("removeAddress", "Addresses to remove: the street or the full formatted address."),
            .list("addDate", "Dates to add, 'label: YYYY-MM-DD'."),
            .list("removeDate", "Dates to remove: the date or its label."),
            .list("addRelated", "Related names to add, 'relation: name'."),
            .list("removeRelated", "Related names to remove (the name)."),
            .list("addSocial", "Social profiles to add, 'service: username' or URL."),
            .list("removeSocial", "Social profiles to remove: username, URL or service."),
        ]
    static let examples = [
        "update Dana --add-phone 'work: 04-123-4567' --remove-phone 054-123-4567",
        "update dana@example.com --job-title Manager --company 'Example Ltd'",
        "update Dana --nickname '' --birthday 1990-05-17",
    ]

    static func run(_ input: Input, _ context: ContactsContext) throws -> ContactOutput {
        let edit = try input.edit()
        guard !edit.isEmpty else {
            throw AgentError.invalid("Nothing to change.", hint: "Pass at least one field, e.g. --add-phone.")
        }
        let contact = try context.contact(input.contact, policy: .exactName)
        return ContactOutput(try context.write.updateContact(id: contact.id, edit: edit))
    }
}

enum DeleteContacts: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: [String]
    }

    static let path = ["delete"]
    static let summary =
        "Delete contacts by id, exact name, phone or email. More than 5 at once: a vCard backup is written first."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("contact", "Contacts to delete: id, exact name, phone or email.", required: true, positional: true)
    ]
    static let examples = ["delete 'Dana Levi'", "delete name@example.com 054-123-4567"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> BackedUpBatch<Deleted> {
        let contacts = try context.read.fetchContacts()
        let resolved = input.contact.map { selector in
            Result { try ContactSelector.resolve(selector, in: contacts, policy: .exactName) }
        }
        let targets = resolved.compactMap { try? $0.get() }
        var backup: String?
        if Set(targets.map(\.id)).count > ContactsContext.bulkThreshold {
            backup = try context.backup(
                "delete", data: context.write.vCard(ids: Array(Set(targets.map(\.id)))), extension: "vcf")
        }
        var done = Set<String>()
        let batch = Batch.run(Array(zip(input.contact, resolved)), label: { $0.0 }) { _, result in
            let contact = try result.get()
            guard done.insert(contact.id).inserted else { return Deleted(id: contact.id, name: contact.fullName) }
            try context.write.deleteContact(id: contact.id)
            return Deleted(id: contact.id, name: contact.fullName)
        }
        return BackedUpBatch(batch: batch, backup: backup)
    }
}
