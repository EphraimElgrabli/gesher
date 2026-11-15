import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

enum ListGroups: AgentOperation {
    static let path = ["group", "list"]
    static let summary = "List contact groups with their member counts."
    static let params: [Param] = []
    static let examples = ["group list"]

    static func run(_ input: NoInput, _ context: ContactsContext) throws -> GroupList {
        GroupList(
            groups: try context.groups().map {
                GroupOutput(id: $0.id, name: $0.name, members: try context.read.memberIDs(groupID: $0.id).count)
            })
    }
}

enum CreateGroups: AgentOperation {
    struct Input: Decodable, Sendable {
        var name: [String]
    }

    static let path = ["group", "create"]
    static let summary = "Create one or more groups (an existing group with the same name is reported, not duplicated)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [.list("name", "Group names.", required: true, positional: true)]
    static let examples = ["group create Family", "group create Work 'Book Club'"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> BatchResult<GroupOutput> {
        Batch.run(input.name, label: { $0 }) { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = try context.groups().first(where: {
                NameMatcher.normalize($0.name) == NameMatcher.normalize(trimmed)
            }) {
                throw AgentError(
                    code: "already_exists", message: "Group '\(existing.name)' already exists [\(existing.id)].",
                    hint: "Use the existing group, or choose another name.")
            }
            let group = try context.write.createGroup(name: trimmed)
            return GroupOutput(id: group.id, name: group.name, members: 0)
        }
    }
}

enum RenameGroup: AgentOperation {
    struct Input: Decodable, Sendable {
        var group: String
        var name: String
    }

    static let path = ["group", "rename"]
    static let summary = "Rename a group (by exact name or id)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("group", "Group: exact name or id.", required: true, positional: true),
        .string("name", "New name.", required: true),
    ]
    static let examples = ["group rename Work --name Colleagues"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> GroupOutput {
        let groups = try context.groups()
        let group = try context.group(input.group, in: groups, policy: .exactName)
        if let clash = groups.first(where: {
            $0.id != group.id && NameMatcher.normalize($0.name) == NameMatcher.normalize(input.name)
        }) {
            throw AgentError(
                code: "already_exists", message: "Another group is already named '\(clash.name)' [\(clash.id)].",
                hint: "Choose another name.")
        }
        let renamed = try context.write.renameGroup(id: group.id, name: input.name)
        return GroupOutput(id: renamed.id, name: renamed.name, members: nil)
    }
}

enum DeleteGroups: AgentOperation {
    struct Input: Decodable, Sendable {
        var group: [String]
    }

    static let path = ["group", "delete"]
    static let summary =
        "Delete groups by exact name or id; their contacts are kept. More than 5: a backup is written first."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [.list("group", "Groups: exact names or ids.", required: true, positional: true)]
    static let examples = ["group delete 'Old Team'"]

    struct BackupGroup: Encodable {
        let id: String
        let name: String
        let members: [String]
    }

    static func run(_ input: Input, _ context: ContactsContext) throws -> BackedUpBatch<GroupOutput> {
        let groups = try context.groups()
        let resolved = input.group.map { selector in
            Result { try context.group(selector, in: groups, policy: .exactName) }
        }
        let targets = Dictionary(resolved.compactMap { try? $0.get() }.map { ($0.id, $0) }) { a, _ in a }
        var backup: String?
        if targets.count > ContactsContext.bulkThreshold {
            let saved = try targets.values.map {
                BackupGroup(id: $0.id, name: $0.name, members: try context.read.memberIDs(groupID: $0.id))
            }
            backup = try context.backup("group-delete", data: JSONEncoder().encode(saved), extension: "json")
        }
        let batch = Batch.run(Array(zip(input.group, resolved)), label: { $0.0 }) { _, result in
            let group = try result.get()
            try context.write.deleteGroup(id: group.id)
            return GroupOutput(id: group.id, name: group.name, members: nil)
        }
        return BackedUpBatch(batch: batch, backup: backup)
    }
}

enum AddToGroup: AgentOperation {
    struct Input: Decodable, Sendable {
        var group: String
        var contact: [String]
    }

    static let path = ["group", "add"]
    static let summary = "Add contacts to a group (already a member: no change)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("group", "Group name or id.", required: true),
        .list("contact", "Contacts: id, name, phone or email.", required: true, positional: true),
    ]
    static let examples = ["group add --group Family Dana 054-123-4567"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> BatchResult<MembershipChange> {
        let group = try context.group(input.group)
        let contacts = try context.read.fetchContacts()
        return Batch.run(input.contact, label: { $0 }) { selector in
            let contact = try ContactSelector.resolve(selector, in: contacts, policy: .fuzzy)
            let changed = try context.write.setMembership(contactID: contact.id, groupID: group.id, member: true)
            return MembershipChange(contact: contact.fullName, id: contact.id, group: group.name, changed: changed)
        }
    }
}

enum RemoveFromGroup: AgentOperation {
    struct Input: Decodable, Sendable {
        var group: String
        var contact: [String]
    }

    static let path = ["group", "remove"]
    static let summary =
        "Remove contacts from a group; the contacts themselves are kept. More than 5: a backup is written first."
    static let effect = OperationEffect.destructive
    static let idempotent = true
    static let params: [Param] = [
        .string("group", "Group: exact name or id.", required: true),
        .list("contact", "Contacts: id, exact name, phone or email.", required: true, positional: true),
    ]
    static let examples = ["group remove --group Family 'Dana Levi'"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> BackedUpBatch<MembershipChange> {
        let group = try context.group(input.group, policy: .exactName)
        let contacts = try context.read.fetchContacts()
        if input.contact.count > ContactsContext.bulkThreshold {
            let members = try context.read.memberIDs(groupID: group.id)
            let saved = DeleteGroups.BackupGroup(id: group.id, name: group.name, members: members)
            let path = try context.backup("group-remove", data: JSONEncoder().encode(saved), extension: "json")
            return BackedUpBatch(batch: remove(input, group, contacts, context), backup: path)
        }
        return BackedUpBatch(batch: remove(input, group, contacts, context), backup: nil)
    }

    private static func remove(
        _ input: Input, _ group: ContactGroupSnapshot, _ contacts: [ContactSnapshot], _ context: ContactsContext
    ) -> BatchResult<MembershipChange> {
        Batch.run(input.contact, label: { $0 }) { selector in
            let contact = try ContactSelector.resolve(selector, in: contacts, policy: .exactName)
            let changed = try context.write.setMembership(contactID: contact.id, groupID: group.id, member: false)
            return MembershipChange(contact: contact.fullName, id: contact.id, group: group.name, changed: changed)
        }
    }
}
