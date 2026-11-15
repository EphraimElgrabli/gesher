# Reminders

`reminders-cli` reads and manages your reminders: lists, sections, tags, smart lists, templates
and attachments. Every command is also an MCP tool in `reminders-cli mcp`.

**How it works.** Built on the private
`ReminderKit` / `ReminderKitInternal` frameworks. No EventKit, AppleScript or database access:
reads go through `REMStore`, writes through `REMSaveRequest` change items, and every write is
read back through a fresh store before it is reported.

## Operations

| Tool (CLI words) | What it does |
|---|---|
| `lists` | Sidebar: smart-view counts (today, scheduled, overdue, flagged, all, assigned, completed), groups, lists with open/overdue/flagged counts, color, emoji, sharing; `--sections` adds sections |
| `tasks` | Any view (`open`, `today`, `scheduled`, `overdue`, `flagged`, `assigned`, `completed`, `all`), scoped by list/group, section, tags, parent, date range (`--from/--to`), full-text search |
| `task get` | Everything about tasks: subtasks, alarms, recurrence, early alert, attachments, assignee, dates |
| `tags` | Tags in use with open/completed counts |
| `task create` | One or many tasks: shared fields for several titles, or per-task `items` (later items may name earlier ones as `parent`) |
| `task update` | Rename, due, notes, URL, priority, flag, tags (set/add/remove), recurrence, alarms, early alert, location; move to list/section/parent (indent/outdent), reorder (`position`, `before`, `after`), `clear` fields; per-task `items` |
| `task complete` | Complete (recurring tasks advance like the app and report `nextDue`) or `--undo` |
| `task delete` | Delete by exact name or id (subtasks go with their parent) |
| `task restore` | Undo a bulk change from its backup: recreate deleted tasks, revert changed ones |
| `deleted-tasks` / `task purge` | Recently Deleted (about 30 days), and erasing tasks from it for good, as the app's Delete there |
| `list create` / `list update` / `list delete` | Lists and groups (folders): create (`--kind group`), rename, color, emoji/symbol, move into a group or `--ungroup`; deleting a group keeps its lists |
| `section create` / `section update` / `section delete` | Sections: add several, rename, move to a position; deleting keeps the tasks |
| `attachment add` / `attachment remove` / `attachment export` | Images (shown as pictures) and files from local paths (hidden, system and key files refused; shared lists need `--confirm-shared`); remove by id or number; copy them out |
| `smart-lists` / `smart-list create` / `smart-list update` / `smart-list delete` | Custom smart lists and their filters (tags in/out, date, time, priority, flag, location, lists; all/any); `tasks --smart-list` lists what the daemon matches |
| `templates` / `template create` / `template apply` / `template delete` | Save a list as a template (tasks, subtasks, sections), make a new list from it |

Built-ins: `doctor`, `permissions`, `schema [op]`, `mcp`, `--help`, `<op> --help`.

```sh
reminders-cli lists --sections
reminders-cli tasks --view today
reminders-cli tasks dentist                       # search titles, notes, tags
reminders-cli task create 'Submit report' --due 'friday 17:00' --priority high --early-alert 1d
reminders-cli task create 'Water plants' --repeats 'every 3 days' --due today
reminders-cli task update 'Buy milk' --list Groceries --section Dairy
reminders-cli task update Passport --parent Pack          # indent; --clear parent to outdent
reminders-cli task complete 'Buy milk' 'Call the bank'
reminders-cli list create Home --kind group --lists Groceries
reminders-cli smart-list create 'Work week' --filter '{"tags":["work"],"date":"next 7 days"}'
reminders-cli tasks --smart-list 'Work week'
reminders-cli template create Packing --name 'Trip checklist' && reminders-cli template apply 'Trip checklist' --name Rome
reminders-cli attachment add --task 'Fix the sink' ~/Desktop/leak.jpg
```

## Conventions

- **Selectors** take a name or an id (`REMCDList:…`, `REMCDListSection:…`, `REMCDReminder:…`).
  Names ignore case, accents, Hebrew niqqud and emoji; task names prefer open tasks. Ambiguous
  names fail with `candidates`; deletes require the exact name or the id.
- **Default list**: `--list` > `reminders.list` in `~/.config/gesher/config.json` > the
  Reminders default list. Results always name the list used.
