# Connecting AI apps

`gesher connect` finds the AI apps on your Mac and connects them for you:

```sh
gesher connect            # asks which of the AI apps it found to connect
gesher connect --list     # what's installed, and what's connected
gesher connect cursor     # just one (names below)
gesher connect --all --apps reminders,calendar   # every AI app, only some Mac apps
gesher connect --remove   # disconnect everything
```

It adds one MCP server per Mac app, named `gesher-<app>` (`gesher-reminders`, `gesher-calendar`, …),
and never touches other servers. Every settings file it changes is backed up first to
`~/.config/gesher/backups/connect/`. Restart the AI app afterwards.

The rest of this page is for doing it by hand. In every example, replace `/Users/you` with your home
folder (`gesher connect --print` prints the snippet with your real paths), and repeat the entry for each
Mac app you want: `reminders`, `calendar`, `contacts`, `notes`, `maps`, `weather`,
`freeform`.

> [!NOTE]
> All seven Mac apps together add 131 tools: 119, plus a `doctor` tool in every server and a
> `permissions` tool in the five that need a macOS permission. Some AI apps work best with fewer, so `gesher connect` gives Cursor and Windsurf only
> Reminders, Calendar and Notes unless you choose: `gesher connect cursor --apps reminders,maps,weather`.

## Apps that use an `mcpServers` file

| AI app | `gesher connect` name | Settings file |
|---|---|---|
| Claude Desktop | `claude-desktop` | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Cursor | `cursor` | `~/.cursor/mcp.json` |
| Windsurf / Devin Desktop | `windsurf` | `~/.config/devin/mcp_config.json` (Devin) or `~/.codeium/windsurf/mcp_config.json` (Windsurf) |
| Gemini CLI | `gemini` | `~/.gemini/settings.json` |
| Antigravity | `antigravity` | `~/.gemini/config/mcp_config.json` |
| LM Studio | `lmstudio` | `~/.lmstudio/mcp.json` |
| Kiro | `kiro` | `~/.kiro/settings/mcp.json` |
| Warp | `warp` | `~/.warp/.mcp.json` |
| Cline (CLI) | `cline` | `~/.cline/data/settings/cline_mcp_settings.json` |

```json
{
  "mcpServers": {
    "gesher-reminders": { "command": "/Users/you/.local/bin/reminders-cli", "args": ["mcp"] }
  }
}
```

JetBrains AI Assistant takes the same JSON in **Settings → Tools → AI Assistant → Model Context
Protocol**. Most other MCP apps accept it too.

## Claude Code

`gesher connect claude-code` installs Gesher's Claude Code plugins, which add a skill for each app on top
of its MCP server. (The plugins expect the default install folder, `~/.local/bin`; with a custom
`--prefix`, `gesher connect` registers plain MCP servers with your paths instead.) By hand:

```sh
claude plugin marketplace add EphraimElgrabli/gesher
claude plugin install gesher-reminders@gesher
```

Or just the MCP server:

```sh
claude mcp add --scope user --transport stdio gesher-reminders -- /Users/you/.local/bin/reminders-cli mcp
```

## Codex

The Codex app and the Codex CLI share one configuration (so does the ChatGPT desktop app where it is
built on Codex, which `gesher connect` checks).
`gesher connect codex` installs Gesher's Codex plugins (MCP server plus a skill for each app); enable
them under **Plugins** after restarting. By hand, either:

```sh
codex mcp add gesher-reminders -- /Users/you/.local/bin/reminders-cli mcp
```

or in `~/.codex/config.toml`:

```toml
[mcp_servers.gesher-reminders]
command = "/Users/you/.local/bin/reminders-cli"
args = ["mcp"]
```

## VS Code (GitHub Copilot)

`gesher connect vscode` (or `vscode-insiders`) writes your user `mcp.json`
(`~/Library/Application Support/Code/User/mcp.json`). By hand:

```sh
code --add-mcp '{"name":"gesher-reminders","type":"stdio","command":"/Users/you/.local/bin/reminders-cli","args":["mcp"]}'
```

## opencode

`~/.config/opencode/opencode.json`:

```json
{
  "mcp": {
    "gesher-reminders": { "type": "local", "command": ["/Users/you/.local/bin/reminders-cli", "mcp"], "enabled": true }
  }
}
```

## Zed

`~/.config/zed/settings.json` (comments in the file are kept when `gesher connect zed` adds the
servers):

```json
{
  "context_servers": {
    "gesher-reminders": { "command": "/Users/you/.local/bin/reminders-cli", "args": ["mcp"] }
  }
}
```

## MCP Registry and MCP Bundles

Each Mac app is also listed in the [MCP Registry](https://registry.modelcontextprotocol.io) as
`io.github.EphraimElgrabli/gesher-<app>`, packaged as an MCP Bundle (`gesher-<app>-<version>.mcpb`
on the [release page](https://github.com/EphraimElgrabli/gesher/releases/latest)). AI apps that
install bundles, such as Claude Desktop, run the server from the bundle. A bundle holds one app's
CLI only: macOS asks for that app's permission again after each update, and there is no `gesher`
command. For every Mac app, kept permissions and updates, use the installer instead.
Maintainers: `scripts/package-mcpb.py dist/gesher-<version>-macos-arm64.tar.gz` builds the bundles
from a release archive and rewrites `registry/<app>.json` with their SHA-256.

## Anything else

Each `<app>-cli mcp` is a standard MCP server over stdio. Give your app the absolute path: AI apps
launched from the Dock don't see your shell's `PATH`.

## Troubleshooting

- **The tools don't show up.** Quit the AI app completely and open it again; most apps read their MCP
  settings only at launch. `gesher connect --list` shows what is connected.
- **"Command not found" or a server that fails to start.** AI apps need the full path to each tool, not
  `reminders-cli` alone. `gesher connect --print` prints the right paths.
- **A permission error.** Run `gesher doctor` in Terminal; it names what is missing.
- **See what a server does.** Run it by hand: `reminders-cli mcp` waits for MCP messages on stdin.
  Most AI apps also show a log for each server in their MCP settings.

## Permissions inside AI apps

macOS asks for access the first time each Mac app is used, whichever AI app started it, and remembers
your answer for Gesher's tool rather than for the AI app. Run `gesher permissions` once in Terminal to
answer all the prompts up front. See [permissions.md](permissions.md).
