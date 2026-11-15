import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Structured native Notes text. Paragraphs are separate lines; runs carry inline formatting.
public struct NoteDocument: Codable, Sendable {
    public var paragraphs: [Paragraph]

    public init(paragraphs: [Paragraph] = []) {
        self.paragraphs = paragraphs
    }

    public struct Paragraph: Codable, Sendable {
        public var style: Style
        public var runs: [Run]
        public var checked: Bool?
        public var indent: Int?
        public var table: [[String]]?
        public var quote: Bool?

        public init(
            style: Style,
            runs: [Run] = [],
            checked: Bool? = nil,
            indent: Int? = nil,
            table: [[String]]? = nil,
            quote: Bool? = nil
        ) {
            self.style = style
            self.runs = runs
            self.checked = checked
            self.indent = indent
            self.table = table
            self.quote = quote
        }
    }

    public enum Style: String, Codable, Sendable {
        case title, heading, subheading, body, monospaced, bullet, dashed, numbered, checklist
        var nativeValue: Int {
            switch self {
            case .title: 0
            case .heading: 1
            case .subheading: 2
            case .monospaced: 4
            case .body: 3
            case .bullet: 100
            case .dashed: 101
            case .numbered: 102
            case .checklist: 103
            }
        }
    }

    public struct Run: Codable, Sendable {
        public var text: String
        public var bold: Bool?
        public var italic: Bool?
        public var underline: Bool?
        public var strikethrough: Bool?
        public var link: String?
        public var highlight: Int?
        /// A Notes tag: `text` is the tag (with or without '#'); it becomes a real #tag, as typed in the app.
        public var tag: Bool?

        public init(
            text: String,
            bold: Bool? = nil,
            italic: Bool? = nil,
            underline: Bool? = nil,
            strikethrough: Bool? = nil,
            link: String? = nil,
            highlight: Int? = nil,
            tag: Bool? = nil
        ) {
            self.tag = tag
            self.text = text
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strikethrough = strikethrough
            self.link = link
            self.highlight = highlight
        }
    }

    public func validate() throws {
        guard !paragraphs.isEmpty else {
            throw PlatformError.invalidArgument("A document must contain at least one paragraph.")
        }
        for paragraph in paragraphs {
            guard (0...8).contains(paragraph.indent ?? 0), (!paragraph.runs.isEmpty || paragraph.table != nil) else {
                throw PlatformError.invalidArgument("Paragraphs require runs and an indent between 0 and 8.")
            }
            if let table = paragraph.table {
                guard table.count >= 2, let width = table.first?.count, width >= 2,
                    table.allSatisfy({ $0.count == width }), table.count <= 100, width <= 20,
                    paragraph.runs.isEmpty
                else {
                    throw PlatformError.invalidArgument(
                        "Tables require a rectangular array with 2–100 rows, 2–20 columns, and no runs.")
                }
            }
            for run in paragraph.runs {
                if let highlight = run.highlight, !(1...5).contains(highlight) {
                    throw PlatformError.invalidArgument("Highlight must be a native emphasis value from 1 to 5.")
                }
                guard !run.text.contains("\n"), !run.text.contains("\r") else {
                    throw PlatformError.invalidArgument("Use separate paragraphs for line breaks.")
                }
                if run.tag == true {
                    let name = run.text.hasPrefix("#") ? String(run.text.dropFirst()) : run.text
                    guard NoteMarkdown.isTagName(name) else {
                        throw PlatformError.invalidArgument(
                            "'\(run.text)' is not a valid tag: use letters, digits, '-' or '_', starting with a letter."
                        )
                    }
                }
                if let link = run.link {
                    guard let url = URL(string: link),
                        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
                    else {
                        throw PlatformError.invalidArgument("Links must use http, https, or mailto.")
                    }
                }
            }
        }
    }

    public func attributedString(runtime: NotesRuntime, note: AnyObject? = nil) throws -> NSAttributedString {
        try validate()
        try runtime.load()
        let result = NSMutableAttributedString(string: "")
        for paragraph in paragraphs {
            if let table = paragraph.table {
                guard let note else { throw PlatformError.invalidArgument("A table requires a native note.") }
                result.append(try NoteTable.create(cells: table, note: note, runtime: runtime))
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            let cls: AnyClass = try runtime.requireClass("ICTTParagraphStyle")
            guard let style = ObjCSendId(cls, NSSelectorFromString("defaultParagraphStyle")),
                let mutableStyle = ObjCSendId(style, NSSelectorFromString("mutableCopy"))
            else { throw PlatformError.internalError("Cannot construct native paragraph style.") }
            // Paragraph identity must be unique: the mergeable document shares style updates by UUID.
            ObjCSendVoidId(mutableStyle, NSSelectorFromString("setUuid:"), NSUUID())
            ObjCSendVoidUInt32(mutableStyle, NSSelectorFromString("setStyle:"), UInt32(paragraph.style.nativeValue))
            ObjCSendVoidInteger(mutableStyle, NSSelectorFromString("setIndent:"), paragraph.indent ?? 0)
            if paragraph.quote == true {
                ObjCSendVoidInteger(mutableStyle, NSSelectorFromString("setBlockQuoteLevel:"), 1)
            }
            if paragraph.style == .checklist {
                let todoClass: AnyClass = try runtime.requireClass("ICTTTodo")
                guard let allocated = ObjCAlloc(todoClass),
                    let todo = ObjCSendInitNil(allocated, NSSelectorFromString("init"))
                else {
                    throw PlatformError.internalError("Cannot construct checklist.")
                }
                guard
                    let value = ObjCSendIdBool(todo, NSSelectorFromString("todoWithDone:"), paragraph.checked ?? false)
                else {
                    throw PlatformError.internalError("Cannot set checklist state.")
                }
                ObjCSendVoidId(mutableStyle, NSSelectorFromString("setTodo:"), value)
            }
            let start = result.length
            for run in paragraph.runs {
                if run.tag == true {
                    guard let note else { throw PlatformError.invalidArgument("A tag requires a native note.") }
                    result.append(try NoteHashtag.create(run.text, note: note, runtime: runtime))
                    continue
                }
                var attributes: [NSAttributedString.Key: Any] = [:]
                attributes[.init("TTHints")] = (run.bold == true ? 1 : 0) | (run.italic == true ? 2 : 0)
                if run.underline == true { attributes[.init("TTUnderline")] = 1 }
                if run.strikethrough == true { attributes[.init("TTStrikethrough")] = 1 }
                if let link = run.link { attributes[.init("NSLink")] = link }
                if let highlight = run.highlight { attributes[.init("TTEmphasis")] = highlight }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            result.append(NSAttributedString(string: "\n"))
            result.addAttribute(
                .init("TTStyle"), value: mutableStyle, range: NSRange(location: start, length: result.length - start))
        }
        return result
    }
}
