import Foundation
import ObjCRuntimeSupport

/// UTF-16 ranges and native formatting, suitable for checking saved note content.
public struct NoteTextRun: Codable, Sendable, Equatable {
    public let location: Int
    public let length: Int
    public let text: String
    public let paragraphStyle: Int?
    public let indent: Int?
    public let checked: Bool?
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    public let strikethrough: Bool
    public let link: String?
    public let highlight: Int?
    public let attachmentID: String?

    static func extract(from text: NSAttributedString, runtime: NotesRuntime) -> [Self] {
        var result: [Self] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let paragraph = attributes[.init("TTStyle")] as AnyObject?
            let todo = paragraph.flatMap { runtime.objectValue(from: $0, selectors: ["todo"]) }
            let hints = (attributes[.init("TTHints")] as? NSNumber)?.intValue ?? 0
            let attachment = attributes[.init("NSAttachment")] as AnyObject?
            result.append(
                Self(
                    location: range.location, length: range.length,
                    text: (text.string as NSString).substring(with: range),
                    paragraphStyle: paragraph.flatMap {
                        let selector = NSSelectorFromString("style")
                        guard ObjCMatchesMethodSignature($0, selector, "I", []) else { return nil }
                        typealias StyleGetter = @convention(c) (AnyObject, Selector) -> UInt32
                        let method = class_getMethodImplementation(type(of: $0), selector)!
                        return Int(unsafeBitCast(method, to: StyleGetter.self)($0, selector))
                    },
                    indent: paragraph.flatMap { runtime.intValue(from: $0, selectors: ["indent"]) },
                    checked: todo.flatMap { runtime.boolValue(from: $0, selectors: ["done"]) },
                    bold: hints & 1 != 0, italic: hints & 2 != 0,
                    underline: (attributes[.init("TTUnderline")] as? NSNumber)?.boolValue ?? false,
                    strikethrough: (attributes[.init("TTStrikethrough")] as? NSNumber)?.boolValue ?? false,
                    link: attributes[.init("NSLink")].map { String(describing: $0) },
                    highlight: (attributes[.init("TTEmphasis")] as? NSNumber)?.intValue,
                    attachmentID: attachment.flatMap {
                        runtime.stringValue(from: $0, selectors: ["attachmentIdentifier"])
                    }
                ))
        }
        return result
    }
}
