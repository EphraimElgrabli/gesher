import Foundation

/// A note body read back from native Notes, paragraph by paragraph. It uses the same paragraph
/// and run vocabulary as `NoteDocument` (the write schema), plus read-only attachment references,
/// so a read document can be edited and written back.
public struct NoteContent: Encodable, Sendable, Equatable {
    public var paragraphs: [Paragraph]

    public init(paragraphs: [Paragraph]) {
        self.paragraphs = paragraphs
    }

    public struct Paragraph: Encodable, Sendable, Equatable {
        public var style: NoteDocument.Style
        public var runs: [NoteDocument.Run]
        public var checked: Bool?
        public var indent: Int?
        public var quote: Bool?
        public var table: [[String]]?
        public var attachment: Attachment?

        public init(
            style: NoteDocument.Style, runs: [NoteDocument.Run] = [], checked: Bool? = nil, indent: Int? = nil,
            quote: Bool? = nil, table: [[String]]? = nil, attachment: Attachment? = nil
        ) {
            self.style = style
            self.runs = runs
            self.checked = checked
            self.indent = indent
            self.quote = quote
            self.table = table
            self.attachment = attachment
        }

        public var text: String { runs.map(\.text).joined() }
    }

    /// A non-text item embedded in the note (image, PDF, audio, drawing, link card, file).
    public struct Attachment: Encodable, Sendable, Equatable {
        public let id: String
        public let kind: String
        public let name: String?

        public init(id: String, kind: String, name: String?) {
            self.id = id
            self.kind = kind
            self.name = name
        }
    }

    /// Title paragraph text (first paragraph).
    public var title: String { paragraphs.first?.text ?? "" }

    /// Checklist items in body order with their zero-based paragraph index.
    public var checklist: [(index: Int, text: String, checked: Bool)] {
        paragraphs.enumerated().compactMap { index, paragraph in
            paragraph.style == .checklist ? (index, paragraph.text, paragraph.checked ?? false) : nil
        }
    }
}

extension NoteDocument.Style {
    init(nativeValue: Int?) {
        switch nativeValue {
        case 0: self = .title
        case 1: self = .heading
        case 2: self = .subheading
        case 4: self = .monospaced
        case 100: self = .bullet
        case 101: self = .dashed
        case 102: self = .numbered
        case 103: self = .checklist
        default: self = .body
        }
    }

    var isList: Bool { [.bullet, .dashed, .numbered, .checklist].contains(self) }
}

extension NoteDocument.Run: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.sameFormatting(as: rhs)
    }

    func sameFormatting(as other: Self) -> Bool {
        bold == other.bold && italic == other.italic && underline == other.underline
            && strikethrough == other.strikethrough && link == other.link && highlight == other.highlight
            && tag == other.tag
    }
}

// MARK: - Rendering

extension NoteContent {
    /// Markdown: headings, lists, checklists, quotes, fenced monospaced blocks, GFM tables, bold,
    /// italic, strikethrough and links. Underline and highlight have no Markdown form (use the
    /// document form to see them). Attachments render as `[kind: name]`.
    public func markdown() -> String {
        var lines: [String] = []
        var inCode = false
        var number: [Int: Int] = [:]
        for paragraph in paragraphs {
            if paragraph.style == .monospaced && paragraph.table == nil && paragraph.attachment == nil {
                if !inCode { lines.append("```") }
                inCode = true
                lines.append(paragraph.text)
                continue
            }
            if inCode {
                lines.append("```")
                inCode = false
            }
            if paragraph.style != .numbered { number = [:] }
            if let table = paragraph.table {
                lines.append(contentsOf: Self.markdownTable(table))
                continue
            }
            if let attachment = paragraph.attachment {
                lines.append(Self.attachmentLabel(attachment))
                continue
            }
            let text = paragraph.runs.map(Self.markdownRun).joined()
            let indent = String(repeating: "  ", count: paragraph.indent ?? 0)
            var line: String
            switch paragraph.style {
            case .title: line = "# " + text
            case .heading: line = "## " + text
            case .subheading: line = "### " + text
            case .bullet, .dashed: line = indent + "- " + text
            case .numbered:
                let level = paragraph.indent ?? 0
                number[level, default: 0] += 1
                number = number.filter { $0.key <= level }
                line = indent + "\(number[level] ?? 1). " + text
            case .checklist: line = indent + (paragraph.checked == true ? "- [x] " : "- [ ] ") + text
            case .body, .monospaced: line = indent + text
            }
            if paragraph.quote == true { line = "> " + line }
            lines.append(line)
        }
        if inCode { lines.append("```") }
        return lines.joined(separator: "\n")
    }

    /// Plain text without markup: list markers as `•`, `-`, `1.`, checklists as `[ ]`/`[x]`,
    /// tables as `|`-separated rows, attachments as `[kind: name]`.
    public func plainText() -> String {
        var number: [Int: Int] = [:]
        return paragraphs.map { paragraph -> String in
            if paragraph.style != .numbered { number = [:] }
            if let table = paragraph.table { return table.map { $0.joined(separator: " | ") }.joined(separator: "\n") }
            if let attachment = paragraph.attachment { return Self.attachmentLabel(attachment) }
            let indent = String(repeating: "  ", count: paragraph.indent ?? 0)
            switch paragraph.style {
            case .bullet: return indent + "• " + paragraph.text
            case .dashed: return indent + "- " + paragraph.text
            case .numbered:
                let level = paragraph.indent ?? 0
                number[level, default: 0] += 1
                number = number.filter { $0.key <= level }
                return indent + "\(number[level] ?? 1). " + paragraph.text
            case .checklist: return indent + (paragraph.checked == true ? "[x] " : "[ ] ") + paragraph.text
            default: return indent + paragraph.text
            }
        }.joined(separator: "\n")
    }

    static func attachmentLabel(_ attachment: Attachment) -> String {
        "[\(attachment.kind)" + (attachment.name.map { ": " + $0 } ?? "") + "]"
    }

    static func markdownRun(_ run: NoteDocument.Run) -> String {
        guard !run.text.trimmingCharacters(in: .whitespaces).isEmpty else { return run.text }
        if run.tag == true { return run.text.hasPrefix("#") ? run.text : "#" + run.text }
        // Keep surrounding spaces outside the markers so the result stays valid Markdown.
        let leading = String(run.text.prefix { $0 == " " })
        let trailing = String(run.text.reversed().prefix { $0 == " " })
        var core = String(run.text.dropFirst(leading.count).dropLast(trailing.count))
        if run.strikethrough == true { core = "~~\(core)~~" }
        if run.italic == true { core = "*\(core)*" }
        if run.bold == true { core = "**\(core)**" }
        if let link = run.link { core = "[\(core)](\(link))" }
        return leading + core + trailing
    }

    static func markdownTable(_ table: [[String]]) -> [String] {
        guard let header = table.first else { return [] }
        func row(_ cells: [String]) -> String {
            "| "
                + cells.map {
                    $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
                }.joined(separator: " | ") + " |"
        }
        return [row(header), "|" + String(repeating: " --- |", count: header.count)] + table.dropFirst().map(row)
    }
}
