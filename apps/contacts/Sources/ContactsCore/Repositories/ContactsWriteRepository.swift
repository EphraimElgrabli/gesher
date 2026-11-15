import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// A contact parsed from a vCard, not yet saved.
public struct VCardEntry: @unchecked Sendable {
    public let snapshot: ContactSnapshot
    let native: AnyObject
    /// This contact's own vCard, when the input could be split per card.
    let vCard: Data?
}

/// Writes through the private ABCNSaveRequest. Every write is verified by a fresh read.
public final class ContactsWriteRepository: @unchecked Sendable {
    private let runtime: ContactsRuntime
    private let read: ContactsReadRepository

    public init(runtime: ContactsRuntime, readRepository: ContactsReadRepository) {
        self.runtime = runtime
        self.read = readRepository
    }

    // MARK: Groups

    public func createGroup(name: String) throws -> ContactGroupSnapshot {
        let name = try validatedName(name)
        let group = try runtime.makeMutableGroup()
        try runtime.setValue(name as NSString, "name", on: group)
        try save { request in try self.send(request, "addGroup:toAccountWithIdentifier:", group, nil) }
        let id = runtime.identifier(of: group)
        let result = try MutationVerification.readback(type: "group", id: id) { try read.fetchGroup(id: id) }
        guard result.name == name else {
            throw PlatformError.saveFailed("Group was saved but its name did not match. Inspect before retrying.")
        }
        return result
    }

    public func renameGroup(id: String, name: String) throws -> ContactGroupSnapshot {
        let name = try validatedName(name)
        let group = try mutableCopy(read.rawGroup(id: id))
        try runtime.setValue(name as NSString, "name", on: group)
        try save { request in try self.send(request, "updateGroup:", group) }
        let result = try MutationVerification.readback(type: "group", id: id) { try read.fetchGroup(id: id) }
        guard result.name == name else {
            throw PlatformError.saveFailed("Group rename was not verified. Inspect before retrying.")
        }
        return result
    }

    public func deleteGroup(id: String) throws {
        let group = try mutableCopy(read.rawGroup(id: id))
        try save { request in try self.send(request, "deleteGroup:", group) }
        try MutationVerification.absence(id: id, type: "group") { try read.fetchGroup(id: id) }
    }

    /// Adds (or removes) one contact to a group. Already a member (or not a member) is a no-op.
    @discardableResult
    public func setMembership(contactID: String, groupID: String, member: Bool) throws -> Bool {
        let group = try read.rawGroup(id: groupID)
        let contact = try read.rawContact(id: contactID)
        guard try read.memberIDs(groupID: groupID).contains(contactID) != member else { return false }
        try changeMembership(contact, group, member: member)
        let verified = try MutationVerification.readback(type: "group", id: groupID) {
            try read.memberIDs(groupID: groupID).contains(contactID)
        }
        guard verified == member else {
            throw PlatformError.saveFailed("Group membership change was not verified. Inspect before retrying.")
        }
        return true
    }

    // MARK: Contacts

    /// Creates a contact from a full description (labels already native), optionally in groups.
    public func createContact(_ draft: ContactSnapshot, groupIDs: [String] = []) throws -> ContactSnapshot {
        let groups = try groupIDs.map(read.rawGroup)
        let contact = try runtime.makeMutableContact()
        try write(draft, to: contact, base: ContactSnapshot(id: ""), native: [:], flavor: .addressBook)
        try save { request in try self.send(request, "addContact:toAccountWithIdentifier:", contact, nil) }
        let id = runtime.identifier(of: contact)
        let result = try verify(id: id, expected: draft)
        // Members are added once the contact exists.
        if !groups.isEmpty {
            let stored = try read.rawContact(id: id)
            for group in groups { try changeMembership(stored, group, member: true) }
        }
        try verifyMembership(id, in: groupIDs)
        return result
    }

