# Freeform private-backend research

## Update 2026-11-03: content reads and writes

Host: macOS 27.0 (26A428), Freeform 5.0 (656.1.2), iCloud sync on (`CloudKit syncing is
enabled` in Freeform's log; boards carry `sync_data`/`zone_sync_data`; CloudKit zones
`Board_<id>`). The store is in the group container (`Boards/boards.db`, schema version 17,
plus `side.db` with board load/open marks). `freeform-cli` now reads boards and item content and
writes through Freeform's import inbox. Live writes were made only on a board titled
`QA-gesher-freeform`, after a full backup of `Boards/`; a raw hash of every other board's
content columns and their decoded reads were identical before and after.

### No Core Data

Freeform has no managed object model: no `.mom`/`.momd` in the bundle or its frameworks, the
executable does not link CoreData (`otool -L`) and contains no `NSPersistent*` string. Its
persistence is its own SQLite layer (`SQLiteDatabase`, `CRLBoardDataStore`) storing Coherence
CRDT documents in blobs. `NSPersistentContainer` and persistent history do not apply.

### Reads: Coherence + Freeform's own model types (works)

- Every blob is `"crdt"` + version 6 + a Coherence document. Coherence exports
  `(extension in Coherence):CRDT.init(serializedData: Data) throws -> Self`
  (`$s9Coherence4CRDTPAAE14serializedDatax10Foundation0D0V_tKcfC`) and the protocol descriptor
  `$s9Coherence4CRDTMp`. Freeform's model types live in the app executable; `dlopen` of it
  (after its bundled `TS*` frameworks, by path) makes them visible to the Swift runtime, so
  `_typeByName("8Freeform16CRLBoardCRDTDataV")` returns the metadata and
  `swift_conformsToProtocol` the `CRDT` witness table. The generic initializer is called through
  a small arm64 shim (`ObjCCallSwiftThrowingGenericInit`: Data in x0/x1, consumed; Self metadata
  x2 and x20; witness table x3; indirect result x8; error x21). The decoded value is Freeform's
  real struct, read with `Mirror`. No function is called by address or offset.
- Types per column (field names from Swift reflection metadata):
  `boards.data` = `CRLBoardCRDTData` (`_title`, `rootContainerAffinity._rootContainerUUID`,
  `boardMetadata._creationTime/_lastActivityTime`), `boards_metadata.crdt_data` =
  `CRLUserBoardMetadataCRDTData` (`_isFavorite`, grid, connector mode), `folders.data` =
  `CRLFolderCRDTData`. Items: `common_data` =
  `CRLBoardItemCommonAbstractCRDTData<CRLBoardItemParentAffinity>` (or
  `<CRLShapeItemParentAffinity>` for shapes, stickies, connectors, strokes: adds the path), with
  `geometry.position/size/angle`, `_locked`, `_shadow`. `specific_data` by `item_type`.
- `item_type` = position in `CRLBoardItemType` + 2: 2 group/container, 3 shape (text boxes are
  shapes with no fill and no stroke; type `CRLWPShapeItemCRDTData`), 4 connector
  (`CRLConnectionLineCRDTData`: `_connectedFrom/_connectedTo`), 5 image, 6 movie, 7 file,
  8 link (`CRLURLItemCRDTData._atomicData.url`), 9 USDZ, 10 freehand drawing, 11 drawing
  stroke, 12 sticky (`CRLWPStickyNoteItemCRDTData`), 13 table, 14 surface. Confirmed by CloudKit
  record names `BoardItem_5`/`BoardItem_7` for imported images/files and by decoding every item
  of the 24 boards on this Mac. Connectors, tables and sticky notes were not present live (one
  tombstoned sticky), so their field paths are verified from reflection only.
- Text is `CRAttributedString` → `stringRef.topotext` (`CRTTMergeableString`, ObjC) →
  `-attributedString`. Stacking order is the order of the parent container's
  `CROrderedSet<UUID>` (`CRLContainerItemCRDTData.items`). Colors are `TSUColorData`
  (`rgbData`/`monochromeData`/`cmykData`, `alpha`).

### Writes: Freeform's import inbox (works for create board + add text, links, images, files)

