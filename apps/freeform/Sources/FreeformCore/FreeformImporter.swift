import AppKit
import GesherPlatform
import Foundation
import UniformTypeIdentifiers

/// Content handed to Freeform through its own import inbox (see `FreeformImporter`).
public enum FreeformImportContent: Sendable, Equatable {
    case text(String)
    case link(URL, title: String?)
    /// A local image, PDF or other document; Freeform makes an image item for images, else a file item.
    case file(URL)
}

/// Writes through Freeform's sharing-extension inbox, which Freeform itself imports.
///
/// Freeform's Share extension hands content to the app as a directory
/// `<group container>/Import/<import UUID>/` holding `Manifest.plist` (Freeform's
/// `CRLSEImportManifest`: target `boardUUID` or a new board `title`, optional `folderUUID`, and
/// `items` of text, URL or file URL + `mediaUTI`) plus the media files. The app imports such a
/// directory when it launches, and immediately while running when the write is coordinated on the
/// `Import` directory it presents (`CRLSEImporter` is its `NSFilePresenter`). Freeform then creates
/// the board items with its own commands, saves and syncs them, and deletes the directory. This
/// process never writes Freeform's database.
public final class FreeformImporter: @unchecked Sendable {
    public static let bundleIdentifier = "com.apple.freeform"
    public let groupContainer: URL
    private let fileManager = FileManager.default

    public init(groupContainer: URL) {
        self.groupContainer = groupContainer
    }

    public var importDirectory: URL { groupContainer.appendingPathComponent("Import", isDirectory: true) }

    /// Freeform's `CRLSEManifestItem` / `CRLSEImportManifest` (property names are the plist keys).
    struct ManifestItem: Codable, Equatable {
        var itemUUID: UUID
        var title: String?
        var attributedText: AttributedString?
        var url: URL?
        var mediaUTI: UTType?
    }

    struct Manifest: Codable, Equatable {
        var boardUUID: UUID?
        var folderUUID: UUID?
        var ownerName: String?
        var title: String
        var items: [ManifestItem]
    }

    /// Queues one import and returns its id. `board` nil creates a new board titled `title`.
    @discardableResult
    public func submit(board: UUID?, title: String, folder: UUID?, contents: [FreeformImportContent]) throws -> UUID {
        guard fileManager.fileExists(atPath: groupContainer.path) else {
            throw PlatformError.storeInitializationFailed(
                "Freeform's group container does not exist; open Freeform once.")
        }
        let id = UUID()
        var coordinationError: NSError?
        var writeError: Error?
        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: importDirectory, options: [], error: &coordinationError
        ) { root in
            do {
                try self.write(id: id, in: root, board: board, title: title, folder: folder, contents: contents)
            } catch {
                writeError = error
                try? self.fileManager.removeItem(at: root.appendingPathComponent(id.uuidString))
            }
        }
        if let error = coordinationError ?? writeError {
            throw PlatformError.saveFailed("Could not hand the content to Freeform: \(error.localizedDescription)")
        }
        return id
    }

    func write(
        id: UUID, in root: URL, board: UUID?, title: String, folder: UUID?, contents: [FreeformImportContent]
    ) throws {
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        var items: [ManifestItem] = []
        for content in contents {
            let itemID = UUID()
            switch content {
            case .text(let text):
                items.append(ManifestItem(itemUUID: itemID, attributedText: AttributedString(text)))
            case .link(let url, let linkTitle):
                items.append(ManifestItem(itemUUID: itemID, title: linkTitle, url: url))
            case .file(let source):
                let folder = directory.appendingPathComponent(itemID.uuidString, isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
                let target = folder.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: target)
                let type = UTType(filenameExtension: source.pathExtension) ?? .data
                items.append(
                    ManifestItem(itemUUID: itemID, title: source.lastPathComponent, url: target, mediaUTI: type))
            }
        }
        let manifest = Manifest(boardUUID: board, folderUUID: folder, title: title, items: items)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        // Manifest last: the directory is complete before Freeform can see a manifest in it.
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("Manifest.plist"), options: .atomic)
    }

    /// Whether Freeform has consumed (imported or discarded) the import directory.
    public func isPending(_ id: UUID) -> Bool {
        fileManager.fileExists(atPath: importDirectory.appendingPathComponent(id.uuidString).path)
    }

    public static var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// True when Freeform is currently the frontmost active application.
    public static var isAppActive: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
    }

    /// Whether Quick Refresh is enabled when Freeform has a visible window open.
    /// Enabled by default so users can work alongside agents; override via `GESHER_FREEFORM_LIVE_REFRESH=0`
    /// or `{"freeform": {"liveRefresh": "off"}}` in `~/.config/gesher/config.json`.
    public static func liveRefreshEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if let raw = environment["GESHER_FREEFORM_LIVE_REFRESH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !raw.isEmpty
        {
            return !["0", "false", "off", "no"].contains(raw)
        }
        if let configured = UserConfig.load(environment: environment).value("freeform", "liveRefresh")?.lowercased() {
            return !["0", "false", "off", "no"].contains(configured)
        }
        return true
    }

    /// True when Freeform has at least one normal on-screen window (ignoring menu-bar/background helper layers).
    public static var hasVisibleWindows: Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let pids = Set(apps.map(\.processIdentifier))
        guard !pids.isEmpty else { return false }
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return true }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid) else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double, w > 50, h > 50
            {
                return true
            }
        }
        return false
    }

    /// Gracefully terminates Freeform and waits until it exits. Returns true when Freeform is no longer running.
    @discardableResult
    public static func terminateApp(timeout: TimeInterval = 6) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !apps.isEmpty else { return true }
        for app in apps { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while isAppRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.15)
        }
        return !isAppRunning
    }

    /// Reopens Freeform visibly (directly to `freeform://board?id=<UUID>` when `boardID` is provided)
    /// while preserving focus when `activate` is false so the user's chat/editor stays focused.
    public static func reopenApp(boardID: String? = nil, activate: Bool = false) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.hides = false
        let appURL = URL(fileURLWithPath: FreeformModelRuntime.appPath)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        if let boardID, UUID(uuidString: boardID) != nil,
            let deepLink = URL(string: "freeform://board?id=\(boardID)")
        {
            NSWorkspace.shared.open([deepLink], withApplicationAt: appURL, configuration: configuration) { _, error in
                failure = error
                done.signal()
            }
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                failure = error
                done.signal()
            }
        }
        if done.wait(timeout: .now() + 15) == .timedOut || failure != nil {
            throw PlatformError.privateBackendUnavailable(
                "Freeform could not be reopened: \(failure?.localizedDescription ?? "timed out").")
        }
    }

    /// Opens Freeform in the background when it is not running (it imports pending content at launch).
    public static func launchAppIfNeeded() throws {
        guard !isAppRunning else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        let app = URL(fileURLWithPath: FreeformModelRuntime.appPath)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            failure = error
            done.signal()
        }
        if done.wait(timeout: .now() + 30) == .timedOut || failure != nil {
            throw PlatformError.privateBackendUnavailable(
                "Freeform could not be opened: \(failure?.localizedDescription ?? "timed out").")
        }
    }

    /// Polls `check` until it returns a value or `timeout` passes.
    public static func wait<T>(timeout: TimeInterval, interval: TimeInterval = 0.5, _ check: () throws -> T?) rethrows
        -> T?
    {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = try check() { return value }
            Thread.sleep(forTimeInterval: interval)
        } while Date() < deadline
        return try check()
    }
}
