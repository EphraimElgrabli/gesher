import GesherKit
import GesherPlatform
import Foundation
import FreeformCore

enum ListItems: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var type: String?
    }

    static let path = ["items", "list"]
    static let summary =
        "A board's items: type, text, position, size, colors, link or file name, connector ends, stacking order."
    static let params: [Param] = [
        .string("board", "Board title or id (Recently Deleted boards included).", required: true, positional: true),
        .choice(
            "type",
            ["text", "shape", "sticky", "connector", "image", "file", "link", "table", "drawing", "movie", "group"],
            "Only items of this type."),
    ]
    static let examples = ["items list 'Trip ideas'", "items list 'Trip ideas' --type sticky"]

    static func run(_ input: Input, _ context: FreeformContext) throws -> ItemsOutput {
        try context.snapshot { snapshot in
            let board = try context.board(input.board, in: snapshot, includeDeleted: true)
            let items = snapshot.items(board: board).filter { input.type == nil || $0.type == input.type }
            return ItemsOutput(board: board.id, title: board.title, items: items.map(Item.init))
        }
    }

    static func pretty(_ output: ItemsOutput) -> String? {
        let lines = output.items.map { item -> String in
            var line = "\(item.type) \(item.id)"
            if let x = item.x, let y = item.y { line += " at \(x),\(y)" }
            if let width = item.width, let height = item.height { line += " \(width)x\(height)" }
            if let text = item.text ?? item.url ?? item.file {
                line += ": " + text.replacingOccurrences(of: "\n", with: " ")
            }
            return line
        }
        return ([output.title ?? output.board] + lines).joined(separator: "\n")
    }
}

/// Adds content to an existing board through Freeform itself (its import inbox).
enum AddItems: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var text: [String]?
        var url: [String]?
        var file: [String]?
        var confirmShared: Bool
    }

    static let path = ["items", "add"]
    static let summary = "Add text boxes, links, images or files to a board; Freeform places and syncs them."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        .list("text", "Text boxes to add."),
        .list("url", "Links to add (http or https)."),
        .list("file", "Local images, PDFs or other files to add (paths). Hidden, system and key files are refused."),
        .boolean(
            "confirmShared",
            "The user confirmed adding files to a board shared with other people (they will see them)."),
    ]
    static let examples = [
        "items add 'Trip ideas' --text 'Book flights'", "items add 'Trip ideas' --url https://www.apple.com",
        "items add 'Trip ideas' --file ~/Pictures/map.png",
    ]

    static func validate(_ input: Input) throws {
        guard try !ImportContent.parse(text: input.text, url: input.url, file: input.file).isEmpty else {
            throw AgentError.invalid("Nothing to add.", hint: "Pass --text, --url or --file.")
        }
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> AddItemsOutput {
        let contents = try ImportContent.parse(text: input.text, url: input.url, file: input.file)
        let (board, before) = try context.snapshot { snapshot in
            let board = try context.board(input.board, in: snapshot)
            return (board, Set(snapshot.items(board: board).map(\.id)))
        }
        guard board.sharing != .participant else {
            throw AgentError(
                code: "read_only",
                message: "'\(board.title ?? board.id)' is shared with you; Freeform may refuse edits.",
                hint: "Add content to a board you own.")
        }
        if board.sharing == .owner, !input.confirmShared, contents.contains(where: \.isFile) {
            throw AgentError(
                code: "confirmation_required",
                message: "'\(board.title ?? board.id)' is shared; files added to it reach everyone on the board.",
                hint:
                    "Ask the user whether to share these files with the board's participants, then retry with confirmShared."
            )
        }
        guard let boardID = UUID(uuidString: board.id) else { throw AgentError.notFound("board", board.id) }
        let importID = try context.importer.submit(
            board: boardID, title: board.title ?? "", folder: nil, contents: contents)
        try context.launchApp()
        var added: [FreeformItemSnapshot] = []
        _ = try FreeformImporter.wait(timeout: context.importTimeout) { () -> Bool? in
            added = try context.snapshot { snapshot in
                guard let current = try snapshot.boards(includeDeleted: false).first(where: { $0.id == board.id })
                else { return [] }
                return snapshot.items(board: current).filter { !before.contains($0.id) }
            }
            return added.count >= contents.count ? true : nil
        }
        guard !added.isEmpty else {
            throw PlatformError.mutationUnverified(
                type: "board", id: board.id,
                reason: context.importer.isPending(importID)
                    ? "Freeform has not imported the content yet (it does when it runs). Check items list before retrying."
                    : "Freeform took the import but no new items appeared. Check items list before retrying.")
        }
        let pending = contents.count - added.count
        return AddItemsOutput(
            board: board.id, title: board.title, added: added.map(Item.init), pending: pending > 0 ? pending : nil)
    }
}

