# AGENTS.md

> Installing or using Gesher rather than changing it? Follow [docs/install.md](docs/install.md).

macOS CLIs and MCP servers for Apple apps, built only on Apple private frameworks. Read
[docs/architecture.md](docs/architecture.md) for the layout and [apps/weather](apps/weather) for the
reference implementation. Privacy onboarding details: [docs/permissions.md](docs/permissions.md).

## Hard rules

1. **Private frameworks only.** No AppleScript/osascript, no EventKit, `CNContactStore`, MapKit or
   other public data stores, no raw database or preference-file writes, no entitlement spoofing,
   no UI automation. Public value types (e.g. `CLLocation`, `DateComponents`) may carry values
   into private APIs. Missing selectors, permissions or daemon replies are errors, never invented
   defaults.
2. **Never touch the owner's real data in tests or checks.** Read-only live checks are fine.
   Writes go to isolated stores (temporary directories, in-memory contexts), or to live fixtures
   named `QA-gesher-*`, deleting exactly the ids you created (children before parents).
3. **No personal data** (names, emails, addresses) in code, tests, fixtures or docs.
4. `make check` (swift-format lint `--strict`, all tests, release build) passes on every commit.
   Conventional Commits, small and compiling. Do not push or merge unless asked.
5. Build output stays in `.build/`; scratch files go outside the repo.

## The operation pattern (every app follows it)

One `AgentOperation` type per user-facing action. Its declaration is the single source of truth
for the CLI subcommand, the CLI help, the MCP tool, the JSON Schema and argument validation:

```swift
enum HourlyForecast: AgentOperation {
    struct Input: Decodable, Sendable {      // property names == Param names
        var place: String?
        var hours: Int                       // has a declared default, so non-optional
        var from: NaturalDate?               // natural dates parse while decoding
    }
    static let path = ["hourly"]             // CLI words; MCP tool name = path joined by "_"
    static let summary = "Hour-by-hour forecast (temperature, rain chance, wind) for a place."
    static let params: [Param] = [
        .string("place", "City, saved location name, or 'lat,lon'. Default: your default place.", positional: true),
        .integer("hours", "Number of hours to return.", default: 24, min: 1, max: 240),
        .date("from", "First hour to include, e.g. 'tomorrow 6:00'."),
    ]
    static let examples = ["hourly Haifa --hours 6"]     // validated by tests
    // static let effect = OperationEffect.write / .destructive   (default .read)

    // static func validate(_ input: Input) throws   (optional: semantic checks, before the context)
    static func run(_ input: Input, _ context: WeatherContext) throws -> HourlyOutput { ... }
    static func pretty(_ output: HourlyOutput) -> String? { ... }    // optional, --format pretty
}
```

Register it in the app's `AgentApp(... operations: [AnyOperation(HourlyForecast.self), ...])`. That
gives `<app>-cli hourly ...`, `gesher <app> hourly ...`, the `hourly` MCP tool in
`<app>-cli mcp`, `<app>-cli hourly --help` and `<app>-cli schema hourly`. Built-ins `doctor`,
`permissions` (when the app declares a TCC service), `schema`, `mcp`, `--version` come for free.

Core API (`core/Sources/`):

| Need | Use |
|---|---|
| Declare an operation / app | `AgentOperation`, `Param`, `AgentApp`, `NoInput` (`GesherKit/Operations/`) |
| Release version | `Gesher.version` (keep `config/privacy/*.plist` in step) |
| Name-or-id selector | `EntityResolver.resolve(_:in:type:id:name:detail:policy:)` / `resolveAll` |
| Errors | `AgentError(code:message:hint:candidates:)`, `.invalid`, `.notFound`, `.ambiguous`, `AgentError.from` |
| Dates in / out | `NaturalDate` input, `DateInput`, `DateOutput.iso/day` (user's or the item's time zone) |
| Defaults | `UserConfig.load().value(app, key)` (`~/.config/gesher/config.json`) |
| Batch | `Batch.run(items, label:) { item in ... }` returning `BatchResult<T>` |
| Verified writes | `MutationVerification.readback` / `.absence` |
| Tests | `app.exampleFailures()` must be `[]`; `app.run(args, stdout:, stderr:)` for CLI tests |

## Conventions

