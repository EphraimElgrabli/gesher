# Freeform

`freeform-cli` reads Freeform boards and their content, creates boards and adds text, links,
images and files. Every command is also an MCP tool in `freeform-cli mcp`.

```sh
freeform-cli doctor                              # Freeform version, Full Disk Access, store, model types
freeform-cli boards list [--include-deleted] [--favorites]
freeform-cli boards get 'Trip ideas'             # details + item count per type
freeform-cli items list 'Trip ideas' [--type sticky]
freeform-cli search 'packing list' [--type sticky] [--include-deleted]   # across all boards
freeform-cli boards create 'Trip ideas' --text 'Flights' --url https://www.apple.com
freeform-cli items add 'Trip ideas' --text 'Book flights' --file ~/Pictures/map.png
```

- **How it reads.** Each call copies `boards.db` (+ `-wal`, `-shm`) into a new temporary
  directory, reads the copy with SQLite and deletes it. The live store is never opened. Blobs are
  Coherence CRDT documents; they are decoded by Coherence's exported `CRDT.init(serializedData:)`
  into Freeform's own Swift model types (`CRLBoardCRDTData`, `CRLWPShapeItemCRDTData`, ...,
  loaded from the app executable) and read with Swift reflection. Nothing is called by address.
- **Items** carry `type` (text, shape, sticky, connector, image, file, link, table, drawing, movie,
  group), `x`/`y`/`width`/`height` (points), `angle`, `text`, `fill`/`stroke` (`#RRGGBB[AA]`),
  `url`, `file` (name), connector `from`/`to`, `z` (stacking order in its parent, 0 = back) and
  `group` for items inside a group.
- **How it writes.** `boards create` and `items add` use Freeform's own import inbox (the one its
  Share extension uses): a directory with `Manifest.plist` and the files under
  `Import/` in the group container. Freeform imports it immediately when running (otherwise
  `freeform-cli` opens it in the background), creates the items with its own commands, saves and
  syncs them with iCloud, and deletes the directory. The command then reads the store back and
  returns the new board or items. Freeform chooses positions; images keep the name `image.<ext>`.
  Hidden files and folders, `~/Library` (iCloud Drive excepted), system files and key or
  credential files are refused; files for a board you share need `--confirm-shared`.
- **Not available:** renaming, favoriting, deleting or restoring boards; editing, moving or
  deleting items; adding shapes, sticky notes or connectors. Freeform's only writer is Swift-only
  code in the app with no exported or Objective-C entry point, its App Intents need an
  Apple-only entitlement, and raw database writes are out of scope (see RESEARCH.md).
