import CryptoKit
import GesherPlatform
import Foundation
import SQLite3

/// Where Freeform keeps its board database, and whether this process can read it.
public struct FreeformStoreLocation: Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// The current store in the `group.com.apple.freeform` group container.
        case groupContainer = "group_container"
        /// The pre-migration store in the app's own container (older Freeform versions).
        case legacyContainer = "legacy_container"
    }

    public let kind: Kind
    public let database: URL
}

public struct FreeformBoardSnapshot: Sendable, Equatable {
    public enum Sharing: String, Sendable { case owner, participant }

    public let id: String
    public let title: String?
    public let favorite: Bool
    public let folderID: String?
    public let folder: String?
    public let deleted: Bool
    public let deletedAt: Date?
    public let createdAt: Date?
    public let lastActivityAt: Date?
    public let sharing: Sharing?
    /// Root container of the canvas (items whose parent it is are top level).
    public let rootContainerID: String?
    public let itemCount: Int
    /// Deterministic content revision of the board and its live items for optimistic concurrency.
    public let revision: String?

    public init(
        id: String, title: String?, favorite: Bool, folderID: String?, folder: String?, deleted: Bool,
        deletedAt: Date?, createdAt: Date?, lastActivityAt: Date?, sharing: Sharing?, rootContainerID: String?,
        itemCount: Int, revision: String? = nil
    ) {
        self.id = id
        self.title = title
        self.favorite = favorite
        self.folderID = folderID
        self.folder = folder
        self.deleted = deleted
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.sharing = sharing
        self.rootContainerID = rootContainerID
        self.itemCount = itemCount
        self.revision = revision
    }
}

public struct FreeformFolderSnapshot: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let parentID: String?
    public let deleted: Bool
}

public struct FreeformColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// `#RRGGBB`, or `#RRGGBBAA` when not opaque.
    public var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 0.999 ? byte(alpha) : "")
    }

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private static let namedColors: [String: FreeformColor] = [
        "yellow": FreeformColor(red: 1.0, green: 0.89, blue: 0.36),
        "blue": FreeformColor(red: 0.25, green: 0.56, blue: 0.96),
        "green": FreeformColor(red: 0.30, green: 0.78, blue: 0.48),
        "pink": FreeformColor(red: 0.96, green: 0.45, blue: 0.67),
        "orange": FreeformColor(red: 0.98, green: 0.58, blue: 0.22),
        "purple": FreeformColor(red: 0.65, green: 0.44, blue: 0.95),
        "red": FreeformColor(red: 0.91, green: 0.30, blue: 0.24),
        "teal": FreeformColor(red: 0.20, green: 0.73, blue: 0.76),
        "gray": FreeformColor(red: 0.56, green: 0.56, blue: 0.58),
        "grey": FreeformColor(red: 0.56, green: 0.56, blue: 0.58),
        "white": FreeformColor(red: 1.0, green: 1.0, blue: 1.0),
        "black": FreeformColor(red: 0.0, green: 0.0, blue: 0.0),
        "clear": FreeformColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
    ]

    /// Parses `#RGB`, `#RRGGBB`, `#RRGGBBAA` or a standard color name.
    public static func parse(_ raw: String) throws -> FreeformColor {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let named = namedColors[trimmed.lowercased()] { return named }
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let expanded: String
        switch hex.count {
        case 3:
            expanded = hex.map { "\($0)\($0)" }.joined() + "FF"
        case 6:
            expanded = hex + "FF"
        case 8:
            expanded = hex
        default:
            throw AgentError.invalid(
                "Invalid color '\(raw)'.",
                hint:
                    "Use #RRGGBB, #RRGGBBAA or a named color (yellow, blue, green, pink, orange, purple, red, teal, gray, white, black)."
            )
        }
        guard let value = UInt32(expanded, radix: 16) else {
            throw AgentError.invalid(
                "Invalid hex color '\(raw)'.", hint: "Use #RRGGBB or #RRGGBBAA, e.g. #3B82F6.")
        }
        return FreeformColor(
            red: Double((value >> 24) & 0xFF) / 255.0,
            green: Double((value >> 16) & 0xFF) / 255.0,
            blue: Double((value >> 8) & 0xFF) / 255.0,
            alpha: Double(value & 0xFF) / 255.0)
    }
}

