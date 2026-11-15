# Install Gesher (instructions for AI agents)

You are an AI agent and your user asked you to set up Gesher: local MCP servers that let you work with
their Mac's Reminders, Calendar, Contacts, Notes, Maps, Weather and Freeform. Follow these steps
in order. Each command is safe to re-run. Keep the user informed in plain language; they don't need the
technical details unless they ask.

## 1. Check the Mac

```sh
sw_vers -productVersion; uname -m
```

Gesher needs Apple silicon (`arm64`). It is tested on macOS 27. On an Intel Mac, stop and tell the user
Gesher can't run there.

## 2. Install

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash -s -- --no-connect
```

No sudo. It verifies the download, installs to `~/.local`, adds `~/.local/bin` to the PATH in
`~/.zshrc`, and signs the tools with a certificate it creates on this Mac (macOS may show one keychain
prompt; tell the user to allow it; if they decline, the install still works, but macOS permissions have
to be granted again after each update). In the current shell, use the full path
`~/.local/bin/gesher` or run `export PATH="$HOME/.local/bin:$PATH"` first.

## 3. Connect the user's AI apps

```sh
gesher connect --list    # which AI apps are installed, and whether Gesher is connected to each
```

Ask the user which AI apps to connect (or all), and which Mac apps they want to give access to
(default: all seven). Some AI apps work best with fewer tools; for Cursor and Windsurf, suggest the
three or four Mac apps the user cares about most (`gesher connect` defaults them to Reminders,
Calendar and Notes). Then, for example:

```sh
gesher connect --all                                  # every AI app found on this Mac
gesher connect claude-desktop cursor                  # only these
gesher connect --all --apps reminders,calendar,notes  # only some Mac apps
```

Supported: Claude Desktop, Claude Code, Codex, Cursor, VS Code, Windsurf/Devin,
Gemini CLI, Antigravity, LM Studio, opencode, Zed, Kiro, Warp and Cline. For any other MCP client,
`gesher connect --print` prints the JSON to paste. Details: [clients.md](clients.md).

## 4. Grant access

```sh
gesher permissions
```

macOS shows one prompt each for Reminders, Calendar and Contacts. Tell the user to click **Allow** (for
Calendar: **Allow Full Access**). Notes, Freeform and Weather's saved places need Full Disk Access,
which has no prompt: `gesher permissions` also opens System Settings at Full Disk Access and shows the
tool in Finder; tell the user to drag it into the list and turn it on. Maps and Weather lookups
need nothing.

## 5. Verify

```sh
gesher doctor          # a table for the user
gesher doctor --json   # the same as a JSON array, one object per app
```

Every app should say `ok`. Then ask the user to restart the AI apps you connected, and suggest a first
request, such as *"What's on my calendar tomorrow?"* or *"Remind me to call Mom at 6."*

## 6. Confirm the tools are visible

After the restart, the AI app should list servers named `gesher-reminders`, `gesher-calendar` and so
on in its MCP or tools settings. If you are the agent inside one of those apps, you can check your own
tool list for names like `agenda` or `task_create`. `gesher connect --list` shows what is connected
where.

## If something fails

- `gesher doctor` names what is missing and how to fix it.
- Running in a sandbox that can't write outside the project, or without network access? Give the user
  the one-line install command to run in Terminal themselves, then continue from step 3.
- Every CLI explains itself: `<app>-cli --help`, `<app>-cli <command> --help`.
- Full guide: [docs/permissions.md](permissions.md). Uninstall: `gesher uninstall`.
