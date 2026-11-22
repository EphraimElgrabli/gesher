# Architecture

Seven executables (`notes-cli`, `reminders-cli`, `calendar-cli`, `contacts-cli`, `maps-cli`,
`weather-cli`, `freeform-cli`) plus the `gesher` launcher. Each executable is both a CLI and, via
`<app>-cli mcp`, a Model Context Protocol server for that app. There is no other runtime: no
Python, no wrapper process, no generated contract files, and no third-party Swift packages.

```
            agent (Codex, Claude, ...)                     human / script
                     │ MCP stdio                               │ argv
                     ▼                                         ▼
   <app>-cli mcp ─ MCPServer ──┐                ┌── AgentApp.run (CLI parser, help)
                               ▼                ▼
                ParamValidation  →  Input (Decodable)  →  AgentOperation.run(input, context)
                                                                  │
                                                     <App>Core repositories + runtime
                                                                  │
                                                     Apple private frameworks (dlopen)
```

## Layers

| Path | Role |
|---|---|
| `core/Sources/ObjCRuntimeSupport/` | C/arm64 typed `objc_msgSend` and Swift-ABI call shims |
| `core/Sources/GesherPlatform/` | framework loading, `DynamicRuntime`, `RuntimeCompatibility` (`OSGeneration`, multi-generation fallback resolvers), `MachOAnchorScanner`, `NativeProperty`, `NativeServiceReply`, TCC permissions, `AgentError`, `EntityResolver`, `DateInput`/`DateOutput`, `UserConfig`, `Batch`, `MutationVerification` |
| `core/Sources/GesherKit/Operations/` | `AgentOperation`, `Param`, `AnyOperation`, `AgentApp` (CLI dispatch, help, `schema`, `doctor`, `permissions`), `JSONValue`, `Gesher.version` |
| `core/Sources/GesherKit/MCP/` | `MCPServer`: newline-delimited JSON-RPC 2.0 over stdio |
| `apps/<app>/Sources/<App>Core/` | private-framework runtime, repositories, native snapshots; no CLI dependency |
| `apps/<app>/Sources/<App>Cli/` | `AgentApp` definition, context, operations and agent-facing output models |
| `config/privacy/<app>.plist` | bundle id and usage strings embedded in each Mach-O (`__TEXT,__info_plist`) |
| `plugins/gesher-<app>/` | agent plugin: `.claude-plugin/plugin.json` (Claude Code), `.codex-plugin/plugin.json` (Codex), `.mcp.json`, one skill; listed in `.claude-plugin/marketplace.json` |
| `install.sh`, `scripts/` | one-line installer, bundled installer, signing, packaging (`make dist`), `gesher` dispatcher |

## One declaration, two front ends

An operation declares `path`, `summary`, `params`, `effect`, `examples`, a `Decodable` `Input`, an
`Encodable` `Output` and `run`. Both front ends turn their input into the same JSON object (CLI
flags are parsed by `CLIArguments` using the declared params; MCP sends JSON), validate it with
`ParamValidation` (unknown keys, required params, types, ranges, defaults), decode `Input`, run,
and encode `Output` with one encoder. The MCP `inputSchema` and CLI help are generated from the
same `params`. They cannot drift, and `app.exampleFailures()` checks the documented examples.

The per-app context (runtime + repositories) is created lazily, after input validation, once per
process or MCP session. Repositories re-read native state on every call.

## MCP server

In-house rather than `modelcontextprotocol/swift-sdk`: the SDK's actor/async server would run
handlers off the main thread, while NotesShared requires the main thread and native replies spin
the current run loop (`NativeServiceReply`); it would also add swift-nio, swift-log, swift-system,
eventsource and a branch-pinned docc plugin. The protocol subset needed is small and tested
(`core/Tests/GesherKitTests/MCPServerTests.swift`).

- Methods: `initialize` (negotiates 2025-06-18 / 2025-03-26 / 2024-11-05), `ping`, `tools/list`,
  `tools/call`; notifications get no reply; unknown methods −32601; bad JSON −32700; unknown tool
  −32602.
- Results carry `structuredContent` (an object) and the same compact JSON as text content. Tool
  failures are results with `isError: true` and `{"error": {code, message, hint, candidates}}`.
- Requests are handled synchronously on the main thread. While serving, fd 1 is redirected to
  stderr so stray framework output cannot corrupt the protocol stream.
