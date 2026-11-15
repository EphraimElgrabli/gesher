import GesherKit
import GesherPlatform
import ContactsCore
import Foundation

/// Parses the `label: value` strings used by every multi-value parameter.
enum ValueText {
    /// `work: +972 4 123 4567` -> ("work", "+972 4 123 4567"). A URL scheme is not a label.
    static func split(_ raw: String) -> (label: String?, value: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.firstIndex(of: ":") else { return (nil, text) }
        let head = text[..<colon].trimmingCharacters(in: .whitespaces)
        let tail = text[text.index(after: colon)...]
        let schemes = ["http", "https", "mailto", "tel", "sms", "ftp", "facetime"]
        guard !tail.hasPrefix("//"), !head.isEmpty, head.count <= 30, !schemes.contains(head.lowercased()),
            head.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" })
        else { return (nil, text) }
        return (head, tail.trimmingCharacters(in: .whitespaces))
    }

    static func labeled(_ raw: String, default fallback: String) -> (label: String, value: String) {
        let (label, value) = split(raw)
        return (ContactLabel.native(label ?? fallback), value)
    }

    static func phone(_ raw: String) throws -> LabeledText {
        let (label, value) = labeled(raw, default: "mobile")
        guard value.contains(where: \.isNumber) else {
            throw AgentError.invalid("'\(raw)' is not a phone number.", hint: "Example: 'mobile: +972 54 123 4567'.")
        }
        return LabeledText(label: label, value: value)
    }

    static func email(_ raw: String) throws -> LabeledText {
        let (label, value) = labeled(raw, default: "home")
        guard value.contains("@"), !value.contains(" ") else {
            throw AgentError.invalid("'\(raw)' is not an email address.", hint: "Example: 'work: name@example.com'.")
        }
        return LabeledText(label: label, value: value)
    }

    static func url(_ raw: String) throws -> LabeledText {
        let (label, value) = labeled(raw, default: "homepage")
        guard !value.isEmpty else { throw AgentError.invalid("Empty URL.", hint: "Example: 'work: example.com'.") }
        return LabeledText(label: label, value: value)
    }

    static func related(_ raw: String) throws -> LabeledText {
        let (label, value) = labeled(raw, default: "other")
        guard !value.isEmpty else {
            throw AgentError.invalid("Empty related name.", hint: "Example: 'spouse: Dana'.")
        }
        return LabeledText(label: label, value: value)
    }

    /// `home: street; city; state; postal code; country` (semicolons), or commas:
    /// 2 parts = street, city; 3 = + country; 4 = street, city, postal code, country; 5 = all.
    static func address(_ raw: String) throws -> PostalAddress {
        let (label, value) = labeled(raw, default: "home")
        let separator: Character = value.contains(";") ? ";" : ","
        let parts = value.split(separator: separator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.contains(where: { !$0.isEmpty }) else {
            throw AgentError.invalid(
                "Empty address.", hint: "Example: 'home: 1 Example St; Haifa; ; 3100000; Israel'.")
        }
        func part(_ index: Int) -> String { index < parts.count ? parts[index] : "" }
        var address = PostalAddress(label: label)
        if separator == ";" || parts.count >= 5 {
            (address.street, address.city, address.state, address.postalCode) = (part(0), part(1), part(2), part(3))
            address.country = parts.count > 4 ? parts[4...].joined(separator: ", ") : ""
        } else {
            address.street = part(0)
            address.city = part(1)
            if parts.count == 3 { address.country = part(2) }
            if parts.count == 4 { (address.postalCode, address.country) = (part(2), part(3)) }
        }
        return address
    }

    static func date(_ raw: String) throws -> LabeledDay {
        let (label, value) = labeled(raw, default: "other")
        guard let day = ContactDay(text: value) else {
            throw AgentError.invalid(
                "'\(raw)' is not a date.", hint: "Use 'anniversary: 2015-06-01' or '--06-01' without a year.")
        }
        return LabeledDay(label: label, day: day)
    }

    static func birthday(_ raw: String) throws -> ContactDay? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        guard let day = ContactDay(text: text) else {
            throw AgentError.invalid(
                "'\(raw)' is not a birthday.", hint: "Use YYYY-MM-DD, or --MM-DD when the year is unknown.")
        }
        return day
    }

    static let services: [String: String] = [
        "twitter": "Twitter", "x": "Twitter", "facebook": "Facebook", "linkedin": "LinkedIn", "flickr": "Flickr",
        "myspace": "MySpace", "sinaweibo": "SinaWeibo", "tencentweibo": "TencentWeibo", "yelp": "Yelp",
        "gamecenter": "GameCenter", "instagram": "Instagram", "github": "GitHub", "telegram": "Telegram",
        "threads": "Threads", "mastodon": "Mastodon", "tiktok": "TikTok", "youtube": "YouTube",
    ]

