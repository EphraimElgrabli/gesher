# Calendar

`calendar-cli` reads your agenda, finds free time, and creates, moves and deletes events and
calendars. Every command is also an MCP tool in `calendar-cli mcp`.

**How it works.** Calendar is reached through the private CalendarDaemon (CAD) XPC protocol: `EKDaemonConnection`'s
`CADOperationProxy` for reads (`CADObjects:getPropertiesWithNames:`, `CADEventPredicate`
occurrence fetches) and `CADDatabaseCommitDeletes:updatesAndInserts:...` transactions for
writes. EventKit is loaded only to resolve the private connection classes; no public EventKit
store, AppleScript or database file is used. See [PRIVATE_BACKEND.md](PRIVATE_BACKEND.md).

```sh
calendar-cli agenda                                   # today; also tomorrow, week, next-week, friday, --from/--to
calendar-cli agenda week --calendar Work --format pretty
calendar-cli event search dentist
calendar-cli event get 'Team sync'                    # repeat rule, alerts, attendees, address, travel time
calendar-cli free-slots tomorrow --duration 45 --working-hours 09:00-17:00 --buffer 10
calendar-cli free-busy next-week
calendar-cli event create 'Dentist' --start 'thursday 10:00' --duration 45 --location Clinic --alerts 1h --alerts 1d
calendar-cli event create Standup --start 'monday 9:30' --duration 15 --repeat weekdays
calendar-cli event create Trip --start 2026-12-01 --end 2026-12-04 --calendar Personal   # all-day, end inclusive
calendar-cli event update Standup --on tomorrow --scope this --start 'tomorrow 10:00'
calendar-cli event update Standup --scope future --repeat-days MO,WE
calendar-cli event invite 'Planning' --add 'Dana <dana@example.com>'   # emails a real invitation
calendar-cli event delete 'Old sync' --scope all
calendar-cli event batch --input changes.json         # {"create":[...],"update":[...],"delete":[...]}
calendar-cli invitation list
calendar-cli invitation respond 'Quarterly review' --response accept
calendar-cli calendar list --writable
calendar-cli calendar create 'Side project' --color purple --account iCloud
calendar-cli calendar update 'Side project' --title 'Side projects' --color '#3B82F6'
calendar-cli calendar delete 'Side projects'
```

Layout: `Sources/CalendarCli/CalendarCli.swift` declares the app and its context (calendar and
event resolution, defaults, conflicts); `Sources/CalendarCli/Operations/` holds the operations,
input types and agent-facing output models; `Sources/CalendarCore/` holds the daemon session,
change sets, repositories, native snapshots and the RRULE ⇄ native recurrence mapping.

## Conventions

- Output times are ISO 8601 in the user's time zone with offset. All-day events use plain days
  and `end` is the last day (inclusive). `timeZone` appears in `event get` only when the event's
  zone differs from the user's.
- Events are selected by id (`x-apple-eventkit:///Event/p12`, occurrences `...#<epoch>`) or by
  title among events from 2 weeks ago to 3 months ahead (`on` narrows it to a day). A series is
  offered once, at its next occurrence. Destructive operations use exact names.
- Defaults: calendar = explicit > `calendar.calendar` in `~/.config/gesher/config.json` >
  Calendar's default for new events > the only writable calendar. Scheduling considers every
  calendar except subscribed, birthday and holiday ones (override with `calendar` or
  `calendar.scheduling`); working hours `calendar.workingHours` (default 09:00-18:00); workdays
  `calendar.workdays` (default: the locale's weekdays).
- Create/update return `conflicts` with overlapping busy events (all-day, free and declined
  events do not count); `rejectConflicts` turns that into a `conflict` error.
- Deleting more than 5 events (delete, batch, or a calendar holding them) first writes a JSON
  snapshot to `~/.config/gesher/backups/` and returns its path in `backup`.
- Every write is read back through a new daemon connection; deletes check native absence.
- Only `event invite` adds or removes attendees. iCloud, Exchange and CalDAV accounts email the
  invitation or cancellation from the user's address, so it is declared destructive (MCP clients
  ask before running it); `event create`, `event update` and `event batch` never invite anyone.

## Permission

Reads need **Full Access** to Calendars for `calendar-cli` itself (it runs as its own responsible
process, whatever app launches it). `calendar-cli permissions --request` shows the "Allow Full
Access" dialog. Write-only access (`eventAuthorization` 4) is reported as `write_only` with the
fix: System Settings > Privacy & Security > Calendars > calendar-cli > Full Access.
