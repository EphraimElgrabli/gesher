import GesherPlatform
import Foundation

/// Markdown → native note paragraphs. Supported: `#`/`##`/`###` headings, `-`/`*`/`+` bullets,
/// `1.` numbered items, `- [ ]`/`- [x]` checklists, two-space (or tab) indentation, `>` quotes,
/// fenced code (monospaced), GFM tables, `**bold**`, `*italic*`, `~~strike~~`, `[text](url)`
/// (http, https, mailto) and `` `code` `` (kept as plain text). Each other line is one body
/// paragraph; runs of blank lines collapse to one empty paragraph.
public enum NoteMarkdown {
    /// Parses Markdown. When `extractTitle` is set and the first non-blank line is `# Title`, that
    /// line is returned as the title and removed from the paragraphs.
    public static func parse(_ markdown: String, extractTitle: Bool = false) throws -> (
        title: String?, document: NoteDocument
    ) {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var title: String?
        if extractTitle, let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
            lines[first].hasPrefix("# ")
        {
            title = String(lines[first].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeSubrange(0...first)
        }
        var paragraphs: [NoteDocument.Paragraph] = []
        var index = 0
        var blank = false
        func append(_ paragraph: NoteDocument.Paragraph) {
            if blank && !paragraphs.isEmpty { paragraphs.append(.init(style: .body, runs: [.init(text: "")])) }
            blank = false
            paragraphs.append(paragraph)
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blank = true
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    append(
                        .init(
                            style: .monospaced,
                            runs: [.init(text: lines[index].replacingOccurrences(of: "\t", with: "    "))]))
                    index += 1
                }
                index += 1
                continue
            }
            if trimmed.hasPrefix("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                var rows = [tableCells(trimmed)]
                index += 2
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[index].trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                let width = max(2, rows.map(\.count).max() ?? 0)
                let table = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
                if table.count >= 2 {
                    append(.init(style: .body, table: table))
                } else {
                    append(.init(style: .body, runs: [.init(text: trimmed)]))
                }
                continue
            }
            append(try paragraph(line))
            index += 1
        }
        guard !paragraphs.isEmpty || title != nil else {
            throw PlatformError.invalidArgument("The Markdown text is empty.")
        }
        return (title, NoteDocument(paragraphs: paragraphs))
    }

    static func paragraph(_ line: String) throws -> NoteDocument.Paragraph {
        var rest = Substring(line)
        var quote = false
        if rest.hasPrefix(">") {
            quote = true
            rest = rest.dropFirst()
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        }
        var spaces = 0
        while let first = rest.first, first == " " || first == "\t" {
            spaces += first == "\t" ? 2 : 1
            rest = rest.dropFirst()
        }
        let indent = min(8, spaces / 2)
        var style = NoteDocument.Style.body
        var checked: Bool?
        let lowered = rest.lowercased()
        if let marker = ["# ", "## ", "### ", "#### ", "##### ", "###### "].last(where: { rest.hasPrefix($0) }) {
            style = marker.count == 2 || marker.count == 3 ? .heading : .subheading
            rest = rest.dropFirst(marker.count)
        } else if ["- [ ] ", "* [ ] ", "+ [ ] ", "- [x] ", "* [x] ", "+ [x] "].contains(where: { lowered.hasPrefix($0) }
        ) {
            style = .checklist
            checked = lowered.dropFirst(3).hasPrefix("x")
            rest = rest.dropFirst(6)
        } else if ["- ", "* ", "+ "].contains(where: { rest.hasPrefix($0) }) {
            style = .bullet
            rest = rest.dropFirst(2)
        } else if let match = rest.firstMatch(of: #/^\d{1,9}[.)] /#) {
            style = .numbered
            rest = rest[match.range.upperBound...]
        }
        let runs = inline(String(rest))
        return .init(
            style: style, runs: runs.isEmpty ? [.init(text: "")] : runs, checked: checked,
            indent: style == .heading || style == .subheading || indent == 0 ? nil : indent, quote: quote ? true : nil)
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    static func tableCells(_ line: String) -> [String] {
        var text = line
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") && !text.hasSuffix("\\|") { text.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// Inline Markdown → runs. Markers only toggle when a matching closing marker follows, so
    /// stray `*` or `~` stay literal.
    public static func inline(_ text: String) -> [NoteDocument.Run] {
        let characters = Array(text)
        var runs: [NoteDocument.Run] = []
        var buffer = ""
        var bold = false
        var italic = false
        var strike = false
        func flush(link: String? = nil, text override: String? = nil) {
            let value = override ?? buffer
            guard !value.isEmpty else { return }
            let run = NoteDocument.Run(
                text: value, bold: bold ? true : nil, italic: italic ? true : nil,
                strikethrough: strike ? true : nil, link: link)
            if link == nil, let last = runs.last, last.link == nil, last.sameFormatting(as: run) {
                runs[runs.count - 1].text += value
            } else {
                runs.append(run)
            }
            if override == nil { buffer = "" }
        }
        func closes(_ marker: String, from start: Int) -> Bool {
            guard start < characters.count, characters[start] != " " else { return false }
            return String(characters[start...]).contains(marker)
        }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "\\", let next, "\\`*_~[]()#|>-+".contains(next) {
                buffer.append(next)
                index += 2
                continue
            }
            if character == "`", let end = characters[(index + 1)...].firstIndex(of: "`") {
                buffer += String(characters[(index + 1)..<end])
                index = end + 1
                continue
            }
            if (character == "*" && next == "*") || (character == "_" && next == "_") {
                let marker = String([character, character])
                if bold || closes(marker, from: index + 2) {
                    flush()
                    bold.toggle()
                    index += 2
                    continue
                }
            }
            if character == "~" && next == "~", strike || closes("~~", from: index + 2) {
                flush()
                strike.toggle()
                index += 2
                continue
            }
            if character == "*", italic || closes("*", from: index + 1) {
                flush()
                italic.toggle()
                index += 1
                continue
            }
            // `#word` after a space (or at the start) is a Notes tag, as the app converts it.
            if character == "#", index == 0 || characters[index - 1].isWhitespace, let next, next.isLetter {
                var end = index + 1
                while end < characters.count,
                    characters[end].isLetter || characters[end].isNumber
                        || characters[end] == "-" || characters[end] == "_"
                {
                    end += 1
                }
                flush()
                runs.append(NoteDocument.Run(text: String(characters[index..<end]), tag: true))
                index = end
                continue
            }
            if character == "[", let link = parseLink(characters, at: index) {
                flush()
                flush(link: link.url, text: link.text)
                index = link.end
                continue
            }
            buffer.append(character)
            index += 1
        }
        flush()
        return runs
    }

    /// A tag name as Notes accepts it: starts with a letter; letters, digits, '-' and '_'.
    public static func isTagName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter, name.count <= 100 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func parseLink(_ characters: [Character], at start: Int) -> (text: String, url: String, end: Int)? {
        guard let close = characters[start...].firstIndex(of: "]"), close + 1 < characters.count,
            characters[close + 1] == "(", let end = characters[(close + 1)...].firstIndex(of: ")")
        else { return nil }
        let text = String(characters[(start + 1)..<close])
        let url = String(characters[(close + 2)..<end])
        guard !text.isEmpty, let parsed = URL(string: url),
            ["http", "https", "mailto"].contains(parsed.scheme?.lowercased() ?? "")
        else { return nil }
        return (text, url, end + 1)
    }
}
