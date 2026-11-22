import GesherPlatform
import Foundation
import FreeformCore

struct BoardsOutput: Encodable, Sendable {
    let store: String
    let boards: [Board]
}

struct Board: Encodable, Sendable {
    let id: String
    let title: String?
    let favorite: Bool
    let folder: String?
    /// `owner` (you shared it) or `participant` (shared with you); absent when not shared.
    let shared: String?
    let items: Int
    let revision: String?
    let deleted: Bool?
    let deletedAt: String?
    let createdAt: String?
    let lastActivityAt: String?
    let dotGrid: Bool?
    let connectorMode: Bool?

    init(_ board: FreeformBoardSnapshot) {
        id = board.id
        title = board.title
        favorite = board.favorite
        folder = board.folder ?? board.folderID
        shared = board.sharing?.rawValue
        items = board.itemCount
        revision = board.revision
        deleted = board.deleted ? true : nil
        deletedAt = board.deletedAt.map { DateOutput.iso($0) }
        createdAt = board.createdAt.map { DateOutput.iso($0) }
        lastActivityAt = board.lastActivityAt.map { DateOutput.iso($0) }
        dotGrid = board.dotGrid
        connectorMode = board.connectorMode
    }
}

struct Item: Encodable, Sendable {
    let id: String
    /// text, shape, sticky, connector, image, file, link, table, drawing, movie, model3d, group, ...
    let type: String
    /// The group containing the item; absent for items directly on the canvas.
    let group: String?
    /// Stacking order within its parent, 0 = back.
    let z: Int?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let angle: Double?
    let text: String?
    let fill: String?
    let stroke: String?
    let url: String?
    let file: String?
    let from: String?
    let to: String?
    let locked: Bool?
    let description: String?

    init(_ item: FreeformItemSnapshot) {
        func round(_ value: Double?) -> Double? { value.map { ($0 * 10).rounded() / 10 } }
        id = item.id
        type = item.type
        group = item.parentID
        z = item.zIndex
        x = round(item.x)
        y = round(item.y)
        width = round(item.width)
        height = round(item.height)
        angle = item.angle.flatMap { abs($0) < 0.05 ? nil : round($0) }
        text = item.text
        fill = item.fill?.hex
        stroke = item.stroke?.hex
        url = item.url
        file = item.fileName
        from = item.connectedFrom
        to = item.connectedTo
        locked = item.locked ? true : nil
        description = item.accessibilityDescription
    }
}

struct BoardDetailOutput: Encodable, Sendable {
    let board: Board
    /// Item count per type.
    let types: [String: Int]
    let coordinateSystem: String
    let unsupportedItems: Int?
    let partiallyDecodedItems: Int?
}

struct ItemsOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let total: Int
    let offset: Int?
    let more: Int?
    let unsupportedItems: Int?
    let partiallyDecodedItems: Int?
    let items: [Item]
}

struct CreateBoardOutput: Encodable, Sendable {
    let board: Board
    let items: [Item]
    /// Content Freeform has not placed on the board yet (still importing or rejected).
    let pending: Int?
    let sync: String?
}

struct AddItemsOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let added: [Item]
    let pending: Int?
}

struct BoardMutationOutput: Encodable, Sendable {
    let board: Board
    let sync: String
}

struct ItemMutationOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let item: Item
    let sync: String
}

struct ItemsMutationOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let items: [Item]
    let sync: String
}

struct DeleteItemsOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let deleted: [String]
    let affectedConnectors: [Item]?
    let sync: String
}

struct DiagramOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let nodes: [String: Item]
    let edges: [Item]
    let sync: String
}

struct ExportOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let format: String
    let path: String
    let bytes: Int
}

struct Folder: Encodable, Sendable {
    let id: String
    let title: String?
    let parent: String?
    let deleted: Bool?

    init(_ folder: FreeformFolderSnapshot) {
        id = folder.id
        title = folder.title
        parent = folder.parentID
        deleted = folder.deleted ? true : nil
    }
}

struct FoldersOutput: Encodable, Sendable {
    let folders: [Folder]
}

struct SceneOutput: Encodable, Sendable {
    let id: String
    let name: String?
    let index: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ scene: FreeformSceneSnapshot) {
        func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        id = scene.id
        name = scene.name
        index = scene.index
        x = r(scene.x)
        y = r(scene.y)
        width = r(scene.width)
        height = r(scene.height)
    }
}

struct ScenesOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let scenes: [SceneOutput]
}

struct SceneMutationOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let scene: SceneOutput
    let sync: String
}

struct DeleteSceneOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let deletedScene: String
    let sync: String
}

struct TableData: Encodable, Sendable {
    let id: String
    let rows: Int
    let columns: Int
    let rtl: Bool
    let cells: [[String]]

    init(_ snapshot: FreeformTableSnapshot) {
        id = snapshot.id
        rows = snapshot.rows
        columns = snapshot.columns
        rtl = snapshot.rtl
        cells = snapshot.cells
    }
}

struct TableOutput: Encodable, Sendable {
    let board: String
    let title: String?
    let revision: String?
    let table: TableData
    let sync: String?
}

struct SyncOutput: Encodable, Sendable {
    let launched: Bool
    let running: Bool
    let hidden: Bool
    let status: String
}