    static let hosts: [String: String] = [
        "twitter.com": "Twitter", "x.com": "Twitter", "facebook.com": "Facebook", "linkedin.com": "LinkedIn",
        "instagram.com": "Instagram", "github.com": "GitHub", "t.me": "Telegram", "flickr.com": "Flickr",
        "yelp.com": "Yelp", "threads.net": "Threads", "tiktok.com": "TikTok", "youtube.com": "YouTube",
    ]

    /// `linkedin: username`, `twitter: https://x.com/name`, or a bare profile URL of a known site.
    static func social(_ raw: String) throws -> SocialProfile {
        let (label, value) = split(raw)
        let isURL = value.contains("/") || value.hasPrefix("http")
        var service = label.map { services[$0.lowercased()] ?? $0 }
        if service == nil, isURL {
            let host = URL(string: value.hasPrefix("http") ? value : "https://" + value)?.host?.lowercased() ?? ""
            service = hosts[host.hasPrefix("www.") ? String(host.dropFirst(4)) : host]
        }
        guard let service, !value.isEmpty else {
            throw AgentError.invalid(
                "'\(raw)' needs a service.", hint: "Use 'service: username' (e.g. 'linkedin: dana') or a profile URL.")
        }
        if isURL { return SocialProfile(service: service, url: value) }
        return SocialProfile(service: service, username: value.hasPrefix("@") ? String(value.dropFirst()) : value)
    }
}

/// Parameters shared by `create` and `update` (property names == param names).
struct ContactFieldsInput: Decodable, Sendable {
    var firstName, lastName, middleName, prefix, suffix, nickname: String?
    var phoneticFirstName, phoneticLastName: String?
    var company, department, jobTitle, birthday, note, kind: String?
    var phone, email, url, address, date, related, social: [String]?

    static let params: [Param] = [
        .string("firstName", "Given name."),
        .string("lastName", "Family name."),
        .string("middleName", "Middle name."),
        .string("prefix", "Name prefix, e.g. Dr."),
        .string("suffix", "Name suffix, e.g. Jr."),
        .string("nickname", "Nickname."),
        .string("phoneticFirstName", "Phonetic given name (pronunciation)."),
        .string("phoneticLastName", "Phonetic family name."),
        .string("company", "Company / organization."),
        .string("department", "Department."),
        .string("jobTitle", "Job title."),
        .string("birthday", "Birthday: YYYY-MM-DD, or --MM-DD without a year."),
        .string("note", "Note text."),
        .choice(
            "kind", ["person", "organization"], "Card type: a person, or a company card shown by its company name."),
        .list("phone", "Phone numbers as 'label: number' (label default mobile), e.g. 'work: +972 4 123 4567'."),
        .list("email", "Emails as 'label: address' (default home), e.g. 'work: name@example.com'."),
        .list("url", "Web pages as 'label: url' (default homepage)."),
        .list(
            "address",
            "Postal addresses: 'label: street; city; state; postal code; country' (or 'street, city, country')."),
        .list("date", "Other dates as 'label: YYYY-MM-DD' or 'anniversary: --06-01'."),
        .list("related", "Related names as 'relation: name', e.g. 'spouse: Dana', 'mother: Ruth'."),
        .list("social", "Social profiles as 'service: username' or a profile URL, e.g. 'linkedin: dana'."),
    ]

    var scalars: [ContactField: String] {
        let pairs: [(ContactField, String?)] = [
            (.givenName, firstName), (.familyName, lastName), (.middleName, middleName), (.namePrefix, prefix),
            (.nameSuffix, suffix), (.nickname, nickname), (.phoneticGivenName, phoneticFirstName),
            (.phoneticFamilyName, phoneticLastName), (.organization, company), (.department, department),
            (.jobTitle, jobTitle), (.note, note),
        ]
        return Dictionary(
            uniqueKeysWithValues: pairs.compactMap { field, value in
                value.map { (field, $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            })
    }

    /// Parses a list, dropping empty strings (so `--phone ''` means "no phones").
    static func parse<T>(_ values: [String]?, _ parse: (String) throws -> T) throws -> [T]? {
        try values.map { try $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(parse) }
    }

    /// The full contact to create.
    func draft() throws -> ContactSnapshot {
        var contact = ContactSnapshot(id: "")
        for (field, value) in scalars { contact[keyPath: field.keyPath] = value }
        if note == nil { contact.note = nil }
        contact.kind = kind.flatMap(ContactKind.init(rawValue:)) ?? .person
        contact.birthday = try birthday.flatMap(ValueText.birthday)
        contact.phones = try Self.parse(phone, ValueText.phone) ?? []
        contact.emails = try Self.parse(email, ValueText.email) ?? []
        contact.urls = try Self.parse(url, ValueText.url) ?? []
        contact.addresses = try Self.parse(address, ValueText.address) ?? []
        contact.dates = try Self.parse(date, ValueText.date) ?? []
        contact.relations = try Self.parse(related, ValueText.related) ?? []
        contact.socialProfiles = try Self.parse(social, ValueText.social) ?? []
        return contact
    }
}
