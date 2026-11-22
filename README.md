# Gesher

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/banner-light.png">
    <img alt="Gesher: Your AI, meet your Mac." src="docs/assets/banner-light.png" width="100%">
  </picture>
</p>

<p align="center"><b>Let Claude, Codex or Cursor write to Apple Notes, Reminders, Calendar and Freeform: Notes tables and tags, Reminders sections and smart lists, and Freeform boards.</b></p>

<p align="center">One install for seven apps, with Contacts, Weather and Maps too. The apps can stay closed. A native Swift CLI and MCP server per app, 145 tools.</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&label=release"></a>
  <img alt="macOS · Apple silicon" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="Works with any MCP client" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<!-- Demo: a 20-30 s screen recording of one cross-app task goes here. -->

## Install

- **Claude Desktop, one app at a time:** download `gesher-<app>-1.3.1.mcpb` from the [latest release](https://github.com/EphraimElgrabli/gesher/releases/latest) and open it; Claude Desktop installs it as an extension. Each bundle holds one app, and macOS asks for its permission again after each update.
- **Let your agent do it:** paste this into Claude Code, Codex or Cursor:

  ```text
  Install Gesher on my Mac by following https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
  ```

- **Terminal, all seven apps:** installs every app, connects the AI apps you choose (Claude Code and Codex also get the Gesher plugins and skills), and keeps permissions across updates:

  ```sh
  curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
  ```

  Then, in a new Terminal window, run `gesher permissions` and click **Allow**. Notes and Freeform also need one drag into Full Disk Access, and Gesher opens that window for you. Restart your AI app. [Permissions](docs/permissions.md) · [Other AI apps](docs/clients.md)

> [!NOTE]
> **Requirements & trust**
> - Apple silicon Mac with macOS 26 or later; tested on macOS 27. Gesher uses private frameworks Apple doesn't document for third-party use, so a macOS update can break parts of it; `gesher doctor` shows what is affected. Experimental and maintained: [report breakage](https://github.com/EphraimElgrabli/gesher/issues/new/choose).
> - The installer needs no `sudo`. It installs into `~/.local` ([layout](https://github.com/EphraimElgrabli/gesher/blob/74f51d529b31a1b35c1e6f993f2c2ef235fad376/scripts/install.sh#L4-L7)), adds one PATH line to your shell profile ([code](https://github.com/EphraimElgrabli/gesher/blob/74f51d529b31a1b35c1e6f993f2c2ef235fad376/install.sh#L131-L147)), may create a code-signing certificate in your login keychain so permissions survive updates, which asks for your password ([code](https://github.com/EphraimElgrabli/gesher/blob/74f51d529b31a1b35c1e6f993f2c2ef235fad376/scripts/create-signing-identity.sh#L51)), and edits only the `gesher-*` entries of the AI apps you pick, backing each file up first ([code](https://github.com/EphraimElgrabli/gesher/blob/74f51d529b31a1b35c1e6f993f2c2ef235fad376/scripts/connect.sh#L311-L320)).
> - The download is checked against its published SHA-256 before anything is installed ([code](https://github.com/EphraimElgrabli/gesher/blob/74f51d529b31a1b35c1e6f993f2c2ef235fad376/install.sh#L121-L129)).
> - Gesher never writes Apple's databases directly: every change goes through the app's own frameworks and is read back to check it.

## Try it

- *"Plan my Friday: check the weather, find a free hour for a run, and put my errands in a 'Friday' section of my Errands list."*
- *"Turn my Lisbon trip note into a packing list in Reminders, due the day before the flight, and add a Passport row to the note's packing table."*
- *"Which of my Freeform boards mentions the venue? Add today's agenda to it as a text box."*
- *"Make a smart list of everything tagged #home that's due this week."*
- *"Will it rain before my 6 pm run? If so, find a café within a 5-minute walk of the office instead."*

With iCloud, the changes show up on your iPhone too.

## Why Gesher

I built Gesher for my own work. I wanted to stay in Apple's apps instead of adding more apps and subscriptions, and to finally have the assistant I wanted Siri to be. The technical challenge interested me too.

- **Features the public APIs don't have.** Gesher calls the frameworks Apple's apps are built on, including private frameworks Apple doesn't document for third-party use (a macOS update may break them). 90 of its 145 tools do something no public Apple framework offers, like Reminders sections and smart lists, Notes tags and tables, and editable Freeform diagrams and tables. [Tool-by-tool comparison](docs/public-apis.md) · [How it works](docs/architecture.md)
- **The apps can stay closed.** No AppleScript, no Shortcuts, no clicking through windows. Freeform opens quietly in the background only when importing media or files through its inbox.
- **It checks its work.** Every write is read back. Bulk deletes are backed up first, deleted reminders and notes go to Recently Deleted, and Notes edits can be tied to the version the agent read.

## What your agent can do

| | App | Your agent can… | Tools |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/reminders-dark.png"><img src="docs/assets/apps/reminders-light.png" width="32" alt=""></picture> | **Reminders** | add, complete and organize tasks: lists, sections, tags, subtasks, smart lists | [28](apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/calendar-dark.png"><img src="docs/assets/apps/calendar-light.png" width="32" alt=""></picture> | **Calendar** | read your agenda, find free time, create and move events, answer invitations | [17](apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/contacts-dark.png"><img src="docs/assets/apps/contacts-light.png" width="32" alt=""></picture> | **Contacts** | find people by name, phone or email, and update cards | [21](apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/notes-dark.png"><img src="docs/assets/apps/notes-light.png" width="32" alt=""></picture> | **Notes** | read and write notes as Markdown, with checklists, tables and tags | [31](apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/maps-dark.png"><img src="docs/assets/apps/maps-light.png" width="32" alt=""></picture> | **Maps** | search places, see opening hours, plan routes and travel times (read-only) | [6](apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/weather-dark.png"><img src="docs/assets/apps/weather-light.png" width="32" alt=""></picture> | **Weather** | check the forecast hour by hour, air quality and severe-weather alerts; minute-by-minute rain in some countries | [10](apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/apps/freeform-dark.png"><img src="docs/assets/apps/freeform-light.png" width="32" alt=""></picture> | **Freeform** | search, manage and export boards (PDF/PNG), scenes, editable tables, rich text, shapes, stickies, bound connectors, diagrams and board appearance | [32](apps/freeform/README.md) |

Every app is also a command-line tool, for example `calendar-cli agenda tomorrow`. Each app's README lists its commands.

## How it compares

Other good projects cover some of the same apps. Checked against each project's README and repository on 17 November 2026; corrections are welcome in an [issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose).

| | Reminders sections & smart lists | Notes tags & tables | Freeform | Weather / Maps | Apps can stay closed | Install | Maintained |
|---|:-:|:-:|:-:|:-:|:-:|---|:-:|
| **Gesher** | ✓ | ✓ | ✓ | ✓ / ✓ | ✓ | `.mcpb` per app, installer, or ask your agent | ✓ |
| [RemCTL](https://github.com/viticci/remctl) | ✓ | — | — | — / — | ✓ | notarized `.dmg`; then `.mcpb` or Claude Code plugin | ✓ |
| [iMCP](https://github.com/mattt/iMCP) | — | — (reads only) | — | ✓ / ✓ | ✓ | app download or Homebrew | ✓ |
| [apple-mcp](https://github.com/supermemoryai/apple-mcp) | — | — | — | — / ✓ | — | `.dxt`, `npx`, `bunx` | — (archived August 2025) |
| [mcp-server-apple-events](https://github.com/FradSer/mcp-server-apple-events) | — | — | — | — / — | ✓ | `npx` | ✓ |
| [apple-notes-mcp](https://github.com/sweetrb/apple-notes-mcp) | — | ✓ | — | — / — | — | `npx`, Claude Code plugin | ✓ |
| [mcp-ical](https://github.com/Omar-V2/mcp-ical) | — | — | — | — / — | ✓ | `git clone` + `uv` | — (last commit April 2025) |
| [Claude's Apple Notes connector](https://claude.com/connectors/read-and-write-apple-notes) | — | — | — | — / — | not stated | one click in Claude's directory | ✓ |

- **What they do that Gesher doesn't:** RemCTL is Reminders only and goes further there (rich links, Groceries lists, urgent reminders, a notarized installer, a Reminders workspace in Codex), also through Apple's private ReminderKit. iMCP covers Messages, Mail and current location as well, and reads notes (tables included) from the Notes database without writing them. apple-mcp also covers Messages and Mail, and its Maps tools can save favorites and guides (Gesher's Maps is read-only). mcp-server-apple-events covers Reminders and Calendar with priorities, tags and subtasks. apple-notes-mcp is Notes only and goes deeper there in places (exports, audio transcripts, a query language); it does tags, checklists and tables through Apple Shortcuts and AppleScript. mcp-ical covers Calendar. Claude's connector lists, reads, adds and updates notes.
- **Apps can stay closed:** AppleScript-based servers (apple-mcp, apple-notes-mcp) drive the app, so macOS opens it. RemCTL, iMCP (whose own menu-bar app runs), the EventKit-based servers (mcp-server-apple-events, mcp-ical) and Gesher don't need the app running; Gesher opens Freeform in the background only when importing files or links through its inbox.

## Good to know

- **Privacy:** Gesher itself runs on your Mac, with no Gesher servers, accounts or telemetry. Maps and Weather use Apple's services; whatever you share with an agent goes to its provider.
- **Stability:** the frameworks Gesher uses aren't a stable API, so a macOS update can break parts of it. Gesher then stops with a clear error, and `gesher doctor` shows what's affected. [Limitations](docs/limitations.md)
- **Trust:** each release is built from its tagged commit and published with a `.sha256` file, which the installer checks. [Security](SECURITY.md)
- **Questions:** [FAQ](docs/faq.md), including how Gesher differs from AppleScript-based MCP servers.
- **Other languages:** [עברית](docs/i18n/README.he.md) · [简体中文](docs/i18n/README.zh-CN.md) · [日本語](docs/i18n/README.ja.md) · [more](docs/i18n/)

---

I'm Ephraim Elgrabli. I built Gesher for my own work and share it under [GPL-3.0](LICENSE). Gesher (גשר) is Hebrew for *bridge*. Bug reports are welcome, especially after macOS updates ([open an issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose)); pull requests are welcome but reviewed slowly ([CONTRIBUTING](CONTRIBUTING.md)); questions go in [Discussions](https://github.com/EphraimElgrabli/gesher/discussions); security reports go through [private reporting](SECURITY.md). Not affiliated with Apple Inc. · [Legal notes](docs/legal.md)