- The Share extension hands content to the app through
  `<group container>/Import/<UUID>/Manifest.plist` (`CRLSEImportManifest`: `boardUUID?`,
  `folderUUID?`, `ownerName?`, `title`, `items`; each `CRLSEManifestItem` has `itemUUID`,
  `title?`, `attributedText?`, `url?`, `mediaUTI?`; field names via reflection of the extension
  and app types). Media files are referenced by a file URL in `url` (any path inside the
  directory) with `mediaUTI`; text uses `attributedText`, links `url`.
- `CRLSEImporter` (the app's `NSFilePresenter` for `Import/`) imports at launch and, while
  running, as soon as a write is coordinated on the `Import` directory itself (not a subitem).
  It logs `Creating new board: <id>` and runs `CRLCommandInsertBoardItems`; the new rows were
  saved with `unsynced_changes = 0`, and the sync engine fetched the zone back from CloudKit
  with server change tags (`BoardItem_5 ... recordChangeTag`), i.e. the content was uploaded.
  Not checked on icloud.com or a second device.
- Freeform chooses positions; image files are renamed `image.<ext>`; a board that is shared
  read-only is skipped and its import deleted.

### Not possible within the rules (evidence)

Rename, favorite, delete/restore boards; update, move or delete items; add shapes, sticky
notes or connectors:

- The import inbox has no such operations (manifest fields above; importer logs only text and
  URL item counts).
- The only writer is the app's Swift code. The executable exports one symbol
  (`__mh_execute_header`). The ObjC surface has no route to a store-bound `CRLBoard`:
  `CRLBoardLibrary` and `CRLBoardLibraryHeadlessController` expose only `init`;
  `CRLBoardLibraryCommandRenameBoard`/`DeleteItems`/`UndeleteItems` expose only `init` and
  getters; `CRLBoardDataStoreProvider` is a pure Swift class; `CRLCommandController` needs an
  existing `CRLBoard`. Calling Swift-only methods needs vtable offsets or witness-table slots
  (calls by address), which are out of scope.
- App Intents (`CRLRenameBoardIntent`, `CRLDeleteBoardIntent`, `CRLFavoriteBoardIntent_v2`,
  `CRLUtilitiesIntent`) need `com.apple.private.appintents.connection`-class entitlements
  (`LNConnectionErrorCodeMissingConnectionEntitlement`, 2700); spoofing is out of scope.
- Coherence can serialize modified values, but storing them means writing Freeform's SQLite
  tables directly, which is out of scope.
- Consequently the QA board could not be deleted by this tool; it has to be deleted in Freeform
  (and removed from Recently Deleted).

## Original research notes (2026-11-03, before the update)

Research status: no live write was made: no
board was created, modified or deleted. The only live calls were a read-only App
Intents entity query (it was refused) and a group-container directory listing (also
refused). Personal board names and content are not recorded here.

Host: macOS 27.0 (26A428), Apple silicon. Freeform 5.0 (CFBundleVersion 656.1.2,
`DTSDKName macosx27.0.internal`).

## TL;DR

| Path | Read | Write | Status on this host |
|---|---|---|---|
| A. App Intents via `LinkServices` `LNConnection` | board entities only (title, dates, favorite, grid, connectors) | create, rename and delete boards, favorite, add text, sticky notes, shapes, links, files and photos | **Blocked.** Error `LNConnectionErrorCodeMissingConnectionEntitlement` (2700). |
| B. In-process Freeform model (`dlopen` of the app executable + ObjC/Swift runtime) | everything | everything, including folders, connectors, delete and restore | **Technically loadable** (verified). Store access needs Full Disk Access, which this host lacks. The key entry points are Swift-only with no exported symbols, so the path is fragile. |
| C. Read-only SQLite snapshot + Coherence CRDT decoding | board list, flags, folders and tombstones; partial content | none (raw writes are out of scope) | Store location and schema confirmed. Content decoding would need reimplementing Freeform's Swift CRDT types. |
| D. `/usr/bin/shortcuts run` bridge | n/a | the same subset as A | Outside the house rules (it is not a private-framework call). Recorded only for completeness. |

**Recommendation:** do not promise Freeform parity. Ship `freeform-cli` first as
discovery and doctor only (no store calls). Then run a time-boxed spike of path B in
read-only mode, gated on Full Disk Access. Make no write commands until that spike
shows a stable way to obtain a `CRLBoard` bound to the live store. Details are in the
[plan](#recommended-implementation-plan).

## 1. Bundle and linkage

```sh
ls /System/Applications/Freeform.app/Contents/{Frameworks,PlugIns,Extensions}
# Frameworks: AppContentHub AppImageGenerationModel AppImageGenerationUI AppsGen AppsGenUI
#             TSAccessibility TSContentLanguage TSFeatureFlags TSFundamentals TSGeometry TSUtility
# PlugIns:    FreeformSharingExtension.appex   (com.apple.share-services, UI view controller)
# Extensions: USDRendererExtension.appex
otool -hv .../MacOS/Freeform        # MH_EXECUTE, PIE, arm64e (+ arm64e.x1), 55 MB
otool -L  .../MacOS/Freeform | grep -E 'Coherence|CloudKit|AppIntents'
# /System/Library/PrivateFrameworks/Coherence.framework/...
# /System/Library/PrivateFrameworks/_Coherence_CloudKit_Private.framework/...
# /System/Library/Frameworks/CloudKit.framework/...   AppIntents.framework  _AppIntents_AppKit
```

- The whole model layer lives **inside the app executable**: prefix `CRL`, Swift module
  `Freeform`. Build paths in `strings` show
  `Source/Persistence/{CRLBoardDataStore,CRLBoardLibrary,CRLBoardLibraryHeadlessController,SQL,CRLStore,...}.swift`.
  There is no separate Freeform model framework.
- `nm -gU`/`dyld_info -exports` on the executable shows **one export
  (`__mh_execute_header`)**. No Swift symbols are callable by name.
- `Coherence.framework` is Apple's Swift CRDT library (6,228 exports: `CRDT`,
  `CRContext`, `CRAttributedString`, `CRDTDictionary`, `CRArray`, `CRSQLStore`,
  `CRDataStoreBundle`, `Proto4_*`, …). `_Coherence_CloudKit_Private` (29 exports) bridges
  CRDTs to `CKMergeableDelta` (`CRCKMergeable`).
- `SwiftCRLite.framework` is **unrelated**: it handles certificate-revocation CRLite
  (`ValidDownloader`, `SecCRLite`), and Freeform does not link it.
- `TSContentLanguage.framework` (in the bundle, 18,462 exports) defines Codable
  `TSCLModels.CanvasObject`, `CharacterStyle`, `Chart`, …, and the app has
  `CRLCLExport.*Exporter` classes. This is a structured, versioned representation of
  canvas content, and a natural serialization target for agent-facing JSON if a
  `CRLBoard` can be obtained.

### App entitlements (relevant subset)

`codesign -d --entitlements - /System/Applications/Freeform.app`:

- `com.apple.security.app-sandbox`, `com.apple.security.application-groups` =
  `group.com.apple.freeform`, `group.com.apple.creatorstudio`;
  `com.apple.security.restricted-application-groups` = `group.com.apple.freeform`
- CloudKit: `com.apple.developer.icloud-container-identifiers` =
  `iCloud.com.apple.freeform` (+2), `com.apple.private.cloudkit.spi`,
  `.realTimeOperations`, `.setEnvironment`, `com.apple.private.CloudSharing.SPI`
- App Intents: `com.apple.linkd.registry`
- `platform-application`, `com.apple.private.tcc.allow` (AddressBook, Photos, Liverpool)

An ad-hoc or Developer ID signed CLI cannot carry any `com.apple.private.*` entitlement
or `platform-application` (AMFI). Spoofing them is out of scope.

## 2. Storage

### Location

- Live store: `~/Library/Group Containers/group.com.apple.freeform/…/Boards/boards.db`.
  The evidence is these strings in the binary: `containerURLForSecurityApplicationGroupIdentifier:`,
  `Using production path Boards`, `Using sandbox path Development/Boards`,
  `PendingBoards.plist`.
- `NSFileManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.apple.freeform"`
  from a plain process resolves the path, but listing it fails:
  `couldn't be opened because you don't have permission`. The same applies to
  `group.com.apple.notes` and `group.com.apple.reminders` from this terminal, which has
  no Full Disk Access. Notes.app and Reminders.app declare the same
  `restricted-application-groups` entitlement, and this repo's `notes-cli` reaches the
  Notes group container with Full Disk Access. So Full Disk Access is the expected
  prerequisite here too. **This was not verified for Freeform on this host.**
- `~/Library/Containers/com.apple.freeform/Data/Library/Freeform/Boards/boards.db`
  is readable, but it is a **legacy pre-migration store**, left over from
  an older Freeform version. Do not use it as a data source.
- `~/Library/Containers/com.apple.freeform/Data/CloudKit/` holds the per-app `cloudd`
  cache and asset DBs.

### Schema (from a read-only copy of the legacy store, in a scratch directory outside the repository)

```sql
boards(board_identifier BLOB PK, owner_name, container_uuid, alternate_container_uuid,
       data BLOB, last_activity_time REAL, tombstoned INT, unsynced_changes,
       ckshare_unsynced_changes, sync_data BLOB, tombstone_date REAL,
       hide_from_recently_deleted INT, ckshare_data BLOB, min_required_version, is_discardable)
boards_metadata(board_identifier PK, crdt_data BLOB, is_favorite INT,
       enable_collaborator_cursors INT, view_state_data BLOB, ..., unsynced_changes, sync_data)
board_items(item_uuid, parent_uuid, board_identifier, item_type INT, common_data BLOB,
       specific_data BLOB, tombstoned INT, unsynced_changes, sync_data, min_required_version,
       object_options)  -- PK(item_uuid, board_identifier), tree via parent_uuid
freehand_drawing_buckets(...bucket_data BLOB, ck_mergeable_record_value_data...)
assets(asset_uuid, extension, tombstone_date), asset_references(...),
command_history_items(...), command_history_asset_references(...), key_value_data(...)
```

The current binary embeds migrations that add `folders`, `folders_metadata`,
`ck_record_cache`, `ck_zone_cache`, `purged_ck_record_cache` and capsule or
`ck_mergeable_record_value` columns. These come from `CRLBoardDataStore` ObjC getters
such as `foldersTableCreationSQLQuery`, `addParentReferenceToBoardsSQLQuery` and
`addBoardItemCKMergeableRecordValueMigrationQuery`. The live schema therefore also has
folders and board-to-folder parent references.

### Blob format

Every `data`, `crdt_data`, `common_data` and `specific_data` blob starts with
`63 72 64 74 06 00 00 00` (`"crdt"` + version 6), followed by a Coherence protobuf
document. `protoc --decode_raw` (strings redacted) shows nested CRDT
register/dictionary/attributed-string messages. Field semantics are defined by
Freeform's private Swift `CRStruct` types (`$s9Coherence10CRStruct_7P` conformances in
the app), not by a public schema.

