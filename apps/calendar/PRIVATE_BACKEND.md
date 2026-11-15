# Calendar private backend

CalendarDaemon (CAD) over `EKDaemonConnection` / `CADOperationProxy`. EventKit is loaded only to
resolve those private connection classes; `EKEventStore` and the public wrappers never read or
write data.

## Native transport

- Reads: `CADDatabaseGet{Sources,Calendars}WithFaultedProperties:reply:` (IDs + property rows),
  `CADObjects:getPropertiesWithNames:reply:` (rows via `loadedValues`), occurrences through
  `CADEventPredicate` + `CADDatabaseFetchCalendarItemsWithPredicate:entityType:...` (wrappers
  carry `objectID` and `occurrenceDate`), `CADObjectsExist:reply:` (replies with missing IDs),
  `CADDatabaseGetDefaultCalendarForNewEventsInDelegateSource:withReply:`.
- Writes: one `CADDatabaseCommitDeletes:updatesAndInserts:options:andFetchChangesSinceTimestamp:withReply:`
  per operation (`CalendarChangeSet`), keyed by `CADObjectID`; inserts use temporary IDs and the
  reply maps them to permanent ones. Relationship values are `CADObjectID`s, never the serialized
  dictionaries returned by reads.
- Entity types: Calendar 1, Event 2, Alarm 4, RecurrenceRule 5, Source 6, Attendee 7,
  Organizer 8, ExceptionDate 10, Location 14 (from `EKPersistent*` classes on macOS 27).
- Event keys: `unlocalizedTitle`, `startDateRaw`/`endDateRaw`, `isAllDay`,
  `startTimeZoneName`/`endTimeZoneName` (`_float` for all-day), `structuredLocationWithoutPrediction`
  (Location: `title`, `address`, `latitude`, `longitude`, `calendarItemOwner`), `notes`, `URLString`,
  `availability` (0 busy, 1 free, 2 tentative, 3 unavailable), `travelTime` (seconds),
  `allAlarmsSet` (Alarm: `relativeOffset` seconds or `absoluteDate`, `calendarItemOwner`),
  `recurrenceRulesSet` + `hasRecurrenceRules` (RecurrenceRule: `frequencyRaw` 1 daily … 4 yearly,
  `interval`, `count`, `endDate`, `specifier`, `owner`), `attendeesRaw`/`selfAttendee`/`organizer`
  (`emailAddress`, `displayNameRaw`, `statusRaw`, `participantRole`, `isCurrentUser`),
  `selfParticipantStatusRaw`, `originalItem`/`originalStartDate`/`detachedItems` (detached
  occurrences), `ekExceptionDates` (ExceptionDate: `date`, `owner`).
- Recurrence `specifier`: `D=` weekdays (`0MO` every, `+2TU` second, `-1FR` last), `M=` month
  days, `O=` months, `S=` set positions, `;`-separated. Mapping confirmed against EventKit-built
  rules on this macOS (research only, not used at runtime).
- Calendar `flags`: 0x1 read-only, 0x4 immutable, 0x8 subscribed, 0x1000 / 0x1000000 holiday.
- Scopes: `this` inserts a detached event (`originalItem`, `originalStartDate`, master
  `uniqueID`) or, for deletes, an ExceptionDate; `future` ends the master rule one second before
  the occurrence and inserts a new series; `all` edits the master (shifted by the selected
  occurrence's offset).

## Verification status

- 2026-10-16 (previous adapter): QA calendar create/rename/recolor/delete, event
  create/read/update/window query/delete, location and relative alerts were verified live.
- 2026-11-03 (this adapter, macOS 27, Full Access): read-only, every occurrence from a year ago
  to a year ahead decoded and fetched by id with no failure. On a `QA-gesher-calendar` fixture
  (iCloud) through the CLI and MCP `tools/call`: calendar create/update/delete, timed, all-day,
  other-time-zone and weekly events, alerts, location/address/coordinates, travel time, conflicts
  (warn and reject), search, this/future/all edits and deletes, free_slots, free_busy, batch,
  invite/uninvite (`example.invalid`; now the separate `event invite` tool), invitation list and a refused respond. Responding to a
  real invitation needs one from another account and was not exercised.
- Relations inside one database arrive as dictionary representations without `dbID`; they take
  the event's database. All-day ends are stored as the last second of the last day (as Calendar
  stores them). "All events" edits are applied to detached occurrences too (their times kept).
- Attendees on CalDAV/iCloud may be sent as real invitations by the account; test them only on a
  local calendar with `example.invalid` addresses.

## Limits

- Calendar needs Full Access. `TCCAccessRequest` asks only for write-only, and calaccessd answers
  `CADDatabaseRequestAccessForEntityType:desiredFullAccess:...` with error 1019 for clients without
  an app bundle, so `permissions --request` asks tccd for the full-access right directly
  (`tcc_server_message_request_authorization_change`, right 2), as calaccessd does.
- Setting Calendar's system default calendar (`CADDatabaseSetDefaultCalendarForNewEvents:...`)
  is not exposed: it changes an owner preference. Use `calendar.calendar` in the config file.
- Moving single occurrences between calendars is rejected (whole series only).
- macOS versions other than the tested one need their own runtime verification.
