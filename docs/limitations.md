# Limitations

Gesher reaches what macOS lets a regular, non-Apple program reach. Some things are reserved for Apple's
own apps, and no permission you grant can change that.

| App | Not available |
|---|---|
| Contacts | Contact notes. Duplicates can be linked, not merged. |
| Freeform | Renaming, deleting or favoriting boards; adding shapes, sticky notes or connectors. Those live inside the app with no stable interface. Reading and searching everything, creating boards and adding text, links, images and files work. |
| Maps | Changes of any kind: Maps is read-only (search, places, routes and travel times). Your saved places, guides and recents are not read either: they live in Maps' private sync store with no stable interface. |
| Weather | Next-hour precipitation only where Apple offers it (e.g. US, UK; not IL), air quality not in every country. Alerts come from national services: an empty list means none was reported. |

## Platform

| Platform | Status |
|---|---|
| macOS 27, Apple silicon | ✅ Tested |
| macOS 26, Apple silicon | ⚠️ Should work (the code targets it); not tested yet |
| Intel Macs | ❌ Not supported (Gesher uses arm64-specific code) |
| Linux, Windows | ❌ The apps exist only on Apple platforms |

## macOS updates

Gesher uses private frameworks Apple doesn't document for third-party use, which Apple can change in
any update. When something it relies on changes, Gesher stops with a clear error instead of guessing,
and `gesher doctor` shows which apps are affected.

## Building from source

Swift 6 (Xcode 26 or later): `git clone`, then `scripts/install.sh`. See [AGENTS.md](../AGENTS.md).
