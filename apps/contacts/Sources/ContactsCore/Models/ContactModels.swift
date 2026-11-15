import GesherPlatform
import Foundation

public struct ContactGroupSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A day without a time: a birthday or another contact date. `year` is nil for "every May 17".
public struct ContactDay: Codable, Sendable, Equatable, Hashable {
    public var year: Int?
    public var month: Int
    public var day: Int

    public init(year: Int? = nil, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `1990-05-17`, `--05-17` or `05-17`.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        let numbers = parts.compactMap(Int.init)
        guard numbers.count == parts.count else { return nil }
        switch numbers.count {
        case 3 where parts[0].count == 4: self.init(year: numbers[0], month: numbers[1], day: numbers[2])
        case 2: self.init(year: nil, month: numbers[0], day: numbers[1])
        default: return nil
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let year, !(1...9999).contains(year) { return nil }
    }

    /// ISO day, or `--MM-DD` when the year is unknown.
    public var text: String {
        let monthDay = String(format: "%02d-%02d", month, day)
        return year.map { String(format: "%04d-", $0) + monthDay } ?? "--" + monthDay
    }
}

/// A labeled single string (phone, email, URL, related name). `label` is the native label.
public struct LabeledText: Codable, Sendable, Equatable, Hashable {
    public var label: String?
    public var value: String

