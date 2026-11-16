# FAQ

**Is my data sent anywhere?**
Not by Gesher. It runs on your Mac and has no servers. Weather and Maps ask Apple's services, exactly as those apps do. What you share with an AI agent goes to that agent's provider, as with anything you type into it; with a local model in LM Studio or opencode, your conversation never leaves your Mac.

**Is it safe to let an agent change my things?**
Gesher is careful: every write is read back to check it took effect, bulk deletes are backed up to `~/.config/gesher/backups`, and deleted reminders and notes go to Recently Deleted. But it does what your agent asks. Connect only the apps you need, and review what you let an agent change.

**What do I need?**
A Mac with Apple silicon and macOS 26 or later. Gesher is tested on macOS 27; macOS 26 should work but hasn't been tested yet. Intel Macs aren't supported. No Xcode needed.

**How is this different from AppleScript-based MCP servers?**
AppleScript sees only what each app chose to script, needs the app open, and asks for Automation access. Gesher calls the frameworks the apps are built on: it works with the apps closed and reaches what scripting can't, such as Reminders sections and smart lists, Notes tags and tables, and Freeform boards.

**Why use private frameworks at all?**
Gesher calls the frameworks Apple's apps are built on, including private frameworks Apple doesn't document for third-party use; a macOS update may break them. It uses them because much of what Gesher does has no public API: 64 of its 119 tools do something no public Apple framework offers, including every Notes and Freeform tool. The [tool-by-tool comparison](public-apis.md) lists each tool, its public alternative if there is one, and Apple's documentation.

**What can't it do?**
Contact notes, and some Freeform edits (shapes, sticky notes, renaming boards). Maps is read-only. [Full list](limitations.md).

**Why does the installer ask for my password?**
Only to create a signing certificate on your Mac, so updates keep the permissions you granted. Say no and Gesher still works; you'll just grant access again after updates.

**Can I trust the download?**
Every release is built from its tagged commit in this repository and published with a `.sha256` file; the installer checks the download against it, and you can too with `shasum -a 256 -c gesher-*.tar.gz.sha256`. The tools aren't notarized by Apple; the installer signs them on your Mac instead. The [security notes](../SECURITY.md) explain what Gesher's permissions protect against.

**Will a macOS update break it?**
It might: Gesher uses parts of macOS that Apple doesn't promise to keep stable. If something changes, Gesher stops with a clear message instead of guessing, and `gesher doctor` shows what's affected.

**How do I update or remove it?**
`gesher update` installs the latest version and keeps your permissions and connections. `gesher uninstall` removes Gesher and disconnects it from your AI apps.

**What does "Gesher" mean?**
It's Hebrew for *bridge* (גשר), and it's pronounced *GEH-sher*.