## 3. Sync

- Each row carries `unsynced_changes` / `sync_data`. Sync is driven in-app by
  `CRLDatabaseSyncDataSource` and record types such as `CRLBoardItemSyncLocalChangeRecord`,
  `CRLBoardItemSyncRemoteRecord` and `CRLBoardMetadataSyncLocalChangeZone`, with CloudKit
  zones per board or share (`addZonesToRefetch:`, `fetchPendingZoneShareLeaves…`). Merges
  go through `CKMergeableDelta` (`_Coherence_CloudKit_Private`). Real-time collaboration
  uses `CRLBoardRealTimeChangeRecord`.
- A CLI cannot talk to `iCloud.com.apple.freeform` (container entitlements). Any local
  write made outside the app would be uploaded **only when Freeform.app next runs and
  scans `unsynced_changes`**. That behavior is inferred from the schema and class names,
  not observed.

## 4. App Intents surface

`Contents/Resources/Metadata.appintents/extract.actionsdata` lists 24 actions. Most
require feature flag `Freeform/AppIntents`. The column "opens app" is `openAppWhenRun`.

| Intent | Parameters | Opens app | Discoverable |
|---|---|---|---|
| `CRLCreateBoardIntent` | title, returns `CRLBoardEntity` | no | yes |
| `CRLUpdateBoardIntent` | target, title | no | yes |
| `CRLRenameBoardIntent` | entity, property | no | no |
| `CRLDeleteBoardIntent` | entities[] | no | yes |
| `CRLFavoriteBoardIntent_v2` | entity, favorite/unfavorite/toggle | no | yes |
| `CRLChangeBoardCanvasGridIntent` / `…ObjectConnectorsIntent` | entity, show/hide/toggle | no | yes |
| `CRLAddItemToBoardIntent` | target, itemType ∈ {circle, line, roundedRectangle, square, stickyNote, star, textBox, triangle, url, media}, text, mediaItems, url | no | yes |
| `CRLAddStickyNoteToBoardIntent`, `CRLAddTextToBoardIntent`, `CRLInsertShapeToBoardIntent`, `CRLInsertURLToBoardIntent`, `CRLInsertFilesToBoardIntent`, `CRLInsertPhotosToBoardIntent` | board + content | no | yes |
| `CRLInsertTextToBoardIntent` | board, strings, container ∈ {textbox, stickyNote} | no | no |
| `CRLOpenBoardIntent`, `CRLiOSOpenBoardIntent`, `CRLiOSCreateBoardIntent` | target | yes | yes |
| `CRLChangeSelection{Color,FontSize,FontStyle}Intent`, `CRLResizeSelectionFontIntent(_v2)` | act on the UI selection | yes | no |
| `CRLUtilitiesIntent` (hidden) | operation ∈ {boardID, downloadStatus, importBoard, exportBoard, shareBoard, acceptSharedBoard, stopSharingBoard, downloadBoard, resetBoard, manipulate}, arguments[String] → String | no | no |

