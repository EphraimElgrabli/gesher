import Foundation
import FreeformCore
import GesherKit
import GesherPlatform

enum ExportBoard: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var output: String
        var kind: String
    }

    static let path = ["boards", "export"]
    static let summary =
        "Export a Freeform board to vector PDF or PNG using Freeform's native canvas renderer (works even while Freeform is open)."
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        .string("output", "Destination file path (e.g. ~/Desktop/board.pdf).", required: true),
        .choice(
            "kind", FreeformExportFormat.allCases.map(\.rawValue), "Export file kind: pdf or png. Default: pdf.",
            default: "pdf"),
    ]
    static let examples = [
        "boards export 'Architecture' --output /tmp/architecture.pdf --kind pdf",
        "boards export 'Architecture' --output /tmp/architecture.png --kind png",
    ]

    static func validate(_ input: Input) throws {
        guard !input.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalid("Output path is empty.")
        }
        _ = try FreeformExportFormat.parse(input.kind)
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> ExportOutput {
        let format = try FreeformExportFormat.parse(input.kind)
        let result = try context.writer.exportBoard(board: input.board, format: format, outputPath: input.output)
        return ExportOutput(
            board: result.board.id, title: result.board.title, format: result.format.rawValue,
            path: result.path, bytes: result.bytes)
    }
}

enum ListFolders: AgentOperation {
    struct Input: Decodable, Sendable {
        var includeDeleted: Bool
    }

    static let path = ["folders", "list"]
    static let summary = "List Freeform folders (id, title, parent folder, deleted state)."
    static let params: [Param] = [
        .boolean("includeDeleted", "Also include deleted folders.")
    ]
    static let examples = ["folders list", "folders list --include-deleted"]

    static func run(_ input: Input, _ context: FreeformContext) throws -> FoldersOutput {
        try context.snapshot { snapshot in
            let folders = snapshot.folders().filter { input.includeDeleted || !$0.deleted }
            return FoldersOutput(folders: folders.map(Folder.init))
        }
    }
}

enum ListScenes: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
    }

    static let path = ["scenes", "list"]
    static let summary = "List scenes (named canvas regions for presenting/navigating) on a board."
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true)
    ]
    static let examples = ["scenes list 'Architecture'"]

    static func run(_ input: Input, _ context: FreeformContext) throws -> ScenesOutput {
        let result = try context.writer.listScenes(board: input.board)
        return ScenesOutput(
            board: result.board.id, title: result.board.title, revision: result.board.revision,
            scenes: result.scenes.map(SceneOutput.init))
    }
}

enum CreateScene: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var name: String?
        var x: Double?
        var y: Double?
        var width: Double?
        var height: Double?
        var ifRevision: String?
    }

    static let path = ["scenes", "create"]
    static let summary = "Create a named scene (saved canvas viewport rect) on a board."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        .string("name", "Optional scene title."),
        .number("x", "Scene X origin in points. Default: 0."),
        .number("y", "Scene Y origin in points. Default: 0."),
        .number("width", "Scene width in points. Default: 1200.", min: 1),
        .number("height", "Scene height in points. Default: 800.", min: 1),
        .string("ifRevision", "Only save if the board still matches this revision."),
    ]
    static let examples = ["scenes create 'Architecture' --name 'Overview' --x 0 --y 0 --width 1200 --height 800"]

    static func run(_ input: Input, _ context: FreeformContext) throws -> SceneMutationOutput {
        let result = try context.writer.createScene(
            board: input.board, name: input.name, x: input.x ?? 0, y: input.y ?? 0,
            width: input.width ?? 1200, height: input.height ?? 800, ifRevision: input.ifRevision)
        return SceneMutationOutput(
            board: result.board.id, title: result.board.title, revision: result.board.revision,
            scene: SceneOutput(result.scene), sync: "pending_until_app_launch")
    }
}

