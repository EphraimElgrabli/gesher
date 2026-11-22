# Changelog

## 1.3.1 — 2026-11-22

- Cross-generational macOS compatibility: adds `OSGeneration`, `ABIResolutionMode`, ordered
  multi-generation class/selector/symbol fallback helpers (`DynamicRuntime.resolveFirst*`) used
  across Weather, Reminders and Freeform, plus `MachOAnchorScanner` for unique-match arm64
  structural anchor verification and `osGeneration` reporting in `doctor`.
- Freeform: adds populated table creation (`items_add_table --cells`), read-only table inspection
  (`items_table_get`), in-place single-cell editing (`items_table_set_cell`), rich text styling
  (`--font-size`, `--bold`, `--italic`, `--underline`, `--strikethrough`, `--text-color`,
  `--align` with automatic Hebrew/Arabic RTL direction) on text boxes and sticky notes, persistent
  board appearance controls (`boards_appearance --dot-grid --connector-mode`), quiet background
  iCloud sync (`boards_sync`), hidden background launch, and automatic graceful closing of idle
  background Freeform processes that have no visible windows. Freeform: 32 tools, 145 in all.

## 1.3.0 — 2026-11-22

- Updater: GitHub Releases-based update checker with 6-hour local TTL cache and non-blocking
  background refresh. Adds `gesher update --check [--json]`, `gesher update --auto ask|always|never`,
  `gesher update --skip <version|clear>`, interactive prompts on `gesher` runs, and `updateAvailable`
  reporting in `doctor`.
- Freeform: adds native PDF and PNG board export (`boards_export`, read-only via `CRLCanvasImager`),
  full scenes CRUD (`scenes_list`, `scenes_create`, `scenes_update`, `scenes_delete`), native
  table creation (`items_add_table` with `--rtl` and accurate table readback), `folders_list`,
  shape replacement (`items_update --shape`) and item alt text (`items_update --description`).
  Freeform: 28 tools, 141 in all.

## 1.2.0 — 2026-11-22

- Freeform: native in-process board authoring and lifecycle through Freeform's own store and
  command engine (`CRLBoardDataStore`, `CRLBoard`, `CRLBoardItemFactory`, `CRLCommandController`),
  strictly gated on verified Freeform Mach-O build UUIDs. Adds 15 tools: `items_add_text`,
  `items_add_shape`, `items_add_sticky`, `items_connect`, `items_update`, `items_delete`,
  `items_duplicate`, `items_group`, `items_ungroup`, `items_align`, `diagram_create`,
  `boards_rename`, `boards_favorite`, `boards_delete` and `boards_restore`, plus paginated
  `items_list`, optimistic concurrency (`ifRevision`) and `doctor` authoring/capability reporting.
  Freeform: 21 tools, 134 in all.

## 1.1.0 — 2026-11-17

- Notes: `table_add_row` and `table_add_column` add a row or column to an existing table, at the
  end or at a position, with optional cell text. Like `table_set_cell`, they need the note's
  revision and read the note back to check that only the table changed. Notes: 31 tools, 119 in all.
- Each app is also published as an MCP Bundle (`.mcpb`) on the release page and in the
  [MCP Registry](https://registry.modelcontextprotocol.io) as `io.github.EphraimElgrabli/gesher-<app>`.
- Bug reports and pull requests are welcome; issue templates for bugs and feature requests.

## 1.0.0 — 2026-11-15

First public release.

- Command-line tools and MCP servers for Reminders, Calendar, Contacts, Notes, Maps, Weather
  and Freeform: 117 tools, built directly on the frameworks behind each app.
- One declaration per action drives the CLI command, its help, the MCP tool and its JSON Schema.
- Agent-first conventions: names instead of ids, natural dates, compact JSON, batch operations,
  structured errors with hints and candidates.
- Safe writes: read-back verification, backups before bulk changes, revision checks for Notes.
- Guards against prompt injection: every server tells agents that app content is data, not
  instructions; invitations go out only through the destructive `event_invite`; hidden, system
  and key files are never attached or exported to; files for shared notes, lists and boards need
  `confirmShared`; backups are readable only by the user.
- One-line installer with locally signed binaries, so macOS permissions survive updates.
- `gesher connect`: finds the AI apps on your Mac (Claude Desktop, Claude Code, Codex,
  Cursor, VS Code, Windsurf/Devin, Gemini CLI, Antigravity, LM Studio, opencode, Zed, Kiro, Warp, Cline)
  and connects them, with a backup of every settings file it changes.
- Plugins with skills for Claude Code and Codex.
- `llms.txt` and an install guide written for AI agents (`docs/install.md`).