- **Selectors take a name or an id.** Resolve with `EntityResolver`: exact id, exact name,
  normalized name (case, diacritics, Hebrew niqqud, emoji, punctuation ignored), unique prefix,
  then all-words/substring. Several matches fail with `ambiguous` + `candidates`; none fails with
  `not_found` + suggestions. Destructive operations use `policy: .exactName`.
- **Sensible defaults.** Explicit input > `UserConfig` > the app's native default (default list,
  calendar, account) > a documented fallback. Echo what was chosen in the output (e.g. `place`,
  `list`) so the caller can check it. Dates: accept `NaturalDate`; interpret in the user's time
  zone; output ISO 8601 with offset (`DateOutput.iso`) or a plain day for all-day values.
- **Compact output, user fields only.** Define output structs in the CLI target for the agent,
  separate from native snapshots: a stable `id`, user-meaningful fields, no change tags, native
  codes, provider/framework names or duplicated units; optionals are omitted when absent (never
  `null`). Lists return an object (`{"items": [...]}` or a named key), not a bare array. Round
  measurements. JSON is compact by default; `--format pretty` uses `pretty(_:)` or the generic
  renderer.
- **Batch where users act on many items** (add/complete/delete several): a list param, positional
  on the CLI, returning `BatchResult` so each item succeeds or fails independently. Partial
  failure exits 1 but prints every result; MCP marks `isError` only if nothing succeeded.
- **Actionable errors.** Throw `AgentError` with a stable snake_case `code`, a message saying what
  happened, and a `hint` saying what to do next. Exit codes: 0 ok, 64 caller must change input
  (`invalid_argument`, `ambiguous`, `unknown_operation`), 1 everything else. Validation happens
  before the context (and any private framework) is created.
- **Writes are verified.** Read back through a fresh native context with `MutationVerification`;
  a failed readback is `save_failed` ("may have committed; read before retrying"). Where the
  backend has revisions or change tags, accept an optional `ifRevision`-style precondition
  (optimistic concurrency) and return the new revision.
- **Effects are declared.** `.read`, `.write`, `.destructive` drive MCP annotations; set
  `idempotent = true` for writes that are safe to repeat.

## Adding an app or a new area (checklist)

All seven apps follow this layout; copy the closest one (Weather is the reference).

1. Package: `<App>Core` library, `<App>Cli` executable with `privacyLinkerSettings("<app>")` and
   `config/privacy/<app>.plist`, `<App>CliTests`. Add the app to the `apps` lists in
   `scripts/` (`install.sh`, `sign.sh`, `package-release.sh`, `gesher`), `scripts/smoke-mcp.py`
   and `APPS` in the Makefile. No third-party packages.
2. `apps/<app>/Sources/<App>Cli/<App>Cli.swift`: `@main` calling `<App>App.make().main()` and a
   context class holding runtime + repositories (+ `UserConfig`), with a test initializer that
   injects isolated stores.
3. One file per area under `Operations/` with the operations and their output models; reusable
   resolution and defaults go into `<App>Core` repositories.
4. Tests: examples validate, invalid input exits 64 without creating the context, output models
   omit internal fields, write lifecycle against an isolated store (or `QA-gesher-*` fixture).
5. `plugins/gesher-<app>/skills/gesher-<app>/SKILL.md` (plus `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.mcp.json` and an entry in `.claude-plugin/marketplace.json`) describes workflows with the tool names, not
   a schema dump; keep the app README and the table in the root README (tool counts) current.
6. `make check`, then a live read-only smoke run of the release binary and
   `python3 scripts/smoke-mcp.py --bin-dir .build/release`.

## Commands

```sh
make build | make test | make lint | make format | make check | make dist
scripts/install.sh [--prefix DIR] [--skip-build] [--from DIR] [--no-plugins] | --rollback | --uninstall
scripts/connect.sh [AI apps...] [--all] [--list] [--remove] [--print] [--apps weather,maps] [--bin-dir DIR]
scripts/install-plugins.sh [--apps weather,maps] [--bin-dir DIR] [--codex-home DIR] [--marketplace FILE]
./install.sh --archive dist/gesher-<version>-macos-arm64.tar.gz --prefix DIR   # test a packaged release
scripts/test-native-fixtures.py --run-live     # opt-in, writes QA-gesher-* fixtures only
```