enum UpdateScene: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var scene: String
        var name: String?
        var x: Double?
        var y: Double?
        var width: Double?
        var height: Double?
        var ifRevision: String?
    }

    static let path = ["scenes", "update"]
    static let summary = "Rename a scene or update its saved canvas rectangle."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        .string("scene", "Scene UUID to update.", required: true),
        .string("name", "New scene title."),
        .number("x", "New scene X origin in points."),
        .number("y", "New scene Y origin in points."),
        .number("width", "New scene width in points.", min: 1),
        .number("height", "New scene height in points.", min: 1),
        .string("ifRevision", "Only save if the board still matches this revision."),
    ]
    static let examples = [
        "scenes update 'Architecture' --scene 00000000-0000-0000-0000-000000000001 --name 'Backend'"
    ]

    static func validate(_ input: Input) throws {
        guard UUID(uuidString: input.scene) != nil else {
            throw AgentError.invalid("Invalid scene UUID '\(input.scene)'.")
        }
        guard input.name != nil || input.x != nil || input.y != nil || input.width != nil || input.height != nil else {
            throw AgentError.invalid("Specify --name or geometry (--x/--y/--width/--height) to update.")
        }
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> SceneMutationOutput {
        let result = try context.writer.updateScene(
            board: input.board, sceneID: input.scene, name: input.name, x: input.x, y: input.y,
            width: input.width, height: input.height, ifRevision: input.ifRevision)
        return SceneMutationOutput(
            board: result.board.id, title: result.board.title, revision: result.board.revision,
            scene: SceneOutput(result.scene), sync: "pending_until_app_launch")
    }
}

enum DeleteScene: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var scene: String
        var ifRevision: String?
    }

    static let path = ["scenes", "delete"]
    static let summary = "Delete a scene from a board."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        .string("scene", "Scene UUID to delete.", required: true),
        .string("ifRevision", "Only delete if the board still matches this revision."),
    ]
    static let examples = [
        "scenes delete 'Architecture' --scene 00000000-0000-0000-0000-000000000001"
    ]

    static func validate(_ input: Input) throws {
        guard UUID(uuidString: input.scene) != nil else {
            throw AgentError.invalid("Invalid scene UUID '\(input.scene)'.")
        }
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> DeleteSceneOutput {
        let result = try context.writer.deleteScene(
            board: input.board, sceneID: input.scene, ifRevision: input.ifRevision)
        return DeleteSceneOutput(
            board: result.board.id, title: result.board.title, revision: result.board.revision,
            deletedScene: input.scene, sync: "pending_until_app_launch")
    }
}

enum SetBoardAppearance: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var dotGrid: Bool?
        var connectorMode: Bool?
    }

    static let path = ["boards", "appearance"]
    static let summary = "Configure a board's persistent canvas dot grid and connector-mode settings."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        Param("dotGrid", .boolean, "Show (true) or hide (false) the canvas dot grid."),
        Param("connectorMode", .boolean, "Enable (true) or disable (false) connector mode."),
    ]
    static let examples = [
        "boards appearance 'Architecture' --dot-grid false --connector-mode true"
    ]

    static func validate(_ input: Input) throws {
        guard input.dotGrid != nil || input.connectorMode != nil else {
            throw AgentError.invalid("Specify --dot-grid and/or --connector-mode.")
        }
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> BoardMutationOutput {
        let result = try context.writer.setBoardAppearance(
            selector: input.board, dotGrid: input.dotGrid, connectorMode: input.connectorMode)
        return BoardMutationOutput(board: Board(result.board), sync: "pending_until_app_launch")
    }
}

enum SyncBoards: AgentOperation {
    static let path = ["boards", "sync"]
    static let summary =
        "Quietly launch Freeform hidden in the background so pending local edits sync to iCloud without interrupting windows."
    static let effect = OperationEffect.write
    static let params: [Param] = []
    static let examples = ["boards sync"]

    static func run(_ input: NoInput, _ context: FreeformContext) throws -> SyncOutput {
        let wasRunning = FreeformImporter.isAppRunning
        if !wasRunning {
            try context.launchApp()
        }
        return SyncOutput(
            launched: !wasRunning, running: true, hidden: !wasRunning,
            status: wasRunning ? "already_running" : "launched_hidden_for_sync")
    }
}