- Annotations come from `effect`: `readOnlyHint`, `destructiveHint`, `idempotentHint`.

## Errors and exit codes

`AgentError` (code, message, hint, candidates, details) is the only error shape callers see;
`AgentError.from` maps `PlatformError` and other coded errors and adds default hints. Exit
0 = success, 64 = caller must change input (`invalid_argument`, `ambiguous`,
`unknown_operation`), 1 = everything else, including partial batch failure.

## Installation

Releases are packaged by `scripts/package-release.sh` (`make dist`) as
`gesher-<version>-macos-arm64.tar.gz` (+ `.sha256`): `bin/` with the ad-hoc signed CLIs and
`gesher`, the bundled installer and its helper scripts, and `plugins/`. The root `install.sh`
(the `curl | bash` one-liner) downloads the archive of the latest GitHub release (or `--version`),
verifies the checksum and runs the bundled `install.sh --from bin`; from a checkout,
`scripts/install.sh` builds the release itself.

The bundled installer creates the "Gesher Local Signing" identity on first use, re-signs the CLIs
with it and installs an immutable directory
`~/.local/lib/gesher/releases/<version>-<time>-<commit>/` (read-only), switches the `current`
symlink atomically (`previous` keeps the old one; `--rollback` swaps them), copies `current` file
by file into `~/.local/lib/gesher/active/` and links `~/.local/bin/gesher` and `<app>-cli` to
`active/`. Commands it does not own are skipped, never replaced. The one-liner then adds
`~/.local/bin` to the PATH in `~/.zshrc` (or `~/.bash_profile`) and runs `connect.sh`.

`connect.sh` (`gesher connect`) registers one MCP server per app, `gesher-<app>`, with the AI apps
it finds. File-based clients (Claude Desktop, Cursor, VS Code, Windsurf/Devin, Gemini CLI,
Antigravity, LM Studio, opencode, Zed, Kiro, Warp, Cline) are edited in JavaScriptCore
(`osascript -l JavaScript`, used only as a JSON engine), which keeps key order and values; a file
with comments is never reformatted (the servers are inserted as text, or the snippet is printed).
Each changed file is backed up to `~/.config/gesher/backups/connect/` first. Claude Code gets the
plugins from the repository's marketplace (`claude plugin marketplace add EphraimElgrabli/gesher`,
which expands `${HOME}` in their `.mcp.json`), or `claude mcp add` for a custom prefix. Codex gets
`install-plugins.sh`: the plugins are copied into `~/.codex/plugins/` (with absolute command paths)
and listed in `~/.agents/plugins/marketplace.json`; updates refresh the copies. `--uninstall`
disconnects the AI apps and removes the links and `~/.local/lib/gesher`; it never deletes
`~/.config/gesher` or the signing identity.

## Concurrency and OS compatibility

One process handles one request at a time. `@unchecked Sendable` on runtimes does not make
repositories safe to share across threads. Private interfaces evolve across macOS releases:
`GesherPlatform` provides `OSGeneration`, `DynamicRuntime.resolveFirstClass/Selector/Symbol` for
ordered multi-generation symbol/selector fallbacks across apps, and `MachOAnchorScanner` for
unique-match structural anchor verification in loaded arm64 Mach-O images. Selectors, signatures
and build UUIDs are checked before invocation so unrecognized changes fail explicitly rather than
crashing.

## Permissions

### Structure

- `GesherPlatform/ResponsibleProcess`: makes each CLI its own TCC responsible process (below).
- `GesherPlatform/PermissionCoordinator`: first-use policy, bounded wait and injected backend tests.
- `GesherPlatform/TCCPermission`: private TCC preflight, callback-based request with the exported purpose option, and `requestRight` (`tcc_server_message_request_authorization_change`) for a specific right.
- `permissions` command/tool: built into every `AgentApp` that declares a `permission` service (`GesherKit/Operations/BuiltinOperations.swift`). Inspection opens no app data store; `--request` is explicit consent; `--open-settings` opens settings only. When access is missing it prints the `executable` that macOS grants access to. `doctor` reports the same preflight. An app may pass its own `permissionBackend` (Calendar does).
- `config/privacy/*.plist`: per-executable bundle identity and usage descriptions, embedded in Mach-O `__TEXT,__info_plist` through SwiftPM linker settings.
- Domain runtime gates: authorization before Calendar proxy, Contacts mapper, Reminders store initialization. Native store authorization remains independently checked.

