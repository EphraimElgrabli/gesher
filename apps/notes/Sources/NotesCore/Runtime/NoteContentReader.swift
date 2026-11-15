import GesherPlatform
import CoreData
import Foundation
import ObjCRuntimeSupport
import UniformTypeIdentifiers

/// Reads a native note body into `NoteContent`: paragraph styles, inline formatting, inline
/// tokens (hashtags, mentions, links) as their display text, tables as cells and other
/// attachments as references.
enum NoteContentReader {
    static let tableUTI = "com.apple.notes.table"
    static let inlinePrefix = "com.apple.notes.inlinetextattachment"

    static func read(_ text: NSAttributedString, note: AnyObject, runtime: NotesRuntime) throws -> NoteContent {
        let tables = Dictionary(
            try NoteTable.read(from: text, note: note, runtime: runtime).map { ($0.id, $0.cells) },
            uniquingKeysWith: { first, _ in first })
        let context = runtime.objectValue(from: note, selectors: ["managedObjectContext"])
        let string = text.string as NSString
        var paragraphs: [NoteContent.Paragraph] = []
        var offset = 0
        while offset < string.length {
            let full = string.paragraphRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(full)
            var length = full.length
            while length > 0, [10, 13, 0x2028, 0x2029].contains(string.character(at: full.location + length - 1)) {
                length -= 1
            }
            let range = NSRange(location: full.location, length: length)
            let styleObject =
                full.length > 0
                ? text.attribute(.init("TTStyle"), at: full.location, effectiveRange: nil) as AnyObject? : nil
            var base = NoteContent.Paragraph(style: .init(nativeValue: styleObject.flatMap(styleValue)))
            if let styleObject {
                if let indent = runtime.intValue(from: styleObject, selectors: ["indent"]), indent > 0 {
                    base.indent = indent
                }
                if let level = runtime.intValue(from: styleObject, selectors: ["blockQuoteLevel"]), level > 0 {
                    base.quote = true
                }
                if base.style == .checklist,
                    let todo = runtime.objectValue(from: styleObject, selectors: ["todo"])
                {
                    base.checked = runtime.boolValue(from: todo, selectors: ["done"]) ?? false
                }
            }
            var current = base
            var emittedBlock = false
            text.enumerateAttributes(in: range) { attributes, subrange, _ in
                if let attachment = attributes[.init("NSAttachment")] as AnyObject? {
                    guard attachment.responds(to: NSSelectorFromString("attachmentUTI")) else { return }
                    let uti = runtime.stringValue(from: attachment, selectors: ["attachmentUTI"]) ?? ""
                    let id = runtime.stringValue(from: attachment, selectors: ["attachmentIdentifier"]) ?? ""
                    if uti.hasPrefix(inlinePrefix) {
                        let inline = context.flatMap {
                            ObjCSendIdIdArg(attachment, NSSelectorFromString("inlineAttachmentInContext:"), $0)
                                as AnyObject?
                        }
                        let display =
                            inline.flatMap { runtime.stringValue(from: $0, selectors: ["displayText", "altText"]) }
                            ?? ""
                        var token = run(display, attributes)
                        if inline.flatMap({ runtime.boolValue(from: $0, selectors: ["isHashtagAttachment"]) }) == true {
                            token.tag = true
                        }
                        current.runs.append(token)
                        return
                    }
                    // Block attachment: close the current text paragraph, emit the block.
                    if !current.runs.isEmpty {
                        paragraphs.append(merged(current))
                        current = base
                    }
                    if uti == tableUTI, let cells = tables[id] {
                        paragraphs.append(.init(style: .body, indent: base.indent, table: cells))
                    } else {
                        paragraphs.append(
                            .init(
                                style: .body, indent: base.indent,
                                attachment: reference(id: id, uti: uti, note: note, runtime: runtime)))
                    }
                    emittedBlock = true
                    return
                }
                current.runs.append(run(string.substring(with: subrange), attributes))
            }
            if !current.runs.isEmpty || !emittedBlock { paragraphs.append(merged(current)) }
        }
        return NoteContent(paragraphs: paragraphs)
    }

    static func styleValue(_ style: AnyObject) -> Int? {
        let selector = NSSelectorFromString("style")
        guard ObjCMatchesMethodSignature(style, selector, "I", []) else { return nil }
        typealias StyleGetter = @convention(c) (AnyObject, Selector) -> UInt32
        let method = class_getMethodImplementation(type(of: style), selector)!
        return Int(unsafeBitCast(method, to: StyleGetter.self)(style, selector))
    }

    static func run(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> NoteDocument.Run {
        let hints = (attributes[.init("TTHints")] as? NSNumber)?.intValue ?? 0
        func flag(_ key: String) -> Bool? { (attributes[.init(key)] as? NSNumber)?.boolValue == true ? true : nil }
        return NoteDocument.Run(
            text: text, bold: hints & 1 != 0 ? true : nil, italic: hints & 2 != 0 ? true : nil,
            underline: flag("TTUnderline"), strikethrough: flag("TTStrikethrough"),
            link: attributes[.init("NSLink")].map { ($0 as? URL)?.absoluteString ?? String(describing: $0) },
            highlight: (attributes[.init("TTEmphasis")] as? NSNumber)?.intValue)
    }

    static func merged(_ paragraph: NoteContent.Paragraph) -> NoteContent.Paragraph {
        var result = paragraph
        result.runs = []
        for run in paragraph.runs where !run.text.isEmpty || paragraph.runs.count == 1 {
            if let last = result.runs.last, last.sameFormatting(as: run) {
                result.runs[result.runs.count - 1].text += run.text
            } else {
                result.runs.append(run)
            }
        }
        return result
    }

    static func reference(id: String, uti: String, note: AnyObject, runtime: NotesRuntime) -> NoteContent.Attachment {
        let attachment =
            ObjCSendIdIdArg(note, NSSelectorFromString("attachmentWithIdentifier:"), id as NSString) as AnyObject?
        return NoteContent.Attachment(
            id: id, kind: kind(uti), name: attachment.flatMap { name(of: $0, runtime: runtime) })
    }

    static func name(of attachment: AnyObject, runtime: NotesRuntime) -> String? {
        let media = runtime.objectValue(from: attachment, selectors: ["media"])
        let candidates = [
            runtime.stringValue(from: attachment, selectors: ["userTitle"]),
            runtime.stringValue(from: attachment, selectors: ["title"]),
            media.flatMap { runtime.stringValue(from: $0, selectors: ["filename"]) },
            runtime.stringValue(from: attachment, selectors: ["urlString"]),
        ]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    static func kind(_ uti: String) -> String {
        if uti == tableUTI { return "table" }
        if uti.hasPrefix("com.apple.drawing") || uti == "com.apple.paper" || uti.hasPrefix("com.apple.paper") {
            return "drawing"
        }
        if uti == "com.apple.notes.gallery" { return "scan" }
        if uti == "public.url" || uti.hasPrefix("com.apple.notes.url") { return "link" }
        guard let type = UTType(uti) else { return "file" }
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .pdf) { return "pdf" }
        if type.conforms(to: .audio) { return "audio" }
        if type.conforms(to: .movie) { return "video" }
        if type.conforms(to: .url) { return "link" }
        return "file"
    }
}
