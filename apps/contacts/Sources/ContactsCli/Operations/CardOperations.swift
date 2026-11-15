import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

/// Card-level actions: photo, My Card, and linking duplicate cards.
enum SetPhoto: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: String
        var file: String?
        var clear: Bool
    }

    static let path = ["photo"]
    static let summary = "Set a contact's photo from an image file (JPEG, PNG, HEIC), or remove it with --clear."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("contact", "Contact: id, exact name, phone or email.", required: true, positional: true),
        .string("file", "Image file to use as the photo."),
        .boolean("clear", "Remove the photo."),
    ]
    static let examples = ["photo 'Dana Levi' --file ~/Pictures/dana.jpg", "photo 'Dana Levi' --clear"]

    static func validate(_ input: Input) throws {
        guard (input.file != nil) != input.clear else {
            throw AgentError.invalid("Pass either --file or --clear.", hint: "photo <contact> --file image.jpg")
        }
    }

    static func run(_ input: Input, _ context: ContactsContext) throws -> ContactOutput {
        let contact = try context.contact(input.contact, policy: .exactName)
        var data: Data?
        if let file = input.file {
            let url = try LocalFilePolicy.attachable(file)
            do { data = try Data(contentsOf: url) } catch {
                throw AgentError.invalid("Could not read \(url.path): \(error.localizedDescription)")
            }
            guard let data, ImageSniffer.isImage(data) else {
                throw AgentError.invalid("\(url.lastPathComponent) is not a JPEG, PNG, HEIC, GIF or TIFF image.")
            }
        }
        return ContactOutput(try context.write.setImage(id: contact.id, data: data))
    }
}

/// Recognizes common image formats by their magic bytes.
enum ImageSniffer {
    static func isImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) || bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if bytes.starts(with: Array("GIF8".utf8)) || bytes.starts(with: [0x49, 0x49, 0x2A, 0x00])
            || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
        {
            return true
        }
        return bytes.count >= 12 && Array(bytes[4..<8]) == Array("ftyp".utf8)  // HEIC/HEIF
    }
}

enum SetMeContact: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: String
    }

    static let path = ["me", "set"]
    static let summary = "Make a contact the user's own card (\"My Card\")."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("contact", "Contact: id, exact name, phone or email.", required: true, positional: true)
    ]
    static let examples = ["me set 'Dana Levi'"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> ContactOutput {
        let contact = try context.contact(input.contact, policy: .exactName)
        try context.write.setMeCard(id: contact.id)
        return ContactOutput(try context.read.fetchContact(id: contact.id), me: true)
    }
}

struct LinkOutput: Encodable, Sendable {
    let linked: [ContactRef]
    let link: String?
}

struct ContactRef: Encodable, Sendable {
    let id: String
    let name: String
}

enum LinkContacts: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: [String]
    }

    static let path = ["link"]
    static let summary =
        "Link duplicate cards so Contacts shows them as one person (Card > Link Cards); each card keeps its data."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .list("contact", "Two or more contacts: id, exact name, phone or email.", required: true, positional: true)
    ]
    static let examples = ["link 'Dana Levi' dana@example.com"]

    static func validate(_ input: Input) throws {
        guard input.contact.count >= 2 else {
            throw AgentError.invalid("Link needs at least two contacts.", hint: "Use ids from duplicates.")
        }
    }

    static func run(_ input: Input, _ context: ContactsContext) throws -> LinkOutput {
        let all = try context.read.fetchContacts()
        var contacts: [ContactSnapshot] = []
        for selector in input.contact {
            let contact = try ContactSelector.resolve(selector, in: all, policy: .exactName)
            if !contacts.contains(where: { $0.id == contact.id }) { contacts.append(contact) }
        }
        guard contacts.count >= 2 else {
            throw AgentError.invalid("The selectors name only one contact.", hint: "Pass two different contacts.")
        }
        let link = try context.write.link(ids: contacts.map(\.id))
        return LinkOutput(linked: contacts.map { ContactRef(id: $0.id, name: $0.fullName) }, link: link)
    }
}

enum UnlinkContact: AgentOperation {
    struct Input: Decodable, Sendable {
        var contact: String
    }

    static let path = ["unlink"]
    static let summary = "Separate a card from the cards it is linked to (the card and its data are kept)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("contact", "Contact: id, exact name, phone or email.", required: true, positional: true)
    ]
    static let examples = ["unlink 'Dana Levi'"]

    static func run(_ input: Input, _ context: ContactsContext) throws -> LinkOutput {
        let contact = try context.contact(input.contact, policy: .exactName)
        try context.write.unlink(id: contact.id)
        return LinkOutput(linked: [ContactRef(id: contact.id, name: contact.fullName)], link: nil)
    }
}