/// Decoded items of a board together with explicit diagnostics for unsupported or partially decoded rows.
public struct FreeformItemsReport: Sendable, Equatable {
    public let items: [FreeformItemSnapshot]
    public let unsupportedCount: Int
    public let partialDecodeCount: Int
}

public struct FreeformItemSnapshot: Sendable, Equatable {
    public let id: String
    public let kind: FreeformItemKind
    /// `text` for a text box (a shape with no fill and no stroke), else the kind's name.
    public let type: String
    public let parentID: String?
    /// Position in the parent's stacking order, 0 = back.
    public let zIndex: Int?
    public let x: Double?
    public let y: Double?
    public let width: Double?
    public let height: Double?
    public let angle: Double?
    public let text: String?
    public let fill: FreeformColor?
    public let stroke: FreeformColor?
    public let url: String?
    public let fileName: String?
    public let connectedFrom: String?
    public let connectedTo: String?
    public let locked: Bool
}

/// Read-only access to Freeform's boards. The live store is never opened: each read copies the
/// database (and its WAL/SHM files) into a fresh temporary directory, reads the copy with SQLite,
/// decodes the copied blobs with Freeform's own model types (`FreeformModelRuntime`) and deletes
/// the directory before returning.
public final class FreeformStore: @unchecked Sendable {
    public let home: URL
    private let fileManager = FileManager.default
    private let decoderFactory: () throws -> FreeformRecordDecoding

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        decoder: @escaping () throws -> FreeformRecordDecoding = { try FreeformModelRuntime.load() }
    ) {
        self.home = home
        decoderFactory = decoder
    }

    public var groupContainer: URL {
        home.appendingPathComponent("Library/Group Containers/group.com.apple.freeform", isDirectory: true)
    }

    public var legacyDatabase: URL {
        home.appendingPathComponent("Library/Containers/com.apple.freeform/Data/Library/Freeform/Boards/boards.db")
    }

    /// Whether the group container's contents can be listed (Full Disk Access when protected).
    public func groupContainerReadable() -> Bool {
        (try? fileManager.contentsOfDirectory(atPath: groupContainer.path)) != nil
    }

    /// The current store if present, else the legacy one. Nil when neither exists.
    public func locate() throws -> FreeformStoreLocation? {
        if fileManager.fileExists(atPath: groupContainer.path) {
            guard groupContainerReadable() else {
                throw AgentError(
                    code: "permission_denied", message: "Freeform's data folder is protected and not readable.",
                    hint:
                        "Give the app that runs freeform-cli Full Disk Access (System Settings > Privacy & Security), then restart it."
                )
            }
            let database = groupContainer.appendingPathComponent("Boards/boards.db")
            if fileManager.fileExists(atPath: database.path) {
                return FreeformStoreLocation(kind: .groupContainer, database: database)
            }
        }
        if fileManager.fileExists(atPath: legacyDatabase.path) {
            return FreeformStoreLocation(kind: .legacyContainer, database: legacyDatabase)
        }
        return nil
    }

    /// The located store, or `not_found`.
    public func requireLocation() throws -> FreeformStoreLocation {
        guard let location = try locate() else {
            throw AgentError(
                code: "not_found", message: "No Freeform board store was found.",
                hint: "Open Freeform once to create it, then run doctor.")
        }
        return location
    }

    /// Runs `body` on a private copy of the store.
    public func withSnapshot<T>(_ location: FreeformStoreLocation, _ body: (FreeformSnapshot) throws -> T) throws -> T {
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "gesher-freeform-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("boards.db")
        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: location.database.path + suffix)
                guard suffix.isEmpty || fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
            }
        } catch {
            throw AgentError(
                code: "permission_denied",
                message: "Could not copy Freeform's board database: \(error.localizedDescription)",
                hint: "Give the app that runs freeform-cli Full Disk Access, then restart it.")
        }
        return try body(FreeformSnapshot(try SQLiteSnapshot(copy), decoder: try decoderFactory()))
    }

    public func boards(at location: FreeformStoreLocation, includeDeleted: Bool) throws -> [FreeformBoardSnapshot] {
        try withSnapshot(location) { try $0.boards(includeDeleted: includeDeleted) }
    }
}

/// Board, folder and item reads over one private copy of the store.
public final class FreeformSnapshot {
    let db: SQLiteSnapshot
    let decoder: FreeformRecordDecoding

    init(_ db: SQLiteSnapshot, decoder: FreeformRecordDecoding) {
        self.db = db
        self.decoder = decoder
    }

