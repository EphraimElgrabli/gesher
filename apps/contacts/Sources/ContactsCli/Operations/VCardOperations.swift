import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

enum ExportVCard: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: [String]?
        var group: String?
        var all: Bool
        var file: String?
    }

    struct Output: Encodable, Sendable {
        let count: Int
        let file: String?
        let vcard: String?
    }

    static let path = ["export"]
    static let summary =
        "Export contacts as vCard: chosen contacts, a group, or all; inline, or to a new .vcf file (never replaced)."
    /// Writes a file when `file` is given. Existing files are never replaced, so it is not destructive.
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .list("contact", "Contacts to export: id, name, phone or email.", positional: true),
        .string("group", "Export this group's members."),
        .boolean("all", "Export every contact (needs --file)."),
        .string(
            "file",
            "Write to this new .vcf file instead of returning the text. Existing files, hidden and system folders are refused."
        ),
    ]
    static let examples = [
        "export Dana", "export --group Family --file ~/Desktop/family.vcf", "export --all --file all.vcf",
    ]

    static let inlineLimit = 25

    static func validate(_ input: Input) throws {
        let selectors = input.contact ?? []
        guard [!selectors.isEmpty, input.group != nil, input.all].filter({ $0 }).count == 1 else {
            throw AgentError.invalid(
                "Choose exactly one of: contacts, --group or --all.",
                hint: "Example: export --group Family --file f.vcf")
        }
        _ = try destination(input.file)
    }

    /// A new `.vcf` file in a regular folder; nil for inline output.
    static func destination(_ file: String?) throws -> URL? {
        guard let file else { return nil }
        let url = URL(fileURLWithPath: NSString(string: file).expandingTildeInPath).standardizedFileURL
        guard url.pathExtension.lowercased() == "vcf" else {
            throw AgentError.invalid("\(file) is not a .vcf file.", hint: "Name the file with a .vcf extension.")
        }
        _ = try LocalFilePolicy.exportDirectory(url.deletingLastPathComponent().path)
        if FileManager.default.fileExists(atPath: url.path) {
            throw AgentError.invalid(
                "\(url.path) already exists; export never replaces files.", hint: "Choose another file name.")
        }
        return url
    }

    static func run(_ input: Input, _ context: ContactsContext) throws -> Output {
        let selectors = input.contact ?? []
        let url = try destination(input.file)
        let path = url?.path
        let ids: [String]
        if input.all {
            ids = try context.read.fetchContacts().map(\.id)
        } else if let group = input.group {
            ids = try context.read.fetchContacts(groupID: context.group(group).id).map(\.id)
        } else {
            let contacts = try context.read.fetchContacts()
            ids = try EntityResolver.resolveAll(
                selectors.map { try ContactSelector.resolve($0, in: contacts, policy: .fuzzy).id }, in: contacts,
                type: "contact", id: \.id, name: \.fullName
            ).map(\.id)
        }
        guard !ids.isEmpty else { throw AgentError(code: "not_found", message: "No contacts to export.") }
        guard path != nil || ids.count <= inlineLimit else {
            throw AgentError.invalid(
                "\(ids.count) contacts are too many to return inline.", hint: "Pass --file to write a .vcf file.")
        }
        let data = try context.write.vCard(ids: ids)
        guard let url, let path else {
            return Output(count: ids.count, file: nil, vcard: String(decoding: data, as: UTF8.self))
        }
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            throw AgentError.invalid(
                "\(path) already exists; export never replaces files.", hint: "Choose another file name.")
        } catch {
            throw AgentError(code: "write_failed", message: "Could not write \(path): \(error.localizedDescription)")
        }
        return Output(count: ids.count, file: path, vcard: nil)
    }
}

enum ImportVCard: AgentOperation {
    struct Input: Decodable, Sendable {
        var file: String?
        var vcard: String?
        var group: [String]?
        var dryRun: Bool
        var allowDuplicates: Bool
    }

    struct Preview: Encodable, Sendable {
        let contacts: [ContactSummary]
        let existing: [String]?
    }

    struct Output: Encodable, Sendable, PartialFailureReporting {
        let preview: Preview?
        let imported: BatchResult<ContactSummary>?
        var succeeded: Int { imported?.succeeded ?? 1 }
        var failed: Int { imported?.failed ?? 0 }
    }

    static let path = ["import"]
    static let summary =
        "Import contacts from a vCard file or text (skips ones that already exist); --dry-run previews without saving."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("file", "Path of a .vcf file.", positional: true),
        .string("vcard", "vCard text instead of a file."),
        .list("group", "Also add imported contacts to these groups (name or id)."),
        .boolean("dryRun", "Only show what would be imported."),
        .boolean("allowDuplicates", "Import even contacts that match an existing one."),
    ]
    static let examples = ["import ~/Downloads/card.vcf --dry-run", "import cards.vcf --group Work"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> Output {
        let data: Data
        switch (input.file, input.vcard) {
        case (let file?, nil):
            let path = NSString(string: file).expandingTildeInPath
            guard let contents = FileManager.default.contents(atPath: path) else {
                throw AgentError.invalid("Cannot read \(path).", hint: "Pass the path of an existing .vcf file.")
            }
            data = contents
        case (nil, let text?): data = Data(text.utf8)
        default: throw AgentError.invalid("Pass either a file or --vcard text.")
        }
        let entries = try context.write.parseVCard(data)
        guard !entries.isEmpty else { throw AgentError.invalid("The vCard contains no contacts.") }
        let existing = try context.read.fetchContacts()
        func duplicate(_ entry: VCardEntry) -> ContactSnapshot? {
            existing.first { other in
                let reasons = Duplicates.reasons(entry.snapshot, other)
                return reasons.contains("name")
                    && (reasons.count > 1 || (entry.snapshot.phones.isEmpty && entry.snapshot.emails.isEmpty))
            }
        }
        if input.dryRun {
            let found = entries.filter { duplicate($0) != nil }.map(\.snapshot.fullName)
            return Output(
                preview: Preview(
                    contacts: entries.map { ContactSummary($0.snapshot) }, existing: found.isEmpty ? nil : found),
                imported: nil)
        }
        let groups = try context.groups()
        let targets = try (input.group ?? []).map { try context.group($0, in: groups).id }
        let batch = Batch.run(entries, label: { $0.snapshot.fullName }) { entry in
            if !input.allowDuplicates, let match = duplicate(entry) {
                throw AgentError(
                    code: "already_exists", message: "'\(match.fullName)' already exists [\(match.id)].",
                    hint: "Update the existing contact, or pass --allow-duplicates to import it anyway.")
            }
            return ContactSummary(try context.write.importContact(entry, groupIDs: targets))
        }
        return Output(preview: nil, imported: batch)
    }
}