The entity is `CRLBoardEntity` (mangled `8Freeform14CRLBoardEntityV`), with properties
title, creationDate, lastModificationDate, isFavorite, isCanvasDotGridEnabled and
isConnectorModeEnabled. The query is `CRLBoardQuery`, with capabilities 70.

There is no intent to read item content, edit or delete items, manage folders, list
Recently Deleted, restore, or add connectors. `CRLUtilitiesIntent` contains the string
"Manipulate items on a board", but it is hidden and its argument grammar is
undocumented.

### Live probe (read-only): LinkServices from a plain executable

The probe is a small ObjC tool built without ARC in a scratch directory outside the repository, and it has
since been deleted:

```text
LNMetadataProvider -actionsForBundleIdentifier:andActionIdentifier:error:
  -> NSCocoaErrorDomain 4097 "connection to service named com.apple.linkd.registry"
LNEffectiveBundleIdentifier initWithType:0 bundleIdentifier:"com.apple.freeform"
LNConnection initWithEffectiveBundleIdentifier:...appIntentsEnabledOnly:YES ... -> <LNMacApplicationConnection>
-performAllEntitiesQueryWithEntityMangledTypeName:"8Freeform14CRLBoardEntityV"
  -> LNConnectionErrorDomain 2700 "LNConnectionErrorCodeMissingConnectionEntitlement"
```

