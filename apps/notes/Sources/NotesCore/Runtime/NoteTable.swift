import AppKit
import GesherPlatform
import ObjCRuntimeSupport

/// Populate a native Notes table and embed its attachment in the note text.
enum NoteTable {
    static func read(from text: NSAttributedString, note: AnyObject, runtime: NotesRuntime) throws
        -> [NoteTableSnapshot]
    {
        var ids: [String] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let value = value as AnyObject?,
                let id = runtime.stringValue(from: value, selectors: ["attachmentIdentifier"]), !ids.contains(id)
            {
                ids.append(id)
            }
        }
        guard !ids.isEmpty else { return [] }
        try runtime.loadTableSupport()
        var result: [NoteTableSnapshot] = []
        for id in ids {
            guard
                let attachment = ObjCSendIdIdArg(
                    note, try NativeProperty.selector(note, "attachmentWithIdentifier:"), id as NSString)
                    as AnyObject?,
                runtime.boolValue(from: attachment, selectors: ["isTable"]) == true,
                let model = runtime.objectValue(from: attachment, selectors: ["tableModel"]),
                let table = runtime.objectValue(from: model, selectors: ["table"])
            else { continue }
            let rows = ObjCSendInteger(table, try NativeProperty.selector(table, "rowCount"))
            let columns = ObjCSendInteger(table, try NativeProperty.selector(table, "columnCount"))
            guard rows >= 0, columns >= 0, rows <= 10_000, columns <= 10_000, rows * columns <= 1_000_000 else {
                throw PlatformError.fetchFailed(
                    "Native table dimensions are invalid or exceed the supported read size.")
            }
            let selector = NSSelectorFromString("stringForColumnIndex:rowIndex:")
            guard let method = class_getInstanceMethod(type(of: table), selector) else {
                throw PlatformError.missingSelector(className: "ICTable", selector: NSStringFromSelector(selector))
            }
            let cell = unsafeBitCast(
                method_getImplementation(method),
                to: (@convention(c) (AnyObject, Selector, UInt, UInt) -> AnyObject?).self)
            var cells: [[String]] = []
            for row in 0..<rows {
                cells.append(
                    (0..<columns).map { column in
                        cell(table, selector, UInt(column), UInt(row)).flatMap {
                            runtime.stringValue(from: $0, selectors: ["string"])
                        } ?? ""
                    })
            }
            result.append(NoteTableSnapshot(id: id, cells: cells))
        }
        return result
    }

    static func updateCell(id: String, row: Int, column: Int, text: String, note: AnyObject, runtime: NotesRuntime)
        throws
    {
        try runtime.loadTableSupport()
        guard
            let attachment = ObjCSendIdIdArg(
                note, try NativeProperty.selector(note, "attachmentWithIdentifier:"), id as NSString) as AnyObject?,
            runtime.boolValue(from: attachment, selectors: ["isTable"]) == true,
            let model = runtime.objectValue(from: attachment, selectors: ["tableModel"]),
            let table = runtime.objectValue(from: model, selectors: ["table"])
        else { throw PlatformError.objectNotFound(type: "table", id: id) }
        let rows = ObjCSendInteger(table, try NativeProperty.selector(table, "rowCount"))
        let columns = ObjCSendInteger(table, try NativeProperty.selector(table, "columnCount"))
        guard row >= 0, row < rows, column >= 0, column < columns else {
            throw PlatformError.invalidArgument("Table cell index is outside the table.")
        }
        let selector = NSSelectorFromString("setAttributedString:columnIndex:rowIndex:")
        guard let method = class_getInstanceMethod(type(of: table), selector) else {
            throw PlatformError.missingSelector(className: "ICTable", selector: NSStringFromSelector(selector))
        }
        let setCell = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, NSAttributedString, UInt, UInt) -> Void).self)
        setCell(table, selector, NSAttributedString(string: text), UInt(column), UInt(row))
        try DynamicRuntime.shared.sendVoid(model, selector: "writeMergeableData")
        try DynamicRuntime.shared.sendVoid(attachment, selector: "saveMergeableDataIfNeeded")
    }

    static func create(cells: [[String]], note: AnyObject, runtime: NotesRuntime) throws -> NSAttributedString {
        try runtime.loadTableSupport()
        let selector = NSSelectorFromString("addTableAttachmentWithText:")
        guard note.responds(to: selector) else {
            throw PlatformError.missingSelector(className: "ICNote", selector: NSStringFromSelector(selector))
        }
        guard runtime.objectValue(from: note, selectors: ["currentReplicaID"]) != nil else {
            throw PlatformError.saveFailed("Notes did not provide a replica identifier for table editing.")
        }
        let content = NSAttributedString(string: "Table")
        guard let attachment = ObjCSendIdIdArg(note, selector, content) as AnyObject?,
            let identifier = runtime.stringValue(from: attachment, selectors: ["identifier"]),
            let uti = runtime.stringValue(from: attachment, selectors: ["typeUTI"])
        else { throw PlatformError.saveFailed("Notes could not import the table.") }
        let cls: AnyClass = try runtime.requireClass("ICTTAttachment")
        guard let allocated = ObjCAlloc(cls), let inline = ObjCSendInitNil(allocated, NSSelectorFromString("init"))
        else {
            throw PlatformError.saveFailed("Notes could not embed the table.")
        }
        try DynamicRuntime.shared.sendVoidId(
            inline as AnyObject, selector: "setAttachmentIdentifier:", argument: identifier as NSString)
        try DynamicRuntime.shared.sendVoidId(
            inline as AnyObject, selector: "setAttachmentUTI:", argument: uti as NSString)
        guard let model = runtime.objectValue(from: attachment, selectors: ["tableModel"]),
            let table = runtime.objectValue(from: model, selectors: ["table"])
        else { throw PlatformError.saveFailed("Notes did not create a table model.") }
        for (countName, insertName, count) in [
            ("rowCount", "insertRowAtIndex:", cells.count), ("columnCount", "insertColumnAtIndex:", cells[0].count),
        ] {
            let insertSelector = NSSelectorFromString(insertName)
            guard let method = class_getInstanceMethod(type(of: table), insertSelector) else {
                throw PlatformError.missingSelector(className: "ICTable", selector: insertName)
            }
            let insert = unsafeBitCast(
                method_getImplementation(method), to: (@convention(c) (AnyObject, Selector, UInt) -> AnyObject?).self)
            let initialCount = ObjCSendInteger(table, try NativeProperty.selector(table, countName))
            for index in initialCount..<max(initialCount, count) {
                guard insert(table, insertSelector, UInt(index)) != nil else {
                    throw PlatformError.saveFailed("Table insertion failed.")
                }
            }
            guard ObjCSendInteger(table, try NativeProperty.selector(table, countName)) >= count else {
                throw PlatformError.saveFailed("Native table dimensions did not update.")
            }
        }
        let cellSelector = NSSelectorFromString("setAttributedString:columnIndex:rowIndex:")
        guard let method = class_getInstanceMethod(type(of: table), cellSelector) else {
            throw PlatformError.missingSelector(className: "ICTable", selector: NSStringFromSelector(cellSelector))
        }
        let setCell = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, NSAttributedString, UInt, UInt) -> Void).self)
        for (row, values) in cells.enumerated() {
            for (column, value) in values.enumerated() {
                setCell(table, cellSelector, NSAttributedString(string: value), UInt(column), UInt(row))
            }
        }
        try DynamicRuntime.shared.sendVoid(model, selector: "writeMergeableData")
        try DynamicRuntime.shared.sendVoid(attachment, selector: "saveMergeableDataIfNeeded")
        return NSAttributedString(string: "\u{fffc}", attributes: [.attachment: inline])
    }
}
