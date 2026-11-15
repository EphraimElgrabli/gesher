import GesherKit
import GesherPlatform
import Foundation
import FreeformCore

enum ListBoards: AgentOperation {
    struct Input: Decodable, Sendable {
        var includeDeleted: Bool
        var favorites: Bool
    }

    static let path = ["boards", "list"]
    static let summary =
        "List Freeform boards (title, favorite, folder, sharing, item count, dates), most recent first."
    static let params: [Param] = [
        .boolean("includeDeleted", "Also list boards in Recently Deleted."),
        .boolean("favorites", "Only favorite boards."),
    ]
    static let examples = ["boards list", "boards list --include-deleted", "boards list --favorites"]

    static func run(_ input: Input, _ context: FreeformContext) throws -> BoardsOutput {
        let location = try context.store.requireLocation()
        let boards = try context.store.boards(at: location, includeDeleted: input.includeDeleted)
            .filter { !input.favorites || $0.favorite }
        return BoardsOutput(store: location.kind.rawValue, boards: boards.map(Board.init))
    }
}

enum GetBoard: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
    }

    static let path = ["boards", "get"]
    static let summary = "One board's details and how many items of each type it holds."
    static let params: [Param] = [
        .string("board", "Board title or id (Recently Deleted boards included).", required: true, positional: true)
    ]
    static let examples = ["boards get 'Trip ideas'"]

    static func run(_ input: Input, _ context: FreeformContext) throws -> BoardDetailOutput {
        try context.snapshot { snapshot in
            let board = try context.board(input.board, in: snapshot, includeDeleted: true)
            let types = Dictionary(snapshot.items(board: board).map { ($0.type, 1) }, uniquingKeysWith: +)
            return BoardDetailOutput(board: Board(board), types: types)
        }
    }
}

/// Creates a board through Freeform itself (its import inbox), optionally with initial content.
enum CreateBoard: AgentOperation {
    struct Input: Decodable, Sendable {
        var title: String
        var folder: String?
        var text: [String]?
        var url: [String]?
        var file: [String]?
    }

    static let path = ["boards", "create"]
    static let summary =
        "Create a board, optionally with text boxes, links, images or files; Freeform places and syncs them."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("title", "Title of the new board.", required: true, positional: true),
        .string("folder", "Folder to create it in (name or id). Default: no folder."),
        .list("text", "Text boxes to add."),
        .list("url", "Links to add (http or https)."),
        .list("file", "Local images, PDFs or other files to add (paths). Hidden, system and key files are refused."),
    ]
    static let examples = [
        "boards create 'Trip ideas'", "boards create 'Trip ideas' --text 'Flights' --url https://www.apple.com",
    ]

    static func validate(_ input: Input) throws {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalid("The board title is empty.")
        }
        _ = try ImportContent.parse(text: input.text, url: input.url, file: input.file)
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> CreateBoardOutput {
        let contents = try ImportContent.parse(text: input.text, url: input.url, file: input.file)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let (existing, folder) = try context.snapshot { snapshot -> (Set<String>, FreeformFolderSnapshot?) in
            let folder = try input.folder.map { selector in
                try EntityResolver.resolve(
                    selector, in: snapshot.folders().filter { !$0.deleted }, type: "folder", id: \.id,
                    name: { $0.title ?? "" })
            }
            return (Set(try snapshot.boards(includeDeleted: true).map(\.id)), folder)
        }
        let importID = try context.importer.submit(
            board: nil, title: title, folder: folder.flatMap { UUID(uuidString: $0.id) }, contents: contents)
        try context.launchApp()
        var latest: (FreeformBoardSnapshot, [FreeformItemSnapshot])?
        _ = try FreeformImporter.wait(timeout: context.importTimeout) { () -> Bool? in
            latest = try context.snapshot { snapshot in
                try snapshot.boards(includeDeleted: false)
                    .first { !existing.contains($0.id) && $0.title == title }
                    .map { ($0, snapshot.items(board: $0)) }
            }
            guard let (_, items) = latest else { return nil }
            return items.count >= contents.count ? true : nil
        }
        guard let (board, items) = latest else {
            throw PlatformError.mutationUnverified(
                type: "board", id: importID.uuidString,
                reason: context.importer.isPending(importID)
                    ? "Freeform has not imported the new board yet (it does when it runs). Check boards list before retrying."
                    : "Freeform took the import but no new board titled '\(title)' appeared. Check boards list before retrying."
            )
        }
        let pending = contents.count - items.count
        return CreateBoardOutput(board: Board(board), items: items.map(Item.init), pending: pending > 0 ? pending : nil)
    }
}

extension FreeformImportContent {
    var isFile: Bool {
        if case .file = self { return true }
        return false
    }
}

/// Text, link and file content for an import, validated before any context is created.
enum ImportContent {
    static func parse(text: [String]?, url: [String]?, file: [String]?) throws -> [FreeformImportContent] {
        var contents: [FreeformImportContent] = []
        for value in text ?? [] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentError.invalid("A text item is empty.")
            }
            contents.append(.text(value))
        }
        for value in url ?? [] {
            guard let link = URL(string: value.trimmingCharacters(in: .whitespaces)),
                let scheme = link.scheme?.lowercased(), ["http", "https"].contains(scheme), link.host != nil
            else {
                throw AgentError.invalid(
                    "'\(value)' is not an http(s) link.", hint: "Pass local files with --file instead.")
            }
            contents.append(.link(link, title: nil))
        }
        for value in file ?? [] {
            contents.append(.file(try LocalFilePolicy.attachable(value)))
        }
        return contents
    }
}