Of the inspected binaries, only `/usr/libexec/linkd` holds
`com.apple.private.appintents.connection`. `BackgroundShortcutRunner.xpc`, Spotlight and
NotificationCenter use `com.apple.linkd.registry` together with other private
`com.apple.private.appintents.*` keys. Conclusion: **App Intents execution and queries
are not reachable from an ordinary CLI.** This is an Apple signing restriction (the same kind
that keeps Clock alarms from non-Apple programs), and Privacy consent cannot fix it.

## 5. In-process model (path B) findings

The commands below build and run a probe that loads the app executable and lists its
classes:

```sh
clang -fobjc-arc -framework Foundation \
  -Wl,-rpath,/System/Applications/Freeform.app/Contents/Frameworks probe.m -o probe
./probe /System/Applications/Freeform.app/Contents/MacOS/Freeform
# OK .../MacOS/Freeform classes=1664     (dlopen of the MH_EXECUTE succeeds on macOS 27)
```

The `@rpath` for the bundled `TS*` frameworks is required. Without it, the result is
`Library not loaded: @rpath/TSFeatureFlags.framework`. A harmless duplicate-class
warning (`MicaPlayer`) is printed.

ObjC-visible surface (via `class_copyMethodList`):

- `Freeform.CRLBoardDataStore`: `+newTransientStoreWithQueue:error:`, `-init`,
  `-openDatabaseWithCompletionHandler:`, `-closeDatabaseWithCompletionHandler:`,
  `-beginExclusiveRead`/`-endExclusiveRead`, `-crdtContext` (a `CRContext`),
  `-dataDirectory`, `-storeName`, the migration-SQL getters, and zone-refetch and
  tombstone maintenance methods. **Live probe:** `+newTransientStoreWithQueue:error:`
  succeeded in a plain process. It returned a store at
  `$TMPDIR/com.apple.Unknown_<pid>_CRLBoardDataStore.transientStore_*/`, with
  `storeName = boardData` and `crdtContext = CRContext`. The temp directory was removed
  afterwards. This shows that Freeform persistence code runs outside the app.