Authorized access does not prompt. Denied access is not prompted again. Undecided access requests native consent. An unavailable TCC symbol is a backend error, never assumed access. Request timeouts are pending decisions with no write started. A successful callback with unresolved preflight is also pending. XPC disconnection after successful privacy preflight remains a native service error rather than a fabricated permission denial.

### Attribution: each CLI is its own responsible process

macOS attributes a privacy request to the *responsible* process. For a CLI started from a shell, that is the terminal or agent app (Terminal, an editor, or an agent app such as Codex), whose identity, purpose strings and hardened-runtime entitlements are used; hosts without `NSCalendarsUsageDescription` / `com.apple.security.personal-information.*` make tccd refuse to prompt (`requested: blocked`).

`AgentApp.main()` therefore re-executes the CLI once, as Apple's helper tools do: `posix_spawn` with the private `responsibility_spawnattrs_setdisclaim(attr, 1)` (libquarantine, resolved with `dlsym`), marker `GESHER_RESPONSIBLE=1` against loops. The child inherits stdin/stdout/stderr (MCP stdio works), the parent forwards INT/TERM/HUP/QUIT/USR1/USR2/WINCH and exits with the child's status or signal. tccd then uses the CLI's own path, signature and embedded Info.plist.

Policy: the parent first preflights the service as the host. If the host already holds the grant, the CLI runs in-process and inherits it (a terminal with Full Disk Access keeps working for Notes and Freeform; a host that already has Reminders keeps it). Otherwise the CLI disclaims and uses its own grant. Apps without a privacy service never re-execute. `GESHER_DISCLAIM=0` disables the re-exec.

### Calendar Full Access

On macOS 14+ a plain `TCCAccessRequest(kTCCServiceCalendar)` asks for write-only access (tccd `desired_auth=4`). `CADDatabaseRequestAccessForEntityType:desiredFullAccess:...` is refused by calaccessd for clients without an app bundle (error 1019). Calendar therefore asks tccd directly for right 2 (full access) with `tcc_server_message_request_authorization_change`, the call calaccessd itself makes; the dialog offers "Allow Full Access". Status comes from CalendarDaemon's `eventAuthorization` (3 full, 4 write-only), reported as `authorized` or `write_only`. Write-only access is reported with the exact System Settings change (Privacy & Security > Calendars > calendar-cli > Full Access).

### Full Disk Access

Full Disk Access has no dialog. `permissions --request` opens Privacy & Security > Full Disk Access, reveals the `executable` in Finder (to drag into the list), copies its path to the clipboard and prints it. No permission database is changed or reset, no identity is impersonated, and no private Apple signing entitlement is forged.

### Keeping grants across installs

tccd records a command-line tool's grant by its path plus its code requirement:

- ad-hoc signature: the requirement is the code hash, so every new build loses the grant;
- certificate signature: the requirement is `identifier "io.github.ephraimelgrabli.gesher.<app>" and certificate leaf = H"..."`, stable across builds.

`scripts/create-signing-identity.sh` creates a local self-signed code-signing certificate ("Gesher Local Signing") in the login keychain; the installer runs it on first install when the identity is missing, and `scripts/sign.sh` (run by `install.sh`) signs every CLI with it (`--sign-identity -` or `GESHER_SIGN_IDENTITY=-` signs ad-hoc instead). Release archives ship ad-hoc signed CLIs; the installer re-signs them locally. `install.sh` keeps immutable releases for rollback but runs the CLIs from a stable `PREFIX/lib/gesher/active/` directory, replaced file by file. Verified: a Contacts grant on an `active/` CLI survived reinstalls of the same build, a rollback, and an install of a rebuilt binary (new code hash). Development builds in `.build/release` are linker-signed ad-hoc on every build: run `scripts/sign.sh` after building to keep their grants. The binaries are not Developer ID signed or notarized.

### Verification

`make check` validates coordinator states, the disclaim policy and compiles all executables. No tests reset existing user permissions. Live checks on macOS 27 from an agent app: Contacts and Calendar (Full Access) prompts attributed to the CLIs and granted; Reminders and Full Disk Access stay inherited from a host that holds them (the CLI then runs in-process, no re-exec). From a host without them, Reminders prompts for the CLI and Full Disk Access must be granted to the printed `executable`.