    /// vCard 3.0 data for the given contact ids, in the given order, photos included. The user's
    /// address book exports through AddressBook's own vCard writer (as Contacts' Export does);
    /// an injected store through Contacts' serializer.
    public func vCard(ids: [String]) throws -> Data {
        if let book = try runtime.legacyAddressBook() {
            typealias Write = @convention(c) (AnyObject, Selector, Bool, Bool) -> AnyObject?
            let selector = NSSelectorFromString("_vCardRepresentationAsStringIncludeNotes:includePhotos:")
            var text = ""
            for id in ids {
                _ = try read.rawContact(id: id)
                let person = try runtime.legacyRecord(id, in: book)
                guard person.responds(to: selector),
                    let card = ContactsRuntime.msgSend(Write.self)(person, selector, runtime.notesAccessible, true)
                        as? String
                else { throw PlatformError.fetchFailed("AddressBook could not write a vCard for \(id).") }
                text += card.hasSuffix("\n") ? card : card + "\r\n"
            }
            return Data(text.utf8)
        }
        let contacts = try ids.map { id -> AnyObject in
            let native = try read.rawContact(id: id)
            return try valueContact(read.snapshot(native), imageData: read.imageData(native))
        }
        try runtime.load()
        let serializer: AnyClass = try runtime.requireClass("CNContactVCardSerialization")
        let selector = NSSelectorFromString("dataWithContacts:error:")
        typealias Serialize =
            @convention(c) (AnyObject, Selector, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
        var error: NSError?
        let result = ContactsRuntime.msgSend(Serialize.self)(serializer, selector, contacts as NSArray, &error)
        if let error { throw PlatformError.fetchFailed("vCard export failed: \(error.localizedDescription)") }
        guard let data = result as? Data else { throw PlatformError.fetchFailed("vCard export returned no data.") }
        return data
    }

    /// A Contacts value object (CNMutableContact) with the snapshot's fields, for vCard export.
    func valueContact(_ snapshot: ContactSnapshot, imageData: Data?) throws -> AnyObject {
        let contact = try runtime.makeMutableContact(.vCard)
        try write(snapshot, to: contact, base: ContactSnapshot(id: ""), native: [:], flavor: .vCard)
        if let imageData { try runtime.setValue(imageData as NSData, "imageData", on: contact) }
        return contact
    }

    /// Sets (or with nil, removes) the contact's photo (AddressBook's ABPerson setImageData:).
    public func setImage(id: String, data: Data?) throws -> ContactSnapshot {
        _ = try read.rawContact(id: id)
        guard let book = try runtime.legacyAddressBook() else {
            throw PlatformError.privateBackendUnavailable("Photos need the user's address book.")
        }
        try runtime.loadImageSupport()
        try runtime.legacySend(try runtime.legacyRecord(id, in: book), "setImageData:", data as NSData?)
        try runtime.saveLegacy(book)
        let result = try MutationVerification.readback(type: "contact", id: id) { try read.fetchContact(id: id) }
        guard result.hasImage == (data != nil) else {
            throw PlatformError.saveFailed("The photo change was not verified. Inspect before retrying.")
        }
        return result
    }

    /// Links cards so Contacts shows them as one (Card > Link Cards). Returns the link id.
    public func link(ids: [String]) throws -> String {
        guard ids.count >= 2 else { throw PlatformError.invalidArgument("Link at least two contacts.") }
        for id in ids { _ = try read.rawContact(id: id) }
        guard let book = try runtime.legacyAddressBook() else {
            throw PlatformError.privateBackendUnavailable("Linking needs the user's address book.")
        }
        let people = try ids.map { try runtime.legacyRecord($0, in: book) }
        for person in people.dropFirst() {
            typealias Link = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
            let selector = NSSelectorFromString("linkPerson:toPerson:")
            guard book.responds(to: selector) else {
                throw PlatformError.privateBackendUnavailable("AddressBook lacks linkPerson:toPerson:.")
            }
            ContactsRuntime.msgSend(Link.self)(book, selector, person, people[0])
        }
        try runtime.saveLegacy(book)
        let links = try ids.map { id in
            try MutationVerification.readback(type: "contact", id: id) { try read.linkIdentifier(id: id) }
        }
        guard let first = links.first, let link = first, links.allSatisfy({ $0 == link }) else {
            throw PlatformError.saveFailed("Linking the cards was not verified. Inspect before retrying.")
        }
        return link
    }

    /// Removes a card from its link (the card itself is kept).
    public func unlink(id: String) throws {
        _ = try read.rawContact(id: id)
        guard let book = try runtime.legacyAddressBook() else {
            throw PlatformError.privateBackendUnavailable("Unlinking needs the user's address book.")
        }
        try runtime.legacySend(book, "unlinkPerson:", try runtime.legacyRecord(id, in: book))
        try runtime.saveLegacy(book)
        let link = try MutationVerification.readback(type: "contact", id: id) { try read.linkIdentifier(id: id) }
        if let link, try read.linkedIDs(link: link).contains(where: { $0 != id }) {
            throw PlatformError.saveFailed("Unlinking the card was not verified. Inspect before retrying.")
        }
    }

    /// Makes the contact the "me" card.
    public func setMeCard(id: String) throws {
        _ = try read.rawContact(id: id)
        if let book = try runtime.legacyAddressBook() {
            try runtime.legacySend(book, "setMe:", try runtime.legacyRecord(id, in: book))
            try runtime.saveLegacy(book)
        } else {
            let identifier = try runtime.nativeIdentifier(id, group: false)
            try save { request in try self.send(request, "setMeCardIdentifier:", identifier) }
        }
        let verified = try MutationVerification.readback(type: "contact", id: id) { try read.meContactID() }
        guard verified == id else {
            throw PlatformError.saveFailed("The me card change was not verified. Inspect before retrying.")
        }
    }

    /// Group membership goes through the AddressBook model (ABGroup addMember:/removeMember:);
    /// an injected in-memory store uses its save request instead.
    private func changeMembership(_ contact: AnyObject, _ group: AnyObject, member: Bool) throws {
        guard let book = try runtime.legacyAddressBook() else {
            try save { request in
                try self.send(request, member ? "addMember:toGroup:" : "removeMember:fromGroup:", contact, group)
            }
            return
        }
        let person = try runtime.legacyRecord(runtime.identifier(of: contact), in: book)
        let legacyGroup = try runtime.legacyRecord(runtime.identifier(of: group), in: book)
        try runtime.legacySend(legacyGroup, member ? "addMember:" : "removeMember:", person)
        try runtime.saveLegacy(book)
    }

    private func verifyMembership(_ contactID: String, in groupIDs: [String]) throws {
        for groupID in groupIDs {
            let member = try MutationVerification.readback(type: "group", id: groupID) {
                try read.memberIDs(groupID: groupID).contains(contactID)
            }
            guard member else {
                throw PlatformError.saveFailed(
                    "Contact \(contactID) was saved, but adding it to group \(groupID) was not verified. Inspect before retrying."
                )
            }
        }
    }

    /// Applies a partial edit. Untouched labeled values keep their native identity.
    public func updateContact(id: String, edit: ContactEdit) throws -> ContactSnapshot {
        let original = try read.rawContact(id: id, complete: true)
        let current = try read.snapshot(original)
        let expected = try edit.applied(to: current)
        guard expected.editable != current.editable else { return current }
        let contact = try mutableCopy(original)
        try write(expected, to: contact, base: current, native: nativeEntries(original), flavor: .addressBook)
        try save { request in try self.send(request, "updateContact:", contact) }
        return try verify(id: id, expected: expected)
    }

    public func deleteContact(id: String) throws {
        let contact = try mutableCopy(read.rawContact(id: id, complete: true))
        try save { request in try self.send(request, "deleteContact:", contact) }
        try MutationVerification.absence(id: id, type: "contact") { try read.rawContact(id: id) }
    }

    /// Parses vCard data without saving.
    public func parseVCard(_ data: Data) throws -> [VCardEntry] {
        let contacts = try read.parseVCard(data)
        let cards = Self.splitCards(data)
        return try contacts.enumerated().map { index, native in
            VCardEntry(
                snapshot: try read.snapshot(native), native: native,
                vCard: cards.count == contacts.count ? cards[index] : nil)
        }
    }

    /// One BEGIN:VCARD ... END:VCARD block per card.
    static func splitCards(_ data: Data) -> [Data] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var cards: [Data] = []
        var current: [Substring] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.uppercased().hasPrefix("BEGIN:VCARD") { current = [] }
            current.append(line)
            if line.uppercased().hasPrefix("END:VCARD") {
                cards.append(Data(current.joined(separator: "\r\n").appending("\r\n").utf8))
                current = []
            }
        }
        return cards
    }

    /// Saves one parsed vCard contact as a new contact (all decoded fields, photo included).
    /// The user's address book imports through AddressBook's own vCard reader (as Contacts'
    /// Import does); an injected store saves the decoded fields.
    public func importContact(_ entry: VCardEntry, groupIDs: [String] = []) throws -> ContactSnapshot {
        guard let book = try runtime.legacyAddressBook(), let card = entry.vCard else {
            var draft = entry.snapshot
            if !runtime.notesAccessible { draft.note = nil }
            return try createContact(draft, groupIDs: groupIDs)
        }
        let groups = try groupIDs.map(read.rawGroup)
        let personClass: AnyClass = try runtime.requireClass("ABPerson")
        guard let allocated = ObjCSendId(personClass, NSSelectorFromString("alloc")) as AnyObject?,
            let person = ObjCSendIdIdArg(
                allocated, NSSelectorFromString("initWithVCardRepresentation:"), card as NSData)
                as AnyObject?
        else { throw PlatformError.invalidArgument("AddressBook could not read this vCard.") }
        if !runtime.notesAccessible {
            // Never write a note this process could not read back (or later preserve).
            typealias Remove = @convention(c) (AnyObject, Selector, NSString) -> Bool
            let remove = NSSelectorFromString("removeValueForProperty:")
            if person.responds(to: remove) { _ = ContactsRuntime.msgSend(Remove.self)(person, remove, "Note") }
        }
        typealias Add =
            @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        var error: NSError?
        let added = ContactsRuntime.msgSend(Add.self)(book, NSSelectorFromString("addRecord:error:"), person, &error)
        try runtime.checkServiceError(error)
        guard added else { throw PlatformError.saveFailed("AddressBook did not add the imported card.") }
        // The vCard reader keeps the photo aside; attach it to the new record explicitly.
        if let image = try read.imageData(entry.native) {
            try runtime.loadImageSupport()
            try runtime.legacySend(person, "setImageData:", image as NSData)
        }
        try runtime.saveLegacy(book)
        guard let id = runtime.stringValue(from: person, selectors: ["uniqueId"]) else {
            throw PlatformError.saveFailed("The imported card has no id. Inspect before retrying.")
        }
        var expected = entry.snapshot
        expected.note = nil
        let result = try verify(id: id, expected: expected)
        for group in groups { try changeMembership(try read.rawContact(id: id), group, member: true) }
        try verifyMembership(id, in: groupIDs)
        return result
    }

    private func verify(id: String, expected: ContactSnapshot) throws -> ContactSnapshot {
        let result = try MutationVerification.readback(type: "contact", id: id) { try read.fetchContact(id: id) }
        var want = expected.editable
        var got = result.editable
        if got.note == nil || want.note == nil {  // notes not exposed, or not requested
            want.note = nil
            got.note = nil
        }
        if want.note == "" { want.note = nil }
        if got.note == "" { got.note = nil }
        want.hasImage = false
        got.hasImage = false
        // The address book derives a profile URL from service + username when none was given,
        // and normalizes known service names ("twitter" -> "Twitter") and empty labels.
        for (index, profile) in want.socialProfiles.enumerated() where index < got.socialProfiles.count {
            let stored = got.socialProfiles[index]
            if profile.url.isEmpty { want.socialProfiles[index].url = stored.url }
            if profile.service.caseInsensitiveCompare(stored.service) == .orderedSame {
                want.socialProfiles[index].service = stored.service
            }
            if (profile.label ?? "").isEmpty && (stored.label ?? "").isEmpty {
                want.socialProfiles[index].label = stored.label
            }
        }
        guard want == got else {
            throw PlatformError.saveFailed(
                "Contact save returned success, but the stored fields did not match the request ("
                    + Self.differingFields(want, got).joined(separator: ", ") + "). Inspect before retrying.")
        }
        return result
    }

    /// Names (never values) of the top-level fields that differ.
    static func differingFields(_ a: ContactSnapshot, _ b: ContactSnapshot) -> [String] {
        func fields(_ value: ContactSnapshot) -> [String: Any] {
            guard let data = try? JSONEncoder().encode(value),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return object
        }
        let left = fields(a)
        let right = fields(b)
        return Set(left.keys).union(right.keys).sorted().filter { key in
            !((left[key] as? NSObject)?.isEqual(right[key]) ?? (right[key] == nil))
        }
    }

    // MARK: Native encoding

    private static let collections = [
        "phoneNumbers", "emailAddresses", "urlAddresses", "postalAddresses", "dates", "contactRelations",
        "socialProfiles",
    ]

    private func nativeEntries(_ contact: AnyObject) -> [String: [AnyObject]] {
        var result: [String: [AnyObject]] = [:]
        for key in Self.collections {
            result[key] = runtime.objectArray(runtime.value(key, of: contact)) ?? []
        }
        return result
    }

    /// Writes every field of `target` that differs from `base`. Labeled values equal to one in
    /// `base` reuse its native entry (keeping its identifier); others are created.
    private func write(
        _ target: ContactSnapshot, to contact: AnyObject, base: ContactSnapshot, native: [String: [AnyObject]],
        flavor: ContactsRuntime.Flavor
    ) throws {
        for field in ContactField.allCases {
            let value = target[keyPath: field.keyPath]
            let changed = field == .note ? target.note != base.note : value != base[keyPath: field.keyPath]
            guard changed else { continue }
            if field == .note, target.note == nil { continue }
            if field == .note, flavor == .addressBook, !runtime.notesAccessible {
                throw AgentError(
                    code: "notes_unavailable",
                    message: "macOS does not let this CLI read or write contact notes (Apple reserves them for apps "
                        + "with the Contacts notes entitlement).",
                    hint: "Retry without note; the existing note is kept unchanged.")
            }
            try runtime.setValue(value as NSString, field.rawValue, on: contact)
        }
        if target.kind != base.kind {
            try runtime.setValue(NSNumber(value: target.kind == .organization ? 1 : 0), "contactType", on: contact)
        }
        if target.birthday != base.birthday {
            try runtime.setValue(target.birthday.map(runtime.makeDateComponents), "birthday", on: contact)
        }
        let runtime = self.runtime
        func labeled(_ label: String?, _ value: AnyObject) throws -> AnyObject {
            try runtime.makeLabeledValue(label: label, value: value, flavor)
        }
        try collection("phoneNumbers", target.phones, base.phones, native, contact) {
            try labeled($0.label, runtime.makePhoneNumber(string: $0.value, flavor))
        }
        try collection("emailAddresses", target.emails, base.emails, native, contact) {
            try labeled($0.label, $0.value as NSString)
        }
        try collection("urlAddresses", target.urls, base.urls, native, contact) {
            try labeled($0.label, $0.value as NSString)
        }
        try collection("postalAddresses", target.addresses, base.addresses, native, contact) {
            try labeled($0.label, runtime.makePostalAddress($0, flavor))
        }
        try collection("dates", target.dates, base.dates, native, contact) {
            try labeled($0.label, runtime.makeDateComponents($0.day))
        }
        try collection("contactRelations", target.relations, base.relations, native, contact) {
            try labeled($0.label, runtime.makeRelation(name: $0.value, flavor))
        }
        try collection("socialProfiles", target.socialProfiles, base.socialProfiles, native, contact) {
            try labeled($0.label, runtime.makeSocialProfile($0, flavor))
        }
    }

    private func collection<Value: Equatable>(
        _ key: String, _ target: [Value], _ base: [Value], _ native: [String: [AnyObject]], _ contact: AnyObject,
        make: (Value) throws -> AnyObject
    ) throws {
        guard target != base else { return }
        let existing = native[key] ?? []
        var unused = Array(zip(base, existing).enumerated().map { ($0.offset, $0.element.0, $0.element.1) })
        let entries = try target.map { value -> AnyObject in
            if let index = unused.firstIndex(where: { $0.1 == value }) {
                return unused.remove(at: index).2
            }
            return try make(value)
        }
        try runtime.setValue(entries as NSArray, key, on: contact)
    }

    private func mutableCopy(_ object: AnyObject) throws -> AnyObject {
        guard object.responds(to: NSSelectorFromString("mutableCopy")),
            let copy = ObjCSendId(object, NSSelectorFromString("mutableCopy")) as AnyObject?
        else {
            throw PlatformError.privateBackendUnavailable(
                "Contacts service value cannot create a mutable save DTO.")
        }
        return copy
    }

    /// Sends a save-request message with one or two object arguments (nil = default account).
    private func send(_ request: AnyObject, _ name: String, _ first: AnyObject, _ second: AnyObject?) throws {
        let selector = NSSelectorFromString(name)
        guard request.responds(to: selector) else {
            throw PlatformError.privateBackendUnavailable("Contacts save request lacks \(name).")
        }
        typealias Two = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
        ContactsRuntime.msgSend(Two.self)(request, selector, first, second)
    }

    private func send(_ request: AnyObject, _ name: String, _ object: AnyObject) throws {
        let selector = NSSelectorFromString(name)
        guard request.responds(to: selector) else {
            throw PlatformError.privateBackendUnavailable("Contacts save request lacks \(name).")
        }
        ObjCSendVoidId(request, selector, object)
    }

    private func save(_ build: (AnyObject) throws -> Void) throws {
        let mapper = try runtime.makeDataMapper()
        let request = try runtime.makeSaveRequest()
        try build(request)
        let saveSelector = NSSelectorFromString("executeSaveRequest:error:")
        guard mapper.responds(to: saveSelector) else {
            throw PlatformError.privateBackendUnavailable("ABCNContactStore lacks the save interface.")
        }
        typealias Save =
            @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        var error: NSError?
        let succeeded = ContactsRuntime.msgSend(Save.self)(mapper, saveSelector, request, &error)
        try runtime.checkServiceError(error)
        guard succeeded else {
            throw PlatformError.saveFailed("Private Contacts service rejected the save without an error.")
        }
    }

    private func validatedName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlatformError.invalidArgument("Group name cannot be empty.") }
        return trimmed
    }
}