    public init(label: String?, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PostalAddress: Codable, Sendable, Equatable, Hashable {
    public var label: String?
    public var street: String = ""
    public var subLocality: String = ""
    public var city: String = ""
    public var subAdministrativeArea: String = ""
    public var state: String = ""
    public var postalCode: String = ""
    public var country: String = ""
    public var isoCountryCode: String = ""

    public init(
        label: String?, street: String = "", city: String = "", state: String = "", postalCode: String = "",
        country: String = "", isoCountryCode: String = "", subLocality: String = "", subAdministrativeArea: String = ""
    ) {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.isoCountryCode = isoCountryCode
        self.subLocality = subLocality
        self.subAdministrativeArea = subAdministrativeArea
    }

    /// One line: non-empty components joined by ", ".
    public var formatted: String {
        [street, subLocality, city, subAdministrativeArea, state, postalCode, country]
            .map { $0.replacingOccurrences(of: "\n", with: ", ") }.filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

public struct LabeledDay: Codable, Sendable, Equatable, Hashable {
    public var label: String?
    public var day: ContactDay

    public init(label: String?, day: ContactDay) {
        self.label = label
        self.day = day
    }
}

public struct SocialProfile: Codable, Sendable, Equatable, Hashable {
    public var label: String?
    public var service: String = ""
    public var username: String = ""
    public var url: String = ""

    public init(label: String? = nil, service: String, username: String = "", url: String = "") {
        self.label = label
        self.service = service
        self.username = username
        self.url = url
    }
}

/// A non-Gregorian birthday (e.g. Hebrew calendar), read-only.
public struct CalendarDay: Codable, Sendable, Equatable {
    public let calendar: String
    public let day: ContactDay
}

public enum ContactKind: String, Codable, Sendable {
    case person, organization
}

/// The native contact, fully decoded. Nil scalars/collections mean the key was not available.
public struct ContactSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var kind: ContactKind = .person
    public var namePrefix: String = ""
    public var givenName: String = ""
    public var middleName: String = ""
    public var familyName: String = ""
    public var nameSuffix: String = ""
    public var nickname: String = ""
    public var phoneticGivenName: String = ""
    public var phoneticFamilyName: String = ""
    public var organization: String = ""
    public var department: String = ""
    public var jobTitle: String = ""
    public var birthday: ContactDay?
    public var altBirthday: CalendarDay?
    public var phones: [LabeledText] = []
    public var emails: [LabeledText] = []
    public var urls: [LabeledText] = []
    public var addresses: [PostalAddress] = []
    public var dates: [LabeledDay] = []
    public var relations: [LabeledText] = []
    public var socialProfiles: [SocialProfile] = []
    /// Nil when the store does not expose notes to this process.
    public var note: String?
    public var hasImage: Bool = false

    public init(id: String) { self.id = id }

    /// "Given Middle Family" (prefix/suffix included), else nickname, else organization.
    public var fullName: String {
        let name = [namePrefix, givenName, middleName, familyName, nameSuffix].filter { !$0.isEmpty }
            .joined(separator: " ")
        if kind == .organization, !organization.isEmpty { return organization }
        if !name.isEmpty { return name }
        if !nickname.isEmpty { return nickname }
        if !organization.isEmpty { return organization }
        if let email = emails.first?.value { return email }
        if let phone = phones.first?.value { return phone }
        return "No Name"
    }

    /// Everything a caller can set, for verification (the image and the read-only alt birthday excluded).
    public var editable: ContactSnapshot {
        var copy = self
        copy.id = ""
        copy.altBirthday = nil
        copy.hasImage = false
        return copy
    }
}

/// Text fields that can be set directly. Raw values are the native property names.
public enum ContactField: String, CaseIterable, Sendable {
    case namePrefix, givenName, middleName, familyName, nameSuffix, nickname, phoneticGivenName,
        phoneticFamilyName
    case organization = "organizationName"
    case department = "departmentName"
    case jobTitle, note

    public var keyPath: WritableKeyPath<ContactSnapshot, String> {
        switch self {
        case .namePrefix: \.namePrefix
        case .givenName: \.givenName
        case .middleName: \.middleName
        case .familyName: \.familyName
        case .nameSuffix: \.nameSuffix
        case .nickname: \.nickname
        case .phoneticGivenName: \.phoneticGivenName
        case .phoneticFamilyName: \.phoneticFamilyName
        case .organization: \.organization
        case .department: \.department
        case .jobTitle: \.jobTitle
        case .note: \.noteText
        }
    }
}

extension ContactSnapshot {
    var noteText: String {
        get { note ?? "" }
        set { note = newValue }
    }
}

/// Changes to one multi-value field: replace the whole list, or add/remove individual values.
/// `remove` selectors match values (phones by number in any format) and are resolved before saving.
public struct ValueEdit<Value: Sendable & Equatable>: Sendable {
    public var replace: [Value]?
    public var add: [Value] = []
    public var remove: [String] = []

    public init(replace: [Value]? = nil, add: [Value] = [], remove: [String] = []) {
        self.replace = replace
        self.add = add
        self.remove = remove
    }

    public var isEmpty: Bool { replace == nil && add.isEmpty && remove.isEmpty }
}

/// A partial update. Unset fields keep their current value; "" clears a text field.
public struct ContactEdit: Sendable {
    public var fields: [ContactField: String] = [:]
    public var kind: ContactKind?
    /// `.some(nil)` clears the birthday.
    public var birthday: ContactDay??
    public var phones = ValueEdit<LabeledText>()
    public var emails = ValueEdit<LabeledText>()
    public var urls = ValueEdit<LabeledText>()
    public var addresses = ValueEdit<PostalAddress>()
    public var dates = ValueEdit<LabeledDay>()
    public var relations = ValueEdit<LabeledText>()
    public var socialProfiles = ValueEdit<SocialProfile>()

    public init() {}

    public var isEmpty: Bool {
        fields.isEmpty && kind == nil && birthday == nil && phones.isEmpty && emails.isEmpty && urls.isEmpty
            && addresses.isEmpty && dates.isEmpty && relations.isEmpty && socialProfiles.isEmpty
    }

    /// Applies the edit to a snapshot, resolving `remove` selectors. Throws `invalid_argument`
    /// for a removal that matches nothing, so nothing is saved.
    public func applied(to contact: ContactSnapshot) throws -> ContactSnapshot {
        var result = contact
        for (field, value) in fields { result[keyPath: field.keyPath] = value }
        if let kind { result.kind = kind }
        if let birthday { result.birthday = birthday }
        result.phones = try phones.applied(to: contact.phones, field: "phone") { PhoneMatcher.matches($0.value, $1) }
        result.emails = try emails.applied(to: contact.emails, field: "email") {
            $0.value.caseInsensitiveCompare($1.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }
        result.urls = try urls.applied(to: contact.urls, field: "url") { Self.sameURL($0.value, $1) }
        result.addresses = try addresses.applied(to: contact.addresses, field: "address") { address, selector in
            let query = NameMatcher.normalize(selector)
            return !query.isEmpty
                && (NameMatcher.normalize(address.formatted) == query
                    || NameMatcher.normalize(address.street) == query)
        }
        result.dates = try dates.applied(to: contact.dates, field: "date") { date, selector in
            let text = selector.trimmingCharacters(in: .whitespaces)
            return date.day.text == text || ContactDay(text: text) == date.day
                || date.label.map { ContactLabel.display($0) == text.lowercased() } == true
        }
        result.relations = try relations.applied(to: contact.relations, field: "related name") { relation, selector in
            NameMatcher.normalize(relation.value) == NameMatcher.normalize(selector)
        }
        result.socialProfiles = try socialProfiles.applied(to: contact.socialProfiles, field: "social profile") {
            profile, selector in
            let text = selector.trimmingCharacters(in: .whitespaces).lowercased()
            return [profile.username.lowercased(), profile.url.lowercased(), profile.service.lowercased()]
                .contains(text) || (!profile.url.isEmpty && Self.sameURL(profile.url, text))
        }
        return result
    }

    static func sameURL(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ text: String) -> String {
            var value = text.trimmingCharacters(in: .whitespaces).lowercased()
            for prefix in ["https://", "http://", "www."] where value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
            }
            while value.hasSuffix("/") { value.removeLast() }
            return value
        }
        return key(lhs) == key(rhs)
    }
}

extension ValueEdit {
    func applied(to current: [Value], field: String, matches: (Value, String) -> Bool) throws -> [Value] {
        var values = replace ?? current
        for selector in remove {
            let before = values.count
            values.removeAll { matches($0, selector) }
            if values.count == before {
                throw AgentError.invalid(
                    "No \(field) on this contact matches '\(selector)'; nothing was saved.",
                    hint: "Get the contact to see its current values and retry with one of them.")
            }
        }
        for value in add where !values.contains(value) { values.append(value) }
        return values
    }
}

/// Phone numbers compare by digits, in any format: `+972 54-123-4567`, `00972541234567` and
/// `054-1234567` are the same number (international prefix and national trunk 0 ignored).
public enum PhoneMatcher {
    /// Digits only (any script's decimal digits), with a leading international `00`/`+` or
    /// trunk `0` removed.
    public static func key(_ text: String) -> String {
        var digits = text.compactMap { character -> Character? in
            guard let value = character.wholeNumberValue, character.isNumber else { return nil }
            return Character(String(value))
        }
        while digits.first == "0" { digits.removeFirst() }
        return String(digits)
    }

    public static func looksLikePhone(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber).count
        let allowed = text.allSatisfy { $0.isNumber || " +-().#*/".contains($0) }
        return allowed && digits >= 3
    }

    /// Same number: equal keys, or one key ends with the other (country code present on one side
    /// only) and the shorter has at least 7 digits.
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = key(lhs)
        let b = key(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        return short.count >= 7 && long.hasSuffix(short)
    }

    /// Search: a full-number match, or the query's digits (at least 3) appear in the number.
    public static func contains(_ number: String, query: String) -> Bool {
        if matches(number, query) { return true }
        let needle = key(query)
        return needle.count >= 3 && key(number).contains(needle)
    }
}

/// Native labels (`_$!<Mobile>!$_`) <-> plain words (`mobile`). Unknown words are custom labels.
public enum ContactLabel {
    static let known: [String: String] = [
        "mobile": "_$!<Mobile>!$_", "home": "_$!<Home>!$_", "work": "_$!<Work>!$_", "other": "_$!<Other>!$_",
        "main": "_$!<Main>!$_", "home fax": "_$!<HomeFAX>!$_", "work fax": "_$!<WorkFAX>!$_",
        "other fax": "_$!<OtherFAX>!$_", "pager": "_$!<Pager>!$_", "school": "_$!<School>!$_",
        "homepage": "_$!<HomePage>!$_", "anniversary": "_$!<Anniversary>!$_", "mother": "_$!<Mother>!$_",
        "father": "_$!<Father>!$_", "parent": "_$!<Parent>!$_", "brother": "_$!<Brother>!$_",
        "sister": "_$!<Sister>!$_", "child": "_$!<Child>!$_", "friend": "_$!<Friend>!$_",
        "spouse": "_$!<Spouse>!$_", "partner": "_$!<Partner>!$_", "assistant": "_$!<Assistant>!$_",
        "manager": "_$!<Manager>!$_", "iphone": "iPhone", "icloud": "iCloud",
    ]
    static let aliases: [String: String] = [
        "cell": "mobile", "cellphone": "mobile", "fax": "work fax", "homefax": "home fax", "workfax": "work fax",
        "website": "homepage", "web": "homepage", "husband": "spouse", "wife": "spouse", "son": "child",
        "daughter": "child", "mom": "mother", "dad": "father",
    ]

    /// The native label for a plain word; unknown words are kept as custom labels.
    public static func native(_ word: String) -> String {
        let key = word.trimmingCharacters(in: .whitespaces).lowercased()
        return known[aliases[key] ?? key] ?? word.trimmingCharacters(in: .whitespaces)
    }

    /// The plain word for a native label.
    public static func display(_ label: String) -> String {
        if let match = known.first(where: { $0.value == label }) { return match.key }
        if label.hasPrefix("_$!<"), label.hasSuffix(">!$_") {
            return String(label.dropFirst(4).dropLast(4)).lowercased()
        }
        return label
    }
}
