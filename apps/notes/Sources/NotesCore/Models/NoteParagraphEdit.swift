import GesherPlatform
import Foundation

/// Address paragraphs by zero-based index in the exact body returned by note get.
public enum NoteParagraphEdit {
    public static func range(in text: NSString, index: Int) throws -> NSRange {
        guard index >= 0 else { throw PlatformError.invalidArgument("Paragraph index must be nonnegative.") }
        var offset = 0
        var current = 0
        while offset < text.length {
            let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
            if current == index { return range }
            offset = NSMaxRange(range)
            current += 1
        }
        throw PlatformError.invalidArgument("Paragraph index is outside the note body.")
    }
}