- `Freeform.CRLBoardItemFactory` (ObjC): `makeTextboxItemWithString:`,
  `makeStickyNoteItemWithAttributedString:`,
  `makeShapeItemWithShapeType:pathSource:…stroke:fill:headLineEnd:tailLineEnd:`,
  `makeURLItemWithGeometry:metadataAsset:url:`,
  `makeImageItemWithGeometry:imageData:thumbnailData:`,
  `makeFileItemWithFileData:posterImageData:title:geometry:`,
  `makeTableItemWithRowCount:columnCount:geometry:`,
  `makeShapeItemForDiagramWithConnectingTo:with:shapeType:`,
  `makeGroupItemWithGeometry:childItems:error:` and `makeDuplicateOfBoardItems:`.
- Commands: `CRLCommandInsertBoardItems initWithParentContainer:boardItems:`,
  `CRLCommandDeleteBoardItems`, and `CRLCommandController
  initWithBoard:changeNotifier:selectionDispatcher:`, `-enqueueCommand:`,
  `-enqueueNonUndoableCommand:`. Library-level commands include
  `CRLBoardLibraryCommand{CreateFolder,RenameFolder,MoveItems,DeleteItems,UndeleteItems,DuplicateItems}`
  and `CRLCommandDuplicateBoard`.
- `Freeform.CRLBoard`: `-savePendingChanges`,
  `-asyncSavePendingChangesWithCompletionHandler:`,
  `-hasUnsyncedChangesWithCompletionHandler:`, `+defaultBoardTitle`.
- `CRLBoardFileReadAssistant -readBoardWithCompletionHandler:(CRLBoard, NSError)` and
  `CRLBoardFileWriteAssistant -writeBoard:completionHandler:` handle `.board` file
  import and export (UTType `com.apple.freeform.board`). Their real initializers are
  Swift-only.

**The missing links are all Swift-only:** `CRLBoardLibrary` exposes only `init` and
notification handlers. `CRLBoardLibraryHeadlessController` exposes only `init`.
`CRLBoardDataStoreProvider`, `CRLBoardEntityStore`, `CRLAppIntentsManager` and
`SQLiteDatabase` are pure Swift (`_SwiftObject`). No ObjC method returns a `CRLBoard`
for an identifier (a scan of all 1,664 classes for `open|fetch|loadBoard`, `boardWith`
and similar found only UI and editor accessors). With no exported symbols, calling
these needs class-metadata vtable slots or protocol witness tables, which must be
re-derived for every Freeform build.

Other risks of path B:

- `CRLBoardDataStore -init` targets the production store. Opening it runs
  `rewriteAllIdsIfNeeded`, `upgradeFor…` and the migrations, which write to the live
  database, so even reads are not read-only.
- The running Freeform.app keeps in-memory board state. Concurrent external writes may
  be ignored or overwritten. The app also posts real-time collaboration changes the CLI
  cannot.
- Without CloudKit entitlements, the CLI cannot upload or confirm sync. Sharing (`ckshare_data`) and
  shared-board operations are impossible.
- `platform-application`-only code paths (TCC `allow` for Photos and AddressBook,
  `AppContentHub`) may assert outside the app.

## 6. Other paths ruled out

- Spotlight: `mdfind` for `kMDItemContentType == "com.apple.freeform.board"` or
  `kMDItemBundleID == "com.apple.freeform"` returns 0 results. Freeform's CoreSpotlight
  items are not readable from a plain process.
- Share extension: `FreeformSharingExtension.appex` has principal class
  `CRLSEMacViewController`. It is interactive UI that needs user board selection, so it
  is not headless.
- The `freeform://` URL scheme and `.board` import via `open` are LaunchServices/UI
  navigation, not data access.
