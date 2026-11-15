# Permissions

macOS asks before any program reads your reminders, calendars or contacts. Gesher uses the standard
prompts: nothing is granted behind your back, and you can revoke access any time in
**System Settings → Privacy & Security**.

## What each app needs

| App | Permission | How to grant it |
|---|---|---|
| Reminders | Reminders | `gesher permissions`, then allow the prompt |
| Calendar | Calendars, **Full Access** | `gesher permissions`, then choose *Allow Full Access* |
| Contacts | Contacts | `gesher permissions`, then allow the prompt |
| Notes, Freeform | Full Disk Access | See below |
| Weather | Full Disk Access, only for your saved places | See below |
| Maps | Nothing | — |

`gesher doctor` shows the state of every app at any time.

## Full Disk Access

Notes, Freeform and Weather's saved places are read from the apps' own data stores, which macOS
protects with Full Disk Access. That permission has no prompt; you add the program yourself:

1. Run `gesher permissions` (or `notes-cli permissions --request`). It opens
   **System Settings → Privacy & Security → Full Disk Access** and shows the tool in Finder.
2. Drag it from Finder into the list and turn it on. (Or click **+**, press **Cmd-Shift-G** and paste the
   path, which is already on your clipboard.)
3. Optional: for Weather's saved places (the cities you added in the Weather app), add
   `~/.local/lib/gesher/active/weather-cli` the same way. Forecasts for any place work without it.

If your terminal or agent app already has Full Disk Access, Gesher uses that and needs nothing more.

## Updates keep your permissions

macOS remembers a permission for a program's exact location and signature. The installer always runs
the tools from the same folder (`~/.local/lib/gesher/active/`) and signs them with a certificate
created on your Mac ("Gesher Local Signing"), so updates and rollbacks keep every permission you
granted. The certificate is used only on your Mac and is not trusted by anyone else. (If the installer
couldn't create it, it says so and signs ad-hoc; permissions then have to be granted again after an
update.)

## Who else can use these permissions

macOS grants access to Gesher's tools, not to the AI app that runs them, and any program you run can
start those tools. Treat Gesher's permissions like your Terminal's: they protect your data from apps
that don't run code as you, not from software that already does. See [SECURITY.md](../SECURITY.md).

How it all works under the hood: [architecture.md](architecture.md#permissions).
