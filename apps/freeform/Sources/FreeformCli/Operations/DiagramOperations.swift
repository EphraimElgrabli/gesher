import Foundation
import FreeformCore
import GesherKit
import GesherPlatform

enum CreateDiagram: AgentOperation {
    struct Input: Decodable, Sendable {
        var board: String
        var spec: FreeformDiagramSpec
        var ifRevision: String?
    }

    static let path = ["diagram", "create"]
    static let summary =
        "Create a structured, independently editable diagram (nodes + bound connectors) from a JSON spec with explicit coordinates or deterministic auto-layout."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("board", "Board title or id.", required: true, positional: true),
        Param(
            "spec", .object,
            "JSON object with 'nodes' ([{key, type, shape, text, x, y, width, height, fill, stroke}]) and optional 'edges' ([{from, to, style, stroke, headEnd, tailEnd}]), 'direction' ('top-down'|'left-right'), 'originX', 'originY', 'horizontalGap', 'verticalGap'.",
            required: true),
        .string("ifRevision", "Only save if the board still matches this revision."),
    ]
    static let examples = [
        #"diagram create 'Architecture' --spec '{"nodes":[{"key":"a","type":"shape","shape":"rounded_rectangle","text":"Client"},{"key":"b","type":"shape","shape":"rounded_rectangle","text":"API"}],"edges":[{"from":"a","to":"b"}]}'"#
    ]

    static func validate(_ input: Input) throws {
        try FreeformWriter.validateDiagram(input.spec)
    }

    static func run(_ input: Input, _ context: FreeformContext) throws -> DiagramOutput {
        let result = try context.writer.createDiagram(
            board: input.board, spec: input.spec, ifRevision: input.ifRevision)
        return DiagramOutput(
            board: result.board.id, title: result.board.title, revision: result.board.revision,
            nodes: result.nodes.mapValues(Item.init), edges: result.edges.map(Item.init),
            sync: context.writer.lastWriteSync)
    }
}
