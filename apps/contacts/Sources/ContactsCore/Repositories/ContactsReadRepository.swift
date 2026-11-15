import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Reads contacts and groups through the private ABCNContactStore. Every call re-reads the store.
public final class ContactsReadRepository: @unchecked Sendable {
    private let runtime: ContactsRuntime

    public init(runtime: ContactsRuntime) { self.runtime = runtime }

    typealias ObjectErrorCall =
        @convention(c) (AnyObject, Selector, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?

    private func call(_ selector: String, _ argument: AnyObject?) throws -> AnyObject? {
        let store = try runtime.makeDataMapper()
        let sel = NSSelectorFromString(selector)
        guard store.responds(to: sel) else {
            throw PlatformError.privateBackendUnavailable("ABCNContactStore lacks \(selector).")
        }
        var error: NSError?
        let result = ContactsRuntime.msgSend(ObjectErrorCall.self)(store, sel, argument, &error)
        try runtime.checkServiceError(error)
        return result
    }

    // MARK: Groups

    public func fetchGroups() throws -> [ContactGroupSnapshot] {
        try rawGroups().map(groupSnapshot)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func groupSnapshot(_ group: AnyObject) -> ContactGroupSnapshot {
        ContactGroupSnapshot(
            id: runtime.identifier(of: group),
            name: runtime.stringValue(from: group, selectors: ["name"]) ?? "Unnamed Group")
    }

    func rawGroups() throws -> [AnyObject] {
        guard let groups = runtime.objectArray(try call("groupsMatchingPredicate:error:", nil)) else {
            throw PlatformError.privateBackendUnavailable("Private Contacts service returned no group result.")
        }
        return groups
    }

    func rawGroup(id: String) throws -> AnyObject {
        guard let group = try rawGroups().first(where: { runtime.identifier(of: $0) == id }) else {
            throw PlatformError.objectNotFound(type: "group", id: id)
        }
        return group
    }

    public func fetchGroup(id: String) throws -> ContactGroupSnapshot {
        groupSnapshot(try rawGroup(id: id))
    }

    /// Contact ids in a group.
    public func memberIDs(groupID: String) throws -> [String] {
        try rawContacts(groupID: groupID).map(runtime.identifier)
    }

    /// Group ids per contact id, from one members fetch per group.
    public func membership() throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for group in try fetchGroups() {
            for member in try memberIDs(groupID: group.id) { result[member, default: []].append(group.id) }
        }
        return result
    }

    // MARK: Contacts

    /// Native contacts: one by id, a group's members, or all (nil predicate).
    func rawContacts(id: String? = nil, groupID: String? = nil) throws -> [AnyObject] {
        let store = try runtime.makeDataMapper()
        try runtime.load()
        let contactClass: AnyClass = try runtime.requireClass("ABCNContact")
        var predicate: AnyObject?
        if let id {
            predicate =
                ObjCSendIdIdArg(
                    contactClass, NSSelectorFromString("predicateForIdentifiers:"),
                    [try runtime.nativeIdentifier(id, group: false)] as NSArray) as AnyObject?
            guard predicate != nil else {
                throw PlatformError.privateBackendUnavailable("Contact identifier predicate is unavailable.")
            }
        } else if let groupID {
            predicate =
                ObjCSendIdIdArg(
                    contactClass, NSSelectorFromString("predicateForMembersOfGroupWithIdentifier:"),
                    try runtime.nativeIdentifier(groupID, group: true)) as AnyObject?
            guard predicate != nil else {
                throw PlatformError.privateBackendUnavailable("Contact group predicate is unavailable.")
            }
        }
        let selector = NSSelectorFromString("contactsMatchingPredicate:error:")
        guard store.responds(to: selector) else {
            throw PlatformError.privateBackendUnavailable(
                "ABCNContactStore lacks contactsMatchingPredicate:error:.")
        }
        var error: NSError?
        let result = ContactsRuntime.msgSend(ObjectErrorCall.self)(store, selector, predicate, &error)
        try runtime.checkServiceError(error)
        guard let contacts = runtime.objectArray(result) else {
            throw PlatformError.privateBackendUnavailable("Private Contacts fetch returned no result.")
        }
        return contacts
    }

    /// One native contact. `complete` also reads the properties fetches normally skip (alert
    /// tones): pass it for a contact that will be saved back.
    func rawContact(id: String, complete: Bool = false) throws -> AnyObject {
        let fetch = { try self.rawContacts(id: id).first(where: { self.runtime.identifier(of: $0) == id }) }
        guard let contact = try complete ? ContactsRuntime.withAlertTones(fetch) : fetch() else {
            throw PlatformError.objectNotFound(type: "contact", id: id)
        }
        return contact
    }

    /// The link shared by cards shown as one contact, or nil when the card is not linked.
    public func linkIdentifier(id: String) throws -> String? {
        guard let link = runtime.value("linkIdentifier", of: try rawContact(id: id)) as? String, !link.isEmpty else {
            return nil
        }
        return link
    }

    /// Ids of all cards that share `link`.
    public func linkedIDs(link: String) throws -> [String] {
        try rawContacts().filter { (runtime.value("linkIdentifier", of: $0) as? String) == link }.map(
            runtime.identifier)
    }

    /// The contact's photo data, or nil when it has none.
    func imageData(_ contact: AnyObject) throws -> Data? {
        guard Self.isStored(contact) else { return runtime.value("imageData", of: contact) as? Data }
        guard let book = try runtime.legacyAddressBook() else { return nil }  // in-memory store: no photos
        let person = try runtime.legacyRecord(runtime.identifier(of: contact), in: book, refresh: false)
        // `hasCustomImage` loads the stored photo; `imageData` alone answers nil until then.
        typealias Check = @convention(c) (AnyObject, Selector) -> Bool
        let check = NSSelectorFromString("hasCustomImage")
        guard person.responds(to: check), ContactsRuntime.msgSend(Check.self)(person, check) else { return nil }
        guard let data = ObjCSendId(person, NSSelectorFromString("imageData")) as? Data, !data.isEmpty else {
            return nil
        }
        return data
    }

    static func isStored(_ contact: AnyObject) -> Bool { ContactsRuntime.isAddressBookObject(contact) }

    /// All contacts (or a group's members), sorted by name.
    public func fetchContacts(groupID: String? = nil) throws -> [ContactSnapshot] {
        try rawContacts(groupID: groupID).map { contact in
            let snapshot = try snapshot(contact)
            return (snapshot, snapshot.fullName)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }.map(\.0)
    }

    /// One contact, including whether it has a photo (read only here: one photo read per contact).
    public func fetchContact(id: String) throws -> ContactSnapshot {
        let contact = try rawContact(id: id)
        var result = try snapshot(contact)
        result.hasImage = try imageData(contact) != nil
        return result
    }

    /// The "me" card's id, or nil when none is set.
    public func meContactID() throws -> String? {
        let store = try runtime.makeDataMapper()
        let selector = NSSelectorFromString("fetchIdentifierForMeCard:")
        guard store.responds(to: selector) else {
            throw PlatformError.privateBackendUnavailable("ABCNContactStore lacks fetchIdentifierForMeCard:.")
        }
        typealias Call = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
        var error: NSError?
        let result = ContactsRuntime.msgSend(Call.self)(store, selector, &error)
        if let error, error.domain == "CNErrorDomain", error.code == 200 { return nil }  // record does not exist
        try runtime.checkServiceError(error)
        let id = (result as? String) ?? result.flatMap { runtime.stringValue(from: $0, selectors: ["stringValue"]) }
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    // MARK: vCard

    /// Parses vCard data into unsaved native contacts.
    func parseVCard(_ data: Data) throws -> [AnyObject] {
        try runtime.load()
        let serializer: AnyClass = try runtime.requireClass("CNContactVCardSerialization")
        let selector = NSSelectorFromString("contactsWithData:error:")
        var error: NSError?
        let result = ContactsRuntime.msgSend(ObjectErrorCall.self)(serializer, selector, data as NSData, &error)
        if let error {
            throw PlatformError.invalidArgument("The vCard could not be read: \(error.localizedDescription)")
        }
        guard let contacts = runtime.objectArray(result) else {
            throw PlatformError.invalidArgument("The vCard contains no contacts.")
        }
        return contacts
    }

    // MARK: Decoding

    func snapshot(_ contact: AnyObject) throws -> ContactSnapshot {
        guard let given = runtime.value("givenName", of: contact, empty: "") as? String,
            let family = runtime.value("familyName", of: contact, empty: "") as? String
        else {
            throw PlatformError.fetchFailed(
                "Native contact name fields are unavailable; empty strings were not inferred.")
        }
        var result = ContactSnapshot(id: runtime.identifier(of: contact))
        result.givenName = given
        result.familyName = family
        for field in ContactField.allCases where field != .givenName && field != .familyName {
            guard
                let text = runtime.value(field.rawValue, of: contact, empty: field == .note ? NSNull() : "") as? String
            else { continue }
            result[keyPath: field.keyPath] = text
        }
        // CNContactType and AddressBook's display style both use 1 for an organization.
        if let type = runtime.value("contactType", of: contact) as? NSNumber, type.intValue & 7 == 1 {
            result.kind = .organization
        }
        if let components = runtime.value("birthday", of: contact) as? DateComponents {
            result.birthday = Self.day(components)
        }
        if let components = runtime.value("nonGregorianBirthday", of: contact) as? DateComponents,
            let day = Self.day(components)
        {
            result.altBirthday = CalendarDay(
                calendar: components.calendar.map { "\($0.identifier)" } ?? "unknown", day: day)
        }
        result.hasImage = (runtime.value("imageDataAvailable", of: contact) as? NSNumber)?.boolValue ?? false
        result.phones = try labeled(contact, "phoneNumbers", required: true) { value in
            (value as? String) ?? runtime.stringValue(from: value, selectors: ["stringValue"])
        }
        result.emails = try labeled(contact, "emailAddresses", required: true) { $0 as? String }
        result.urls = try labeled(contact, "urlAddresses") { $0 as? String }
        result.relations = try labeled(contact, "contactRelations") { value in
            (value as? String) ?? runtime.value("name", of: value) as? String
        }
        result.addresses = try entries(contact, "postalAddresses").map { label, value in
            func text(_ key: String) -> String { (runtime.value(key, of: value) as? String) ?? "" }
            return PostalAddress(
                label: label, street: text("street"), city: text("city"), state: text("state"),
                postalCode: text("postalCode"), country: text("country"), isoCountryCode: text("ISOCountryCode"),
                subLocality: text("subLocality"), subAdministrativeArea: text("subAdministrativeArea"))
        }
        result.dates = try entries(contact, "dates").map { label, value in
            guard let components = value as? DateComponents, let day = Self.day(components) else {
                throw PlatformError.fetchFailed("Native contact contains an undecodable date.")
            }
            return LabeledDay(label: label, day: day)
        }
        result.socialProfiles = try entries(contact, "socialProfiles").map { label, value in
            func text(_ key: String) -> String { (runtime.value(key, of: value) as? String) ?? "" }
            return SocialProfile(
                label: label, service: text("service"), username: text("username"), url: text("urlString"))
        }
        return result
    }

    static func day(_ components: DateComponents) -> ContactDay? {
        guard let month = components.month, let day = components.day, month != NSDateComponentUndefined,
            day != NSDateComponentUndefined
        else { return nil }
        let year = components.year.flatMap { $0 == NSDateComponentUndefined ? nil : $0 }
        return ContactDay(year: year, month: month, day: day)
    }

    /// Labeled values of a key. An unavailable `required` key, or a present but undecodable
    /// collection or entry, is an error; never an inferred empty list.
    private func entries(_ contact: AnyObject, _ key: String, required: Bool = false) throws -> [(String?, AnyObject)] {
        guard let raw = runtime.value(key, of: contact, empty: NSArray()) else {
            if required {
                throw PlatformError.fetchFailed(
                    "Native contact collection \(key) is unavailable; no empty array was inferred.")
            }
            return []
        }
        guard let values = runtime.objectArray(raw) else {
            throw PlatformError.fetchFailed("Native contact collection \(key) is undecodable.")
        }
        return try values.map { entry in
            guard let value = runtime.value("value", of: entry) as AnyObject? else {
                throw PlatformError.fetchFailed("Native contact contains an undecodable \(key) value.")
            }
            return (runtime.value("label", of: entry) as? String, value)
        }
    }

    private func labeled(
        _ contact: AnyObject, _ key: String, required: Bool = false, _ decode: (AnyObject) -> String?
    ) throws -> [LabeledText] {
        try entries(contact, key, required: required).map { label, value in
            guard let text = decode(value) else {
                throw PlatformError.fetchFailed("Native contact contains an undecodable \(key) value.")
            }
            return LabeledText(label: label, value: text)
        }
    }
}
