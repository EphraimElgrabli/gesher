import GesherPlatform
import ContactsCore
import Foundation

private func text(_ value: String) -> String? { value.isEmpty ? nil : value }
private func list<T>(_ values: [T]) -> [T]? { values.isEmpty ? nil : values }
func displayLabel(_ native: String?) -> String? { native.map(ContactLabel.display).flatMap(text) }

/// One line per contact in lists and search results.
struct ContactSummary: Encodable, Sendable {
    let id: String
    let name: String
    let company: String?
    let phones: [String]?
    let emails: [String]?

    init(_ contact: ContactSnapshot) {
        id = contact.id
        name = contact.fullName
        company = contact.organization == contact.fullName ? nil : text(contact.organization)
        phones = list(contact.phones.map(\.value))
        emails = list(contact.emails.map(\.value))
    }
}

struct ContactList: Encodable, Sendable {
    let contacts: [ContactSummary]
    let total: Int
    let group: String?
}

struct LabeledOutput: Encodable, Sendable {
    let label: String?
    let value: String
    init(_ value: LabeledText) {
        label = displayLabel(value.label)
        self.value = value.value
    }
}

struct AddressOutput: Encodable, Sendable {
    let label: String?
    let street, city, state, postalCode, country: String?
    let formatted: String

    init(_ address: PostalAddress) {
        label = displayLabel(address.label)
        street = text(address.street)
        city = text(address.city)
        state = text(address.state)
        postalCode = text(address.postalCode)
        country = text(address.country)
        formatted = address.formatted
    }
}

struct DateOutputValue: Encodable, Sendable {
    let label: String?
    let date: String
}

struct RelatedOutput: Encodable, Sendable {
    let label: String?
    let name: String
}

struct SocialOutput: Encodable, Sendable {
    let service: String?
    let username: String?
    let url: String?
}

struct AltBirthdayOutput: Encodable, Sendable {
    let calendar: String
    let date: String
}

/// Full contact card. Empty fields are omitted.
struct ContactOutput: Encodable, Sendable {
    let id: String
    let name: String
    let kind: String?
    let prefix, firstName, middleName, lastName, suffix, nickname: String?
    let phoneticFirstName, phoneticLastName: String?
    let company, department, jobTitle: String?
    let birthday: String?
    let altBirthday: AltBirthdayOutput?
    let phones: [LabeledOutput]?
    let emails: [LabeledOutput]?
    let urls: [LabeledOutput]?
    let addresses: [AddressOutput]?
    let dates: [DateOutputValue]?
    let related: [RelatedOutput]?
    let social: [SocialOutput]?
    let note: String?
    let hasImage: Bool?
    let groups: [String]?
    let me: Bool?
    /// Create only: existing contacts sharing a name, phone or email.
    var similar: [ContactSummary]?

    init(_ contact: ContactSnapshot, groups: [String]? = nil, me: Bool = false) {
        id = contact.id
        name = contact.fullName
        kind = contact.kind == .organization ? "organization" : nil
        prefix = text(contact.namePrefix)
        firstName = text(contact.givenName)
        middleName = text(contact.middleName)
        lastName = text(contact.familyName)
        suffix = text(contact.nameSuffix)
        nickname = text(contact.nickname)
        phoneticFirstName = text(contact.phoneticGivenName)
        phoneticLastName = text(contact.phoneticFamilyName)
        company = text(contact.organization)
        department = text(contact.department)
        jobTitle = text(contact.jobTitle)
        birthday = contact.birthday?.text
        altBirthday = contact.altBirthday.map { AltBirthdayOutput(calendar: $0.calendar, date: $0.day.text) }
        phones = list(contact.phones.map(LabeledOutput.init))
        emails = list(contact.emails.map(LabeledOutput.init))
        urls = list(contact.urls.map(LabeledOutput.init))
        addresses = list(contact.addresses.map(AddressOutput.init))
        dates = list(contact.dates.map { DateOutputValue(label: displayLabel($0.label), date: $0.day.text) })
        related = list(contact.relations.map { RelatedOutput(label: displayLabel($0.label), name: $0.value) })
        social = list(
            contact.socialProfiles.map {
                SocialOutput(service: text($0.service), username: text($0.username), url: text($0.url))
            })
        note = contact.note.flatMap(text)
        hasImage = contact.hasImage ? true : nil
        self.groups = groups.flatMap(list)
        self.me = me ? true : nil
    }
}

struct GroupOutput: Encodable, Sendable {
    let id: String
    let name: String
    let members: Int?
}

struct GroupList: Encodable, Sendable {
    let groups: [GroupOutput]
}

struct MembershipChange: Encodable, Sendable {
    let contact: String
    let id: String
    let group: String
    let changed: Bool
}

struct Deleted: Encodable, Sendable {
    let id: String
    let name: String
}

/// A batch result plus the backup written before a bulk destructive change.
struct BackedUpBatch<Item: Encodable & Sendable>: Encodable, Sendable, PartialFailureReporting {
    let batch: BatchResult<Item>
    let backup: String?

    var succeeded: Int { batch.succeeded }
    var failed: Int { batch.failed }

    private enum CodingKeys: String, CodingKey { case backup }

    func encode(to encoder: Encoder) throws {
        try batch.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(backup, forKey: .backup)
    }
}
