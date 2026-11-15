# Contacts

`contacts-cli` finds, reads and edits Apple Contacts and groups through the private
AddressBookCore store (`ABCNContactStore` + `ABCNSaveRequest`, and its AddressBook model for
membership, photos, links and My Card). `contacts-cli mcp` serves the same
operations as MCP tools. Public `CNContactStore`, AppleScript and database writes are not used.
See [PRIVATE_BACKEND.md](PRIVATE_BACKEND.md).

`contacts-cli permissions --request` asks macOS for Contacts access for `contacts-cli` itself
(it is its own responsible process, whatever app launches it). Full Disk Access is not Contacts
access. Contact notes are not readable or writable (Apple reserves them for entitled apps).

## Commands (MCP tool = words joined by `_`)

| Command | What it does |
|---|---|
| `search QUERY [--field any\|name\|phone\|email\|company\|note] [--group G]` | ranked matches |
| `list [GROUP] [--limit N --offset N]` | alphabetical, paginated |
| `get CONTACT...` | full cards with labels, groups, `me` flag |
| `me` | the user's own card |
| `me set CONTACT` | make a card "My Card" |
| `photo CONTACT --file IMG \| --clear` | set or remove the photo |
| `link CONTACT CONTACT...` / `unlink CONTACT` | link duplicate cards (Card > Link Cards) or separate one |
| `create --first-name ... --phone 'work: ...' [--group G]` | new card; reports `similar` existing ones |
| `update CONTACT [fields] [--add-phone/--remove-phone ...]` | partial edit, value by value |
| `delete CONTACT...` | exact selectors; > 5 writes a vCard backup first |
| `birthdays [--days 30] [--dates] [--group G]` | upcoming, with age |
| `duplicates [--group G]` | read-only duplicate suggestions |
| `export CONTACT... \| --group G \| --all [--file F]` | vCard 3.0, inline or to a new `.vcf` file (never replaces a file) |
| `import FILE \| --vcard TEXT [--group G] [--dry-run]` | skips existing contacts |
| `group list \| create \| rename \| delete \| add \| remove` | groups and membership |

```sh
contacts-cli search 054-123
contacts-cli get 'Dana Levi' --format pretty
contacts-cli update Dana --add-phone 'work: +972 4 123 4567' --remove-email old@example.com
contacts-cli create --first-name Noa --birthday 05-17 --related 'spouse: Dana' --group Family
contacts-cli birthdays --days 14
contacts-cli group add --group Family Dana Noa
```

Run `contacts-cli <command> --help` or `contacts-cli schema <command>` for every parameter.

## Conventions

- **Selectors**: id, exact email, phone number in any format (`+972 54-123-4567`, `054-1234567`,
  `00972541234567` match; international prefix and trunk 0 are ignored), or a name (Hebrew and
  diacritics safe; "Family Given", nickname and company also match). Ambiguity fails with
  `candidates`. `update`, `delete`, `group remove/rename/delete` require an id or exact name.
- **Values** are `label: value`. Labels: mobile, iphone, home, work, main, home fax, work fax,
  pager, other, school, homepage, anniversary, mother/father/parent/brother/sister/child/friend/
  spouse/partner/assistant/manager, or any custom label. Addresses: `street; city; state; postal
  code; country` (or `street, city, country`). Dates: `YYYY-MM-DD`, `MM-DD` without a year.
- **update** changes only what you pass. `--phone ...` replaces all phones (`''` = none);
  `--add-*` / `--remove-*` touch single values and keep the others with their native identity.
  A removal that matches nothing is `invalid_argument` and nothing is saved.
- **Backups**: deleting more than 5 contacts writes a `.vcf`, deleting more than 5 groups or
  removing more than 5 members a `.json`, to `~/.config/gesher/backups/` before any change.
- **Verification**: every write is read back from the store; a mismatch is `save_failed`
  ("may have committed; read before retrying").

## Limits

- Notes are omitted (`notes_unavailable` when setting one); the Hebrew-calendar birthday
  (read-only `altBirthday`) is not writable; instant-message handles are not exposed. Linking
  keeps both cards (no destructive merge).
- No revision tokens: the store exposes none, so there is no `ifRevision` precondition.
- Unit tests run against the private in-memory store (no user data). Membership, My Card,
  photos and links need the AddressBook model and were verified live on `QA-gesher-*`
  fixtures (see PRIVATE_BACKEND.md).