    public func folders() -> [FreeformFolderSnapshot] {
        let columns = db.columns("folders")
        guard columns.isSuperset(of: ["identifier", "data"]) else { return [] }
        func column(_ name: String) -> String { columns.contains(name) ? name : "NULL" }
        let rows = db.rows(
            "SELECT identifier, data, \(column("title")), \(column("parent_identifier")), \(column("tombstone")) FROM folders"
        )
        return rows.compactMap { row in
            guard let id = row[0] as? Data else { return nil }
            let data = (row[1] as? Data).flatMap { decoder.decode(.folder, $0) }
            return FreeformFolderSnapshot(
                id: SQLiteSnapshot.identifier(id), title: data?["title"]?.string ?? (row[2] as? String),
                parentID: (row[3] as? Data).map(SQLiteSnapshot.identifier), deleted: (row[4] as? Int64 ?? 0) != 0)
        }
    }

    public func boards(includeDeleted: Bool) throws -> [FreeformBoardSnapshot] {
        let boardColumns = db.columns("boards")
        guard boardColumns.isSuperset(of: ["board_identifier", "data"]) else {
            throw PlatformError.unsupportedPrivateAPI(
                selector: "boards", reason: "This Freeform version uses an unknown board table layout.")
        }
        func column(_ name: String) -> String { boardColumns.contains(name) ? "b.\(name)" : "NULL" }
        let favorite = db.columns("boards_metadata").contains("is_favorite") ? "m.is_favorite" : "NULL"
        let folders = Dictionary(folders().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let counts =
            db.columns("board_items").isSuperset(of: ["board_identifier", "tombstoned", "parent_uuid"])
            ? "(SELECT count(*) FROM board_items i WHERE i.board_identifier = b.board_identifier AND i.tombstoned = 0 AND i.parent_uuid IS NOT NULL)"
            : "0"
        let query = """
            SELECT b.board_identifier, b.data, \(column("last_activity_time")), \(column("tombstoned")),
                   \(column("tombstone_date")), \(column("hide_from_recently_deleted")), \(column("parent_identifier")),
                   \(favorite), \(column("ckshare_data")), \(column("owner_name")), \(counts)
            FROM boards b LEFT JOIN boards_metadata m ON m.board_identifier = b.board_identifier
            """
        return db.rows(query).compactMap { row -> FreeformBoardSnapshot? in
            guard let identifier = row[0] as? Data else { return nil }
            let deleted = (row[3] as? Int64 ?? 0) != 0
            let purged = (row[5] as? Int64 ?? 0) != 0
            if deleted && (purged || !includeDeleted) { return nil }
            let data = (row[1] as? Data).flatMap { decoder.decode(.board, $0) }
            let folderID = (row[6] as? Data).map(SQLiteSnapshot.identifier)
            let lastActivity =
                (row[2] as? Double).flatMap(SQLiteSnapshot.date)
                ?? data?["boardMetadata.lastActivityTime"]?.double.flatMap(SQLiteSnapshot.date)
            let shared = row[8] is Data
            let owner = (row[9] as? String).map { !$0.isEmpty && $0 != "__defaultOwner__" } ?? false
            return FreeformBoardSnapshot(
                id: SQLiteSnapshot.identifier(identifier),
                title: data?["title"]?.string, favorite: (row[7] as? Int64 ?? 0) != 0,
                folderID: folderID, folder: folderID.flatMap { folders[$0]?.title }, deleted: deleted,
                deletedAt: deleted ? (row[4] as? Double).flatMap(SQLiteSnapshot.date) : nil,
                createdAt: data?["boardMetadata.creationTime"]?.double.flatMap(SQLiteSnapshot.date),
                lastActivityAt: lastActivity,
                sharing: owner ? .participant : shared ? .owner : nil,
                rootContainerID: data?["rootContainerAffinity.rootContainerUUID"]?.uuid?.uuidString,
                itemCount: Int(row[10] as? Int64 ?? 0),
                revision: boardRevision(
                    boardID: identifier, boardData: row[1] as? Data, favorite: (row[7] as? Int64 ?? 0) != 0,
                    deleted: deleted))
        }.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
    }

    private func boardRevision(boardID: Data, boardData: Data?, favorite: Bool, deleted: Bool) -> String {
        var hasher = SHA256()
        hasher.update(data: boardID)
        if let boardData { hasher.update(data: boardData) }
        hasher.update(data: Data([favorite ? 1 : 0, deleted ? 1 : 0]))
        let itemRows = db.rows(
            "SELECT item_uuid, parent_uuid, item_type, common_data, specific_data FROM board_items WHERE board_identifier = ? AND tombstoned = 0 ORDER BY item_uuid",
            blob: boardID)
        for row in itemRows {
            if let id = row[0] as? Data { hasher.update(data: id) }
            if let parent = row[1] as? Data { hasher.update(data: parent) }
            if let kind = row[2] as? Int64 {
                var little = kind.littleEndian
                hasher.update(data: Data(bytes: &little, count: MemoryLayout<Int64>.size))
            }
            if let common = row[3] as? Data { hasher.update(data: common) }
            if let specific = row[4] as? Data { hasher.update(data: specific) }
        }
        let digest = hasher.finalize()
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The live (not deleted) items of a board, in stacking order within each parent.
    public func items(board: FreeformBoardSnapshot) -> [FreeformItemSnapshot] {
        itemsReport(board: board).items
    }

    /// The live items of a board together with counts of unrecognized or partially decoded rows.
    public func itemsReport(board: FreeformBoardSnapshot) -> FreeformItemsReport {
        guard let boardID = UUID(uuidString: board.id) else {
            return FreeformItemsReport(items: [], unsupportedCount: 0, partialDecodeCount: 0)
        }
        let rows = db.rows(
            "SELECT item_uuid, parent_uuid, item_type, common_data, specific_data FROM board_items WHERE board_identifier = ? AND tombstoned = 0",
            blob: SQLiteSnapshot.blob(boardID))
        struct Row {
            let id: String
            let parent: String?
            let kind: FreeformItemKind?
            let common: Reflected?
            let specific: Reflected?
        }
        let decoded: [Row] = rows.compactMap { row in
            guard let id = row[0] as? Data else { return nil }
            let kind = (row[2] as? Int64).flatMap { FreeformItemKind(rawValue: Int($0)) }
            return Row(
                id: SQLiteSnapshot.identifier(id), parent: (row[1] as? Data).map(SQLiteSnapshot.identifier), kind: kind,
                common: kind.flatMap { kind in (row[3] as? Data).flatMap { decoder.decode(.itemCommon(kind), $0) } },
                specific: kind.flatMap { kind in (row[4] as? Data).flatMap { decoder.decode(.itemSpecific(kind), $0) } }
            )
        }
        // Stacking order: each container lists its children back to front.
        var order: [String: Int] = [:]
        for row in decoded where row.kind == .group || row.kind == .drawing || row.kind == .surface {
            for (index, child) in (row.specific?["items"]?.elements ?? []).enumerated() {
                if let id = child.uuid?.uuidString { order[id] = index }
            }
        }
        let byID = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Only items reachable from the board's canvas root (the alternate root holds no canvas items).
        func onCanvas(_ row: Row) -> Bool {
            var parent = row.parent
            var depth = 0
            while let current = parent, depth < 64 {
                if current == board.rootContainerID { return true }
                parent = byID[current]?.parent
                depth += 1
            }
            return board.rootContainerID == nil && row.parent != nil
        }
        let canvasRows = decoded.filter { $0.parent != nil && onCanvas($0) }
        var unsupportedCount = 0
        var partialDecodeCount = 0
        var items: [FreeformItemSnapshot] = []
        for row in canvasRows {
            guard let kind = row.kind else {
                unsupportedCount += 1
                continue
            }
            if row.common == nil || row.specific == nil { partialDecodeCount += 1 }
            items.append(
                Self.item(
                    row.id, kind: kind, parent: row.parent, root: board.rootContainerID,
                    zIndex: order[row.id], common: row.common, specific: row.specific))
        }
        items.sort { ($0.parentID ?? "", $0.zIndex ?? 0, $0.id) < ($1.parentID ?? "", $1.zIndex ?? 0, $1.id) }
        return FreeformItemsReport(
            items: items, unsupportedCount: unsupportedCount, partialDecodeCount: partialDecodeCount)
    }

    static func item(
        _ id: String, kind: FreeformItemKind, parent: String?, root: String?, zIndex: Int?, common: Reflected?,
        specific: Reflected?
    ) -> FreeformItemSnapshot {
        let geometry = common?.first("parentAffinity.superParentAffinity.geometry", "parentAffinity.geometry")
        let shapeStyle = specific?.first(
            "superData.superData.shapeStyleData", "superData.shapeStyleData", "shapeStyleData")
        let fill = color(shapeStyle?["fill.color"])
        let stroke = color(shapeStyle?["stroke.color"])
        let text = specific?.first("superData.textStorageCRDTData.text", "textStorageCRDTData.text")?.text
            .map { $0.hasSuffix("\n") ? String($0.dropLast()) : $0 }
        var type = String(describing: kind)
        if kind == .shape, fill == nil, stroke == nil { type = "text" }
        if kind == .model3D { type = "model3d" }
        let width = (geometry?["widthValid"]?.bool ?? true) ? geometry?["size.width"]?.double : nil
        let height = (geometry?["heightValid"]?.bool ?? true) ? geometry?["size.height"]?.double : nil
        let fileName = specific?.first(
            "atomicData.fileAssetData.filename", "assets.imageData.filename", "assets.movieData.filename")?.string
        return FreeformItemSnapshot(
            id: id, kind: kind, type: type, parentID: parent == root ? nil : parent, zIndex: zIndex,
            x: geometry?["position.x"]?.double, y: geometry?["position.y"]?.double, width: width, height: height,
            angle: geometry?["angle"]?.double, text: text?.isEmpty == true ? nil : text, fill: fill, stroke: stroke,
            url: specific?["atomicData.url"]?.url?.absoluteString, fileName: fileName,
            connectedFrom: specific?["connectedFrom"]?.uuid?.uuidString,
            connectedTo: specific?["connectedTo"]?.uuid?.uuidString, locked: common?["locked"]?.bool ?? false)
    }

    /// `TSUColorData`: an RGB, monochrome or CMYK model plus an optional alpha.
    static func color(_ value: Reflected?) -> FreeformColor? {
        guard let value else { return nil }
        let alpha = value["alpha"]?.double ?? 1
        if let rgb = value["rgbData"], let red = rgb["red"]?.double, let green = rgb["green"]?.double,
            let blue = rgb["blue"]?.double
        {
            return FreeformColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        if let white = value.first("monochromeData.white", "monochromeData.gray")?.double {
            return FreeformColor(red: white, green: white, blue: white, alpha: alpha)
        }
        if let cmyk = value["cmykData"], let c = cmyk["cyan"]?.double, let m = cmyk["magenta"]?.double,
            let y = cmyk["yellow"]?.double, let k = cmyk["black"]?.double
        {
            return FreeformColor(
                red: (1 - c) * (1 - k), green: (1 - m) * (1 - k), blue: (1 - y) * (1 - k), alpha: alpha)
        }
        return nil
    }
}

/// One SQLite connection to a private copy of the store. Opened read-write only so SQLite can
/// apply the copied WAL to the copy; the live store is never touched.
final class SQLiteSnapshot {
    private var db: OpaquePointer?

    init(_ url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw PlatformError.fetchFailed("Could not open the copied Freeform database.")
        }
    }

    deinit { sqlite3_close(db) }

    func columns(_ table: String) -> Set<String> {
        Set(rows("PRAGMA table_info(\(table))").compactMap { $0[1] as? String })
    }

    /// 16-byte identifiers as UUID strings; other lengths as hex.
    static func identifier(_ data: Data) -> String {
        if data.count == 16 {
            let uuid = data.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }
            return UUID(uuid: uuid).uuidString
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    static func blob(_ uuid: UUID) -> Data { withUnsafeBytes(of: uuid.uuid) { Data($0) } }

    /// Store times are seconds since 2001-01-01; zero means unset.
    static func date(_ seconds: Double) -> Date? {
        seconds.isFinite && seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
    }

    func rows(_ sql: String, blob: Data? = nil) -> [[Any?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if let blob {
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(blob.count), transient) }
        }
        var result: [[Any?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                (0..<sqlite3_column_count(statement)).map { index -> Any? in
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER: return sqlite3_column_int64(statement, index)
                    case SQLITE_FLOAT: return sqlite3_column_double(statement, index)
                    case SQLITE_TEXT: return sqlite3_column_text(statement, index).map { String(cString: $0) }
                    case SQLITE_BLOB:
                        guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
                        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
                    default: return nil
                    }
                })
        }
        return result
    }
}