- `/usr/bin/shortcuts run` (path D) would run user-authored shortcuts containing the
  intents above through `BackgroundShortcutRunner`. It does not use a private framework
  and it requires a shortcut the user built in advance, so it does not meet the
  project's rules.

## 7. Parity matrix

| Operation | A (App Intents) | B (in-process) | C (SQLite read-only) |
|---|---|---|---|
| list boards, favorites, recent (`last_activity_time`) | entity query (blocked) | yes (Swift-only) | yes (title from CRDT `data`) |
| folders | no | yes (Swift-only) | yes (`folders` tables) |
| shared boards | no | read only | partial (`ckshare_data`, owner) |
| Recently Deleted | no | yes | yes (`tombstoned`, `tombstone_date`) |
| read board items (text, sticky notes, shapes, connectors, images, files, links) | no | yes (TSCL export possible) | partial; needs CRDT/struct reverse engineering |
| create, rename and delete boards | yes (blocked) | yes | no |
| add text, sticky notes, shapes, links, files and photos | yes (blocked) | yes (ObjC factory + commands) | no |
| add connectors | no | yes (`makeShapeItemForDiagramWithConnectingTo:`, `CRLConnectionLineItem`) | no |
| edit or delete items | no | yes | no |
| restore from Recently Deleted | no | yes (`CRLBoardLibraryCommandUndeleteItems`) | no |
| permanent delete, share, collaborate | no | no (CloudKit entitlements) | no |
| freehand drawings | no | read possible (PencilKit buckets) | no |

## Recommended implementation plan

1. **`freeform-cli` scaffold (no store access).** Add `guide`, `schema`, `capabilities`
   and `doctor`. `doctor` checks for the app executable, that it can be loaded with
   `dlopen`, that the expected ObjC classes and selectors exist, and whether the group
   container can be read (Full Disk Access). It does not open the store. `capabilities`
   lists each operation as blocked, with the evidence above. Add
   `apps/freeform/PRIVATE_BACKEND.md` in the style of the other apps.
2. **Read spike (path B, read-only, with Full Disk Access), time-boxed.** Copy the live
   `Boards/` directory into the `dataDirectory` of a store created by
   `+newTransientStoreWithQueue:error:`, so migrations only touch the copy. Open it with
   `-openDatabaseWithCompletionHandler:` and test whether a `CRLBoard` can be obtained
   without Swift vtable calls, for example via `CRLBoardFileReadAssistant` or other
   ObjC-visible routes. If the spike has to fall back to Swift ABI calls, put them
   behind `ObjCCallSwiftMethodValue`, with selector and metadata validation like the
   Weather and Maps runtime. Serialize items through the `CRLCLExport` → `TSContentLanguage`
   models to produce agent JSON.
3. **Optional fallback for listing (path C).** If the spike fails, open
   `sqlite3 -readonly` on a snapshot copy and return board id, title, favorite, folder,
   tombstone and dates. Write nothing. Label item content as unsupported rather than
   half-decoded.
4. **Writes: only after step 2 shows a stable `CRLBoard` handle.** Use
   `CRLBoardItemFactory` + `CRLCommandInsertBoardItems`/`CRLCommandDeleteBoardItems`
   through `CRLCommandController -enqueueNonUndoableCommand:`, then
   `-asyncSavePendingChangesWithCompletionHandler:`. Refuse to run while Freeform.app is
   running. Report `sync: pending_until_app_launch`. Do the first live test on a board
   named `QA-gesher-freeform` only, and delete it afterwards.
5. **Never in scope:** sharing, collaboration, permanent purge, and any App Intents
   execution unless Apple-signed entitlements become available.

Confidence:

- **High** that path A is blocked for unsigned CLIs. Verified with error 2700.
- **High** that the app model can be loaded in-process. `dlopen`, class listing and the
  transient store were all verified.
- **Medium** that Full Disk Access unlocks the group container. This is by analogy with
  Notes and was not verified, because this host lacks Full Disk Access.
- **Low to medium** that path B can reach maintainable read and write parity, because of
  the Swift-only, unexported entry points and the sync and concurrency risks above.

## Reproduction hygiene

- All store inspection used copies in a scratch directory outside the repository, opened
  with `sqlite3 -readonly`. The copies and probe binaries were deleted after the research.
- The live group container was never opened. The live store was never opened for writing.
- No App Intent was executed. The only call was the refused entity query.
