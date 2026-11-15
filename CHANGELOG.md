# Changelog

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