/// Finds text across every board: board titles and the text, links and file names of items.
/// Matching ignores case, accents, Hebrew niqqud and punctuation; every query word must appear.
enum SearchBoards: AgentOperation {
    struct Input: Decodable, Sendable {
        var query: String
        var type: String?
        var includeDeleted: Bool
        var limit: Int
    }

    struct Match: Encodable, Sendable {
        let board: String
        let title: String?
        let item: Item
    }

    struct Output: Encodable, Sendable {
        /// Boards whose title matches.
        let boards: [Board]
        /// Matching items with their board, most recently active board first.
        let items: [Match]
        /// Set when more items matched than `limit`.
        let more: Int?
    }

    static let path = ["search"]
    static let summary =
        "Search all boards for text, links or file names (and board titles); each match comes with its board."
    static let params: [Param] = [
        .string(
            "query", "Words to find (case and accents ignored; every word must appear).", required: true,
            positional: true),
        .choice(
            "type",
            ["text", "shape", "sticky", "connector", "image", "file", "link", "table", "drawing", "movie", "group"],
            "Only items of this type."),
        .boolean("includeDeleted", "Also search boards in Recently Deleted."),
        .integer("limit", "Maximum items to return.", default: 25, min: 1, max: 200),
    ]
    static let examples = ["search 'packing list'", "search flights --type sticky", "search apple.com --type link"]

    static func words(_ query: String) -> [String] {
        NameMatcher.normalize(query).split(separator: " ").map(String.init)
    }

    static func validate(_ input: Input) throws {
        guard !words(input.query).isEmpty else {
            throw AgentError.invalid(
                "The search has no words.", hint: "Pass the text to look for, e.g. search 'packing list'.")
        }
    }

    static func matches(_ text: String?, _ words: [String]) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let normalized = NameMatcher.normalize(text)
        return words.allSatisfy { normalized.contains($0) }
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> Output {
        let words = words(input.query)
        return try context.snapshot { snapshot in
            let boards = try snapshot.boards(includeDeleted: input.includeDeleted)
            var found: [Match] = []
            for board in boards {
                for item in snapshot.items(board: board) where input.type == nil || item.type == input.type {
                    if matches([item.text, item.url, item.fileName].compactMap { $0 }.joined(separator: " "), words) {
                        found.append(Match(board: board.id, title: board.title, item: Item(item)))
                    }
                }
            }
            return Output(
                boards: input.type == nil ? boards.filter { matches($0.title, words) }.map(Board.init) : [],
                items: Array(found.prefix(input.limit)),
                more: found.count > input.limit ? found.count - input.limit : nil)
        }
    }

    static func pretty(_ output: Output) -> String? {
        let boards = output.boards.map { "board \($0.id): \($0.title ?? "")" }
        let items = output.items.map { match in
            "\(match.title ?? match.board) · \(match.item.type) \(match.item.id): "
                + (match.item.text ?? match.item.url ?? match.item.file ?? "").replacingOccurrences(of: "\n", with: " ")
        }
        let lines = boards + items + (output.more.map { ["… \($0) more"] } ?? [])
        return lines.isEmpty ? "No matches." : lines.joined(separator: "\n")
    }
}
