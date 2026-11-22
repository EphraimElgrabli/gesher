# Freeform

`freeform-cli` reads, authors and edits Apple Freeform boards: native text boxes, shapes, sticky
notes, bound connectors, structured diagrams, board lifecycle and media/file imports. Every command
is also an MCP tool in `freeform-cli mcp`.

```sh
freeform-cli doctor                                         # Freeform version, build UUID, FDA, authoring status
freeform-cli boards list [--include-deleted] [--favorites]
freeform-cli boards get 'Trip ideas'                        # details, revision, coordinate system, counts per type
freeform-cli boards create 'Architecture'
freeform-cli boards rename 'Architecture' --title 'System Architecture'
freeform-cli boards favorite 'System Architecture' [--off]
freeform-cli boards delete 'Draft'                          # moves to Recently Deleted
freeform-cli boards restore 'Draft'                         # restores from Recently Deleted
freeform-cli boards export 'System Architecture' --output ~/Desktop/arch.pdf --kind pdf
freeform-cli folders list [--include-deleted]
freeform-cli scenes list 'System Architecture'
freeform-cli scenes create 'System Architecture' --name 'Overview' --x 0 --y 0 --width 1200 --height 800
freeform-cli scenes update 'System Architecture' --scene <id> --name 'Backend'
freeform-cli scenes delete 'System Architecture' --scene <id>
freeform-cli items list 'System Architecture' [--type shape] [--limit 50] [--offset 0]
freeform-cli search 'gateway' [--type shape] [--include-deleted]
freeform-cli items add-text 'System Architecture' --text 'Overview' --x 100 --y 60 --width 260
freeform-cli items add-shape 'System Architecture' --shape rounded_rectangle --text 'API' --x 100 --y 180 --fill '#3B82F6'
freeform-cli items add-sticky 'System Architecture' --text 'Note' --x 420 --y 180 --fill yellow
freeform-cli items add-table 'System Architecture' --rows 3 --columns 4 --x 100 --y 360 [--rtl]
freeform-cli items connect 'System Architecture' --from <id1> --to <id2> --style orthogonal
freeform-cli items update 'System Architecture' --item <id1> --x 140 --y 200 --fill green --text 'API Gateway' --shape star --description 'Core API'
freeform-cli items delete 'System Architecture' --item <id1>
freeform-cli items duplicate 'System Architecture' --item <id1> --dx 260 --dy 0
freeform-cli items group 'System Architecture' --item <id1> --item <id2>
freeform-cli items ungroup 'System Architecture' --group <groupId>
freeform-cli items align 'System Architecture' --item <id1> --item <id2> --mode top
freeform-cli diagram create 'System Architecture' --spec '{"direction":"left-right","nodes":[...],"edges":[...]}'
freeform-cli items add 'Trip ideas' --url https://www.apple.com --file ~/Pictures/map.png
```

- **How it reads.** Each call copies `boards.db` (+ `-wal`, `-shm`) into a new temporary
  directory, reads the copy with SQLite and deletes it. The live store is never opened for reads.
  Blobs are Coherence CRDT documents decoded by Coherence's exported `CRDT.init(serializedData:)`
  into Freeform's own Swift model types and read with Swift reflection.
- **How native authoring works.** `items add-text`, `add-shape`, `add-sticky`, `connect`,
  `update`, `delete`, `duplicate`, `group`, `ungroup`, `align`, `diagram create` and board
  lifecycle commands (`boards rename`, `favorite`, `delete`, `restore`, and empty `boards create`)
  run through Freeform's own in-process store and command engine (`CRLBoardDataStore`, `CRLBoard`,
  `CRLBoardItemFactory`, `CRLCommandController`, `CRLCommand*`) and save through
  `CRLBoard -asyncSavePendingChangesWithCompletionHandler:`. No raw SQLite writes are made.
  - **Strict ABI gating:** the small set of unexported Swift bootstrap entry points is gated on the
    exact Mach-O `LC_UUID` of the verified Freeform build plus ObjC class, selector and ivar checks.
    An unrecognized Freeform build fails cleanly with `unsupported_private_api` while reads and the
    import inbox continue to work.
  - **Concurrency & safety:** native writes refuse to run while Freeform.app is open (`app_running`),
    refuse participant-shared boards (`read_only`), refuse locked items unless explicitly unlocking
    (`item_locked`), support optimistic concurrency via `--if-revision`, and verify every mutation
    by reading back from a fresh store snapshot. Changes sync to iCloud the next time Freeform opens
    (`sync: "pending_until_app_launch"`).
- **How media/file imports work.** `items add` (and `boards create` with `--file`, `--url`,
  `--folder`, or while Freeform is running) uses Freeform's import inbox (`Import/<UUID>/Manifest.plist`).
  Hidden files, `~/Library` (iCloud Drive excepted), system files and key/credential files are refused;
  files for a board you share need `--confirm-shared`.
- **Out of scope / blocked:** participant writes to boards shared with you, collaboration invites
  and live collaborator presence, table cell text editing, freehand drawing authoring,
  folder write operations, and live iCloud push while Freeform is closed.
