import GesherKit
import GesherPlatform
import Foundation
import FreeformCore

@main
enum FreeformCli {
    static func main() { FreeformApp.make().main() }
}

/// The Freeform app. Reads decode a temporary copy of the store with Freeform's own model types;
/// writes go through Freeform's import inbox, so the app itself creates, saves and syncs the
/// content (see FreeformImporter and RESEARCH.md).
enum FreeformApp {
    static func make(context: @escaping () throws -> FreeformContext = { FreeformContext() })
        -> AgentApp<FreeformContext>
    {
        AgentApp(
            name: "freeform",
            summary: "Read Freeform boards and their items; create boards and add text, links, images and files.",
            instructions: """
                Boards accept a title or an id; on 'ambiguous' retry with a candidate id. boards_list and \
                items_list read a temporary copy of the store (titles, folders, favorites, item text, \
                positions, sizes, colors, stacking order); search finds text, links and file names across \
                boards. boards_create and items_add hand content to the Freeform app, which places it on the \
                board and syncs it; positions cannot be chosen. Renaming, favoriting, deleting boards and \
                editing or deleting items are not available: tell the user to do those in Freeform.
                """,
            permission: .fullDiskAccess,
            operations: [
                AnyOperation(FreeformDoctor.self),
                AnyOperation(ListBoards.self),
                AnyOperation(GetBoard.self),
                AnyOperation(ListItems.self),
                AnyOperation(SearchBoards.self),
                AnyOperation(CreateBoard.self),
                AnyOperation(AddItems.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Freeform operation for the life of the process (or MCP session).
final class FreeformContext {
    let store: FreeformStore
    let importer: FreeformImporter
    /// Opens Freeform when it is not running, so it imports queued content.
    let launchApp: () throws -> Void
    /// How long a write waits for Freeform to import and save the content.
    let importTimeout: TimeInterval

    init(
        store: FreeformStore = FreeformStore(), importer: FreeformImporter? = nil,
        launchApp: @escaping () throws -> Void = { try FreeformImporter.launchAppIfNeeded() },
        importTimeout: TimeInterval = 45
    ) {
        self.store = store
        self.importer = importer ?? FreeformImporter(groupContainer: store.groupContainer)
        self.launchApp = launchApp
        self.importTimeout = importTimeout
    }

    func snapshot<T>(_ body: (FreeformSnapshot) throws -> T) throws -> T {
        try store.withSnapshot(try store.requireLocation(), body)
    }

    func board(_ selector: String, in snapshot: FreeformSnapshot, includeDeleted: Bool = false) throws
        -> FreeformBoardSnapshot
    {
        try EntityResolver.resolve(
            selector, in: try snapshot.boards(includeDeleted: includeDeleted), type: "board", id: \.id,
            name: { $0.title ?? "" }, detail: { $0.lastActivityAt.map { DateOutput.iso($0) } })
    }
}

enum FreeformDoctor: AgentOperation {
    static let path = ["doctor"]
    static let summary = "Check Freeform, Full Disk Access, the board store and Freeform's model types."
    static let params: [Param] = []
    static let examples = ["doctor"]

    static func run(_ input: NoInput, _ context: FreeformContext) throws -> DoctorOutput {
        let store = context.store
        let app = Bundle(path: FreeformModelRuntime.appPath)
        let readable = store.groupContainerReadable()
        let location = try? store.locate()
        var model = "ok"
        do {
            let missing = try FreeformModelRuntime.load().missingTypes()
            if !missing.isEmpty { model = "missing: " + missing.joined(separator: ", ") }
        } catch {
            model = AgentError.from(error).message
        }
        let hint: String? =
            !readable
            ? "Give the app that runs freeform-cli Full Disk Access (System Settings > Privacy & Security), then restart it."
            : location == nil
                ? "No Freeform board store was found; open Freeform once to create it."
                : model != "ok" ? "This Freeform version's model is not supported; reads may omit fields." : nil
        return DoctorOutput(
            app: "freeform", version: AgentApp<FreeformContext>.version,
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            freeform: app?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            freeformRunning: FreeformImporter.isAppRunning,
            permission: PermissionCoordinator().inspect(service: .fullDiskAccess).permission,
            groupContainerReadable: readable, store: location?.kind.rawValue,
            storeModifiedAt: location.flatMap { lastModified($0.database) }.map { DateOutput.iso($0) }, model: model,
            hint: hint)
    }

    private static func lastModified(_ database: URL) -> Date? {
        ["", "-wal"].compactMap { suffix in
            try? FileManager.default.attributesOfItem(atPath: database.path + suffix)[.modificationDate] as? Date
        }.max()
    }
}

struct DoctorOutput: Encodable, Sendable {
    let app: String
    let version: String
    let os: String
    /// Installed Freeform version; nil when Freeform is not installed.
    let freeform: String?
    let freeformRunning: Bool
    /// Full Disk Access, named `permission` like every other app's doctor.
    let permission: String
    let groupContainerReadable: Bool
    /// `group_container` (current), `legacy_container` (pre-migration) or absent.
    let store: String?
    let storeModifiedAt: String?
    /// `ok` when every Freeform model type used for decoding resolves.
    let model: String
    let hint: String?
}