- **Dates** are natural (`today`, `friday 18:00`, `in 2 hours`, `2026-11-05`). A date without a
  time is an all-day due date (output `2026-11-05`); timed values are ISO 8601 in your zone.
  Alarms given without a time fire at 09:00.
- **Recurrence**: `daily`, `weekly`, `monthly`, `yearly`, `weekdays`, `weekends`,
  `every 2 weeks`, `weekly on mon,thu`, `monthly on 1,15,last`, `none`; end with
  `--repeat-until DATE` or `--repeat-count N`.
- **Early alert** (the app's "Early Reminder"): `15m`, `1h`, `1d`, `1w`, `1mo` before the due date.
- **Priority**: `none|low|medium|high` (native 0 / 9 / 5 / 1; native 1–4 read as high, 6–9 low).
- **Batches** report every item (`results`, `succeeded`, `failed`); partial failure exits 1.
- **Backups**: changing or completing more than 5 tasks, deleting more than 5 tasks, and deleting a
  list with tasks first write a JSON snapshot to `~/.config/gesher/backups/`
  (`$GESHER_BACKUP_DIR` overrides). The path is returned as `backup`; `task restore <path|latest>`
  undoes the change.

## Native behavior worth knowing

- Lists are read per account (`fetchListsWithError:`) plus each group's `sublistContext`; groups
  are `REMList`s whose storage has `isGroup`. Moving a list into a group adds its change item to
  the group's sublist context; ungrouping adds it back to the account.
- Section membership and order come from the `REMRemindersListDataView_ListSectionsInvocation`
  Swift invocation. For a list inside a group the parent group's storage must be passed too
  (without it the daemon answers error -1). Membership writes send the complete map; because
  stored memberships merge by date, an omitted entry keeps its old section, so "no section" is
  written as membership of the list itself.
- Task order is the list's manual `reminderIDsOrdering` within each section; reordering uses
  `insertReminderChangeItem:before/afterReminderChangeItem:` on the list or the parent's subtask
  context.
- Subtasks: created in the parent's subtask context; indent adds the change item to the parent's
  subtask context, outdent adds it back to the list. Moving a parent to another list must re-attach
  each subtask (`fetchRemindersForMovingWithError:`) or the save fails with -3002.
- The URL field is a `REMURLAttachment` (as the app writes it); legacy `icsUrl` is read as a fallback.
- Early alerts are `REMDueDateDeltaAlert`s, stored separately: reminders are re-fetched with
  `REMReminderFetchOptions.fetchOptionsIncludingDueDateDeltaAlerts` to read them.
- Completing a recurring task keeps the series on the same id (advanced) and saves a completed copy.
- Custom smart lists store their filters as JSON in `filterData`; the daemon parses it by the list's
  `minimumSupportedVersion`, so writes always use the app's v2 format with version `20220430`
  (validated against the native `REMCustomSmartListFilterDescriptor`). Dates there are
  `dd-MM-yyyy`. Matching tasks come from `REMRemindersListDataView_CustomSmartListInvocation`,
  whose storages must include the smart list's account.
- Templates: `addTemplateWithName:configuration:toAccountChangeItem:` with a
  `REMTemplateConfiguration(sourceListID:shouldSaveCompleted:)`; ReminderKit copies the content.
  `addListUsingTemplate:toAccountChangeItem:` makes the list.
- Start dates are stored floating; ReminderKit stores a day-only start as midnight (read back as a day).
- Deleted tasks stay in Recently Deleted (`REMRemindersListDataView_RecentlyDeletedInvocation`;
  objects via `fetchReminderIncludingConcealedWithObjectID:`). `task purge` calls the Swift
  `REMStore.permanentlyHideReminders(with:accountID:completion:)` the app uses.
- ReminderKit stores attachment files under content hashes; exports are named `image-<id>.png`.

## Limitations

- Moving tasks between accounts, nested groups, sharing lists and assigning tasks are not supported
  (sharees and assignees are read). Smart list filters on a specific place (only any/none/car) and
  editing a template's content are not supported.
- Location alerts need coordinates (no geocoding here; use the Maps tool to find them).
- Private interfaces change between macOS releases; only the local release has been exercised.

## Tests

`swift test --filter RemindersCliTests` uses fixtures and isolated temporary directories only.
`scripts/test-native-fixtures.py --run-live` writes `QA-gesher-*` lists and deletes exactly them.
