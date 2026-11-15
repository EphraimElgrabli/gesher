import Darwin
import Foundation

/// Makes a CLI its own TCC "responsible process", as Apple's helper tools do.
///
/// macOS attributes privacy requests to the responsible process: for a CLI started from a shell
/// that is the terminal or agent app (Terminal, an Electron host, Codex), whose purpose strings and
/// identity are used instead of the CLI's embedded `__info_plist`. Re-executing the CLI once with
/// `responsibility_spawnattrs_setdisclaim` (libquarantine, resolved at run time) makes the child
/// responsible for itself, so TCC uses the CLI's own bundle id, purpose strings and signature.
///
/// The parent only relays: the child inherits stdin/stdout/stderr (MCP stdio keeps working), the
/// parent forwards termination signals and exits with the child's status (or re-raises its signal).
public enum ResponsibleProcess {
    /// Set in the child so it never re-executes again.
    public static let markerVariable = "GESHER_RESPONSIBLE"
    /// `GESHER_DISCLAIM=0` keeps the launching app responsible (inherits its grants).
    public static let optOutVariable = "GESHER_DISCLAIM"

    /// Whether this process should re-execute itself as its own responsible process.
    /// Never for the child, nor when opted out. When the launching host is already authorized for
    /// `service` (e.g. a terminal that holds Full Disk Access or Reminders), its grant is kept.
    public static func shouldDisclaim(
        service: TCCService?, environment: [String: String] = ProcessInfo.processInfo.environment,
        hostAuthorized: (TCCService) -> Bool = { TCCPermission.shared.preflight(service: $0) == .authorized }
    ) -> Bool {
        guard let service, environment[markerVariable] == nil, environment[optOutVariable] != "0" else {
            return false
        }
        return !hostAuthorized(service)
    }

    /// Whether this process runs as a disclaimed child.
    public static var isDisclaimedChild: Bool { ProcessInfo.processInfo.environment[markerVariable] == "1" }

    /// Re-executes the current executable as its own responsible process and exits with its
    /// status. Returns only when the re-exec is unavailable (the caller then runs in-process).
    public static func relaunchDisclaimed() {
        guard let disclaim = disclaimFunction(), let path = executablePath() else { return }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return }
        defer { posix_spawnattr_destroy(&attributes) }
        guard disclaim(&attributes, 1) == 0 else { return }

        // The parent ignores forwarded signals; the child starts with default dispositions.
        let forwarded = [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGUSR1, SIGUSR2, SIGWINCH]
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in forwarded { sigaddset(&defaults, signal) }
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        var environment = ProcessInfo.processInfo.environment
        environment[markerVariable] = "1"
        let argv = CommandLine.arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }

        var child: pid_t = 0
        guard posix_spawn(&child, path, nil, &attributes, argv, envp) == 0 else { return }

        let sources = forwarded.map { signal -> DispatchSourceSignal in
            Darwin.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .global())
            source.setEventHandler { kill(child, signal) }
            source.resume()
            return source
        }

        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
        for source in sources { source.cancel() }

        let termination = status & 0x7f
        if termination == 0 { exit((status >> 8) & 0xff) }
        // The child died from a signal: die the same way so callers see the same status.
        Darwin.signal(termination, SIG_DFL)
        var unblock = sigset_t()
        sigemptyset(&unblock)
        sigaddset(&unblock, termination)
        sigprocmask(SIG_UNBLOCK, &unblock, nil)
        kill(getpid(), termination)
        exit(128 + termination)
    }

    private typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    private static func disclaimFunction() -> Disclaim? {
        let symbol =
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
            ?? dlopen("/usr/lib/system/libquarantine.dylib", RTLD_NOW).flatMap {
                dlsym($0, "responsibility_spawnattrs_setdisclaim")
            }
        return symbol.map { unsafeBitCast($0, to: Disclaim.self) }
    }

    /// The real executable (symlinks resolved), so the child's code identity is the CLI itself.
    public static func executablePath() -> String? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        guard let resolved = realpath(buffer, nil) else {
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
