# Notes

`notes-cli` reads and edits Apple Notes through the runtime-loaded private frameworks
NotesShared/NotesSupport, with NotesEditor for tables. It does not use AppleScript, Apple Events,
GUI automation, SQL, or hand-edited Notes database files. Every command is also an MCP tool:
`notes-cli mcp`, where the tool name is the path joined with `_` (`note get` becomes `note_get`).
See [AGENTS.md](../../AGENTS.md) for the operation pattern.

## Permissions

The in-process Notes context opens the user's real Notes store. For that, the app that launches
the CLI (terminal, agent host) needs Full Disk Access, and it must be restarted after access is
granted. `notes-cli permissions` reports the state and `notes-cli doctor` checks the setup without
reading notes. If the store cannot be opened, the command fails and no substitute database is
created. Calls run on the main thread, and the MCP server keeps them there.

## Commands

```sh
notes-cli account list
notes-cli folder list [--account NAME]
notes-cli folder create Recipes 'Q1' --parent Work          # batch
notes-cli folder rename Recipes --name Cooking
notes-cli folder move Work/Q1 --parent Archive              # omit --parent: top level
notes-cli folder delete 'Old ideas'                         # notes go to Recently Deleted

notes-cli note list [FOLDER] [--tag '#travel'] [--pinned] [--recently-deleted] [--limit 50 --offset 0]
notes-cli note get 'Shopping list' [--folder Home] [--content markdown|text|document|none]
notes-cli note search 'olive oil' [--folder Home] [--limit 20]
notes-cli note create '- [ ] milk' --title Groceries --folder Home [--pinned]
notes-cli note append --note Journal '## Friday' [--if-revision REV]
notes-cli note prepend --note Inbox '- [ ] Renew passport'
notes-cli note update 'Old name' --title 'New name'
notes-cli note update Draft --markdown '...' --replace-body --if-revision REV
notes-cli note move 'Paris trip' 'Rome trip' --folder Travel # batch
notes-cli note pin|unpin 'Shopping list'
notes-cli note delete 'Old draft' [--permanent]             # permanent: only from Recently Deleted
notes-cli note restore 'Old draft' [--folder Work]

notes-cli checklist list Groceries
notes-cli checklist add --note Groceries milk eggs [--checked] [--top]
notes-cli checklist check|uncheck --note Groceries milk 3   # by text or number
notes-cli table set-cell Budget --row 2 --column 3 --text 120 --if-revision REV
notes-cli tag list
notes-cli tag add --note 'Paris trip' travel ideas         # real #tags
notes-cli smart-folder create Travel --tags travel --match any
notes-cli note list Travel                                  # notes the smart folder shows
notes-cli attachment add --note 'Trip receipts' ~/Desktop/receipt.pdf
notes-cli attachment list 'Trip receipts'
notes-cli attachment export 'Trip receipts' --attachment receipt.pdf --to ~/Downloads
```

Options can also be passed as one JSON object with `--json '{...}'` or `--input FILE|-`. Output is
compact JSON (`--format pretty` for people). `notes-cli <command> --help` and `notes-cli schema`
show the parameters.

## Behavior

- **Selectors.** Notes and folders take a title/name or an id. Folders also take a `Parent/Child`
  path. Matching ignores case, diacritics, Hebrew niqqud, emoji and punctuation. Reads also accept
  a unique prefix or words; writes to existing notes and folders need the exact (normalized)
  name or the id. More than one match returns `ambiguous` with candidates.
- **Defaults.** New notes go to `--folder`, else `notes.folder` in
  `~/.config/gesher/config.json`, else the account's default folder.
- **Markdown in.** Headings, bullets, numbered items, checklists, two-space indentation, quotes,
  fenced code (monospaced), GFM tables, bold, italic, strikethrough and http/https/mailto links.
  A leading `# Title` line becomes the note title. `--document` takes the rich JSON form instead:
  paragraphs with `style`, `runs`, `checked`, `indent`, `quote`, `table`; runs with `bold`,
  `italic`, `underline`, `strikethrough`, `link`, `highlight` (1–5).
- **Content out.** Markdown (default), plain text, or `document`: the same JSON with
  read-only `attachment` references. Hashtags, mentions and inline links show their display
  text. Results include `tags`, `attachments` and a `revision`.
- **Tags.** `#word` in Markdown (a letter first; letters, digits, `-`, `_`; after a space) becomes a
  real Notes tag (`ICInlineAttachment` hashtag + `ICHashtag`), as typing it in the app does; `C#`
  and `#1` stay text, `\#word` escapes. In `document` form a tag is a run with `"tag": true`.
- **Smart folders.** `note list <smart folder>` evaluates the folder's own native query.
  `smart-folder create` builds a tag query (all/any of existing tags); `folder delete` removes a
  smart folder without touching any note.
- **Attachments.** `attachment add` imports files with `ICNote addAttachmentWithFileURL:` and embeds
  each on its own line at the end; only that range of the text changes. Hidden files and folders,
  `~/Library` (iCloud Drive excepted), system files and key or credential files are refused, after
  resolving symbolic links; a note shared through iCloud needs `--confirm-shared`. `attachment
  export` does not write into hidden folders, `~/Library` or system folders.
- **Edits.** `append`, `prepend`, `checklist add`, `tag add` and `attachment add` insert only their
  new range into the native mergeable text; `checklist check/uncheck` change only the paragraph
  style attributes. Existing formatting, tables and attachments are untouched, and the note's
  modification date moves to now, as editing in the app does. Replacing a body
  needs `replaceBody` and `ifRevision`. Each write is read back through the native context
  before it reports success.
- **Delete.** `note delete` moves notes to Recently Deleted (as Notes does). `note restore` moves
  them back out. `--permanent` erases notes that are already there. `folder delete` first moves
  the folder's notes to Recently Deleted, and it refuses folders that still have subfolders.
- **Locked notes** are listed with `locked: true`. They are never unlocked, and their content
  cannot be read or edited.

## Limits

- Smart folders can be created from tags only (other filters: date, checklists, attachments,
  folders... are read and listed, not created). Renaming or removing a tag everywhere is not supported.
- Attachments can be added and exported, not removed individually (remove them by replacing the
  body). Drawings and link cards may have no file.
- Notes cannot be moved between accounts. Shared notes, collaboration, and locking or unlocking
  are out of scope.
- The revision is checked before the write. It is not a lock across processes. A successful
  local save does not mean iCloud upload has finished.

## Tests

`swift test --filter Notes` covers the Markdown codec, compact output, input validation, and a
CLI lifecycle against an in-memory native store. Tests never open the user's Notes store. Live
write checks use only a folder named `QA-gesher-notes` and delete exactly what they created.
