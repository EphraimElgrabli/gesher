# Contacts private macOS backend

Data operations use **ABCNContactStore**, a private NSObject class in AddressBookCore (not a
CNContactStore subclass), created with `initWithLegacySharedAddressBook`. The runtime checks the
private TCC state (`CNAuthorizationContext`) and that the store's data mapper has a real
address-book binding (`_addressBook`) before any call: a missing binding is
`private_backend_unavailable`, never an empty address book.

The store returns **ABCN value objects** (`ABCNContact`: `firstName`, `lastName`, `companyName`,
`birthdayComponents`, `relatedNames`, `otherDateComponents`, `displayStyle`, ...; `ABCNLabeledValue`,
`ABCNPostalAddress`, `ABCNSocialProfile`, `ABCNGroup`, identifiers as `ABCNContactIdentifier` /
`ABCNGroupIdentifier` with a `stringValue`). The runtime reads and builds them with CNContact key
names translated per class (`ContactsRuntime.addressBookKeys`); unset ABCN text and lists are nil
(empty), whereas a key without a getter is unavailable (an error).

| Need | Private interface |
|---|---|
| contacts | `contactsMatchingPredicate:error:` with nil (all), `+[ABCNContact predicateForIdentifiers:]`, `predicateForMembersOfGroupWithIdentifier:` |
| groups | `groupsMatchingPredicate:error:` (nil = all) |
| me card | read `fetchIdentifierForMeCard:` (an `ABCNContactIdentifier`); write `-[ABAddressBook setMe:]` |
| contact and group writes | `ABCNSaveRequest` `addContact:toAccountWithIdentifier:` (nil = default account), `updateContact:`, `deleteContact:`, `addGroup:…`, `updateGroup:`, `deleteGroup:`, then `executeSaveRequest:error:` with `ABCNMutableContact` / `ABCNMutableGroup` |
| group membership | `-[ABGroup addMember:]` / `removeMember:` + `saveAndReturnError:` (`ABCNSaveRequest addMember:toGroup:` and `ABCNContactStore addMember:toGroup:error:` are no-op stubs) |
| photo | `-[ABPerson setImageData:]` (AppKit loaded so AddressBook also stores the cropped large image); read `hasCustomImage` then `imageData` |
| link / unlink cards | `-[ABAddressBook linkPerson:toPerson:]`, `unlinkPerson:`; read `linkIdentifier` |
| vCard export / import | `-[ABPerson _vCardRepresentationAsStringIncludeNotes:includePhotos:]` / `initWithVCardRepresentation:` + `addRecord:error:` (AddressBook's own reader and writer); `CNContactVCardSerialization` only parses for previews and duplicate checks |

The legacy `ABAddressBook sharedAddressBook` is the same in-process address book the ABCN store
was created over; records are looked up by the same unique ids (`…:ABPerson`, `…:ABGroup`) and
refreshed before a change (a long-lived MCP process may hold stale records).

**Notes.** macOS reserves contact notes for apps with the Contacts notes entitlement
(`CNAuthorizationContext isNotesAccessGranted`). Without it AddressBookCore still converts every
property and faulting a note raises (CoreData 134092), aborting the whole fetch. The runtime then
makes `ABCNNoteDescription` neither read nor write in this process: notes are omitted and never
changed; setting one is `notes_unavailable`.

**Alert tones.** Converting a stored contact reads every property; its ringtone and text tone
(`ABCNAlertTones`/`RingTone`/`TextTonePropertyDescription`) come from a Core Data relationship
that is not prefetched, so each contact costs one synchronous NSXPCStore round trip (most of a
whole-address-book fetch: seconds for a few thousand cards). Tones are never output, so the
runtime gates those reads: fetches skip them, and a contact fetched to be saved back (update,
delete) reads them as usual (`ContactsRuntime.withAlertTones`). The store is created once per
process (it wraps the process-wide shared address book; records are still re-read per fetch).

Keys are read with KVC only after `isKeyAvailable:` on CNContact values. Phones and emails must
be available; an undecodable value is an error, never dropped. Updates rebuild only the changed
collections and reuse untouched labeled values so their identifiers survive.

## Verification status

- Tests use `ABCNContactStore memoryBackedContactStore` (pure in-memory) for contact create,
  update (all field kinds, single-value add/remove, clearing), delete, vCard round trip, group
  create/rename/delete and bulk-delete backups. It has no AddressBook model, so membership, me
  card, photos and links are verified live only.
- Live (macOS 27, `QA-gesher-*` fixtures, CLI and MCP `tools/call`): every tool, all field
  types, single-value add/remove, groups, photo set/clear, link/unlink, me set and restore,
  birthdays, duplicates, vCard export/import with photo; fixtures deleted and verified gone.
- Do **not** use `legacyMemoryBackedContactStore` in tests: it opens the user's AddressBook
  database through contactsd.
- Live use needs Contacts permission for `contacts-cli` itself: it runs as its own responsible
  process (see [permissions](../../docs/permissions.md)), so the launching host needs no
  address-book entitlement.

## Alternatives rejected

`CN.defaultDataMapperClass` (CNCoreDataMapperX) has a nil account collection without contactsd
persistence (NSCocoaErrorDomain/4097) and silently falls back to in-memory data; CNXPCDataMapper
needs com.apple.contactsd and returns a communication error. Neither is used as a fallback.
