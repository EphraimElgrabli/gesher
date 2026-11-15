import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

@main
enum ContactsCli {
    static func main() { ContactsApp.make().main() }
}

/// The Contacts app: its operations and shared dependencies (see AGENTS.md).
enum ContactsApp {
    static func make(context: @escaping () throws -> ContactsContext = { ContactsContext() })
        -> AgentApp<ContactsContext>
    {
        AgentApp(
            name: "contacts",
            summary: "Find, read and edit Apple Contacts, groups, birthdays and vCards.",
            instructions: """
                Contacts are selected by id, exact email, phone number in any format (+972 54…, 054-…), or \
                name (Hebrew and diacritics safe; nickname and company also match). Ambiguous selectors fail with \
                candidates: retry with an id. Multi-value inputs are 'label: value' (e.g. 'work: +972 4 123 4567'); \
                update replaces a field's list only when you pass that field, and add*/remove* change single \
                values. Deleting more than 5 items writes a backup to ~/.config/gesher/backups first.
                """,
            permission: .contacts,
            operations: [
                AnyOperation(SearchContacts.self),
                AnyOperation(ListContacts.self),
                AnyOperation(GetContacts.self),
                AnyOperation(MeContact.self),
                AnyOperation(SetMeContact.self),
                AnyOperation(CreateContact.self),
                AnyOperation(UpdateContact.self),
                AnyOperation(DeleteContacts.self),
                AnyOperation(SetPhoto.self),
                AnyOperation(LinkContacts.self),
                AnyOperation(UnlinkContact.self),
                AnyOperation(UpcomingBirthdays.self),
                AnyOperation(FindDuplicates.self),
                AnyOperation(ExportVCard.self),
                AnyOperation(ImportVCard.self),
                AnyOperation(ListGroups.self),
                AnyOperation(CreateGroups.self),
                AnyOperation(RenameGroup.self),
                AnyOperation(DeleteGroups.self),
                AnyOperation(AddToGroup.self),
                AnyOperation(RemoveFromGroup.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Contacts operation for the life of the process (or MCP session).
/// Repositories re-read the store on every call; nothing here caches user data.
final class ContactsContext {
    let runtime: ContactsRuntime
    let read: ContactsReadRepository
    let write: ContactsWriteRepository
    let config: UserConfig
    let backupDirectory: URL
    let now: () -> Date

    init(config: UserConfig = .load()) {
        runtime = ContactsRuntime()
        read = ContactsReadRepository(runtime: runtime)
        write = ContactsWriteRepository(runtime: runtime, readRepository: read)
        self.config = config
        backupDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gesher/backups")
        now = { Date() }
    }

    /// For tests: inject repositories over an isolated store and a temporary backup directory.
    init(
        runtime: ContactsRuntime, read: ContactsReadRepository, write: ContactsWriteRepository, config: UserConfig,
        backupDirectory: URL, now: @escaping () -> Date = { Date() }
    ) {
        self.runtime = runtime
        self.read = read
        self.write = write
        self.config = config
        self.backupDirectory = backupDirectory
        self.now = now
    }

    func contact(_ selector: String, policy: MatchPolicy = .fuzzy) throws -> ContactSnapshot {
        try ContactSelector.resolve(selector, in: read.fetchContacts(), policy: policy)
    }

    func groups() throws -> [ContactGroupSnapshot] { try read.fetchGroups() }

    func group(_ selector: String, in groups: [ContactGroupSnapshot]? = nil, policy: MatchPolicy = .fuzzy) throws
        -> ContactGroupSnapshot
    {
        try EntityResolver.resolve(
            selector, in: groups ?? self.groups(), type: "group", id: \.id, name: \.name, policy: policy)
    }

    /// Writes a backup file before a bulk destructive change and returns its path.
    func backup(_ kind: String, data: Data, extension ext: String) throws -> String {
        try PrivateStorage.createDirectory(backupDirectory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = backupDirectory.appendingPathComponent("contacts-\(kind)-\(formatter.string(from: now())).\(ext)")
        do {
            try PrivateStorage.write(data, to: url, options: .withoutOverwriting)
        } catch {
            throw AgentError(
                code: "backup_failed", message: "Could not write the backup \(url.path): \(error.localizedDescription)",
                hint: "Nothing was changed. Fix the backup directory or act on 5 items or fewer.")
        }
        return url.path
    }

    static let bulkThreshold = 5
}

/// Resolves a contact selector: id, email, phone number (any format), then name.
enum ContactSelector {
    static func resolve(_ selector: String, in contacts: [ContactSnapshot], policy: MatchPolicy) throws
        -> ContactSnapshot
    {
        let text = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AgentError.invalid("The contact selector is empty.") }
        if let exact = contacts.first(where: { $0.id == text }) { return exact }
        if text.contains("@"), !text.contains(" ") {
            return try unique(
                contacts.filter { $0.emails.contains { $0.value.caseInsensitiveCompare(text) == .orderedSame } },
                text, contacts)
        }
        if PhoneMatcher.looksLikePhone(text), PhoneMatcher.key(text).count >= 7 {
            return try unique(
                contacts.filter { $0.phones.contains { PhoneMatcher.matches($0.value, text) } }, text, contacts)
        }
        do {
            return try EntityResolver.resolve(
                text, in: contacts, type: "contact", id: \.id, name: \.fullName, detail: detail, policy: policy)
        } catch let error as AgentError where error.code == "not_found" {
            // Other names people use: "Family Given", nickname, company.
            let aliases = contacts.flatMap { contact in
                Set(
                    [
                        "\(contact.familyName) \(contact.givenName)", "\(contact.givenName) \(contact.familyName)",
                        contact.nickname, contact.organization,
                    ].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != contact.fullName }
                )
                .map { (contact, $0) }
            }
            do {
                return try EntityResolver.resolve(
                    text, in: aliases, type: "contact", id: \.0.id, name: \.1, detail: { detail($0.0) }, policy: policy
                ).0
            } catch let aliasError as AgentError where aliasError.code == "ambiguous" {
                let ids = Set(aliasError.candidates.map(\.id))
                if ids.count == 1, let match = contacts.first(where: { $0.id == ids.first }) { return match }
                throw AgentError.ambiguous(
                    "contact", text,
                    candidates: contacts.filter { ids.contains($0.id) }.map(candidate))
            } catch let aliasError as AgentError where aliasError.code == "not_found" {
                throw error
            }
        }
    }

    private static func unique(_ matches: [ContactSnapshot], _ text: String, _ all: [ContactSnapshot]) throws
        -> ContactSnapshot
    {
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw AgentError.notFound("contact", text) }
        throw AgentError.ambiguous("contact", text, candidates: matches.map(candidate))
    }

    static func candidate(_ contact: ContactSnapshot) -> Candidate {
        Candidate(id: contact.id, name: contact.fullName, detail: detail(contact))
    }

    static func detail(_ contact: ContactSnapshot) -> String? {
        [contact.organization].filter { !$0.isEmpty && $0 != contact.fullName }.first
            ?? contact.emails.first?.value ?? contact.phones.first?.value
    }
}
