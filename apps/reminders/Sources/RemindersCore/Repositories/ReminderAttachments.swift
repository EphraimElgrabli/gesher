import GesherPlatform
import Foundation
import ImageIO
import ObjCRuntimeSupport
import UniformTypeIdentifiers

extension ReminderWriteRepository {
    /// Adds image or file attachments from local paths. Images (by type) become image
    /// attachments with their pixel size, as the app adds them; other files become files.
    public func addAttachments(taskID: String, files: [URL]) throws -> ReminderTaskSnapshot {
        guard !files.isEmpty else { throw ReminderCLIError.invalidArgument("Give at least one file.") }
        for file in files {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { throw ReminderCLIError.invalidArgument("Not a file: \(file.path).") }
            guard FileManager.default.isReadableFile(atPath: file.path) else {
                throw ReminderCLIError.invalidArgument("Cannot read \(file.path).")
            }
        }
        let store = try runtime.makeStore()
        let reminder = try read.fetchReminderObject(id: taskID, store: store)
        let before = try read.fetchTask(id: taskID)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try updateReminder(reminder, saveRequest)
        let context = try runtime.requireObject(item, selector: "attachmentContext")
        for file in files {
            var error: NSError?
            let added: AnyObject?
            if let size = Self.imageSize(file) {
                typealias Add =
                    @convention(c) (
                        AnyObject, Selector, AnyObject, UInt64, UInt64, AutoreleasingUnsafeMutablePointer<NSError?>?
                    ) -> AnyObject?
                let (selector, add) = try runtime.implementation(
                    context, "addImageAttachmentWithURL:width:height:error:", as: Add.self)
                added = add(context, selector, file as NSURL, size.width, size.height, &error)
            } else {
                typealias Add =
                    @convention(c) (
                        AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>?
                    ) -> AnyObject?
                let (selector, add) = try runtime.implementation(
                    context, "addFileAttachmentWithURL:error:", as: Add.self)
                added = add(context, selector, file as NSURL, &error)
            }
            guard added != nil, error == nil else {
                throw ReminderCLIError.saveFailed(
                    "ReminderKit did not attach \(file.lastPathComponent): "
                        + (error?.localizedDescription ?? "no attachment returned") + ". No change was saved.")
            }
        }
        try runtime.saveSynchronously(saveRequest)
        let after = try MutationVerification.readback(type: "task", id: taskID) { try read.fetchTask(id: taskID) }
        let count = { (task: ReminderTaskSnapshot) in task.attachments.filter { $0.kind != "url" }.count }
        guard count(after) == count(before) + files.count else {
            throw unverified("task", taskID, "not every attachment was read back")
        }
        return after
    }

    /// Removes one attachment (image, file or link) by its id.
    public func removeAttachment(taskID: String, attachmentID: String) throws -> ReminderTaskSnapshot {
        let store = try runtime.makeStore()
        let reminder = try read.fetchReminderObject(id: taskID, store: store)
        let saveRequest = try runtime.makeSaveRequest(store: store)
        let item = try updateReminder(reminder, saveRequest)
        let context = try runtime.requireObject(item, selector: "attachmentContext")
        guard
            let attachment = runtime.objectValue(from: context, selectors: ["attachments"]).flatMap(
                runtime.objectArray)?.first(where: { runtime.objectIDString(from: $0) == attachmentID })
        else { throw ReminderCLIError.objectNotFound(type: "attachment", id: attachmentID) }
        try runtime.sendVoidId(context, selector: "removeAttachment:", argument: attachment)
        try runtime.saveSynchronously(saveRequest)
        let after = try MutationVerification.readback(type: "task", id: taskID) { try read.fetchTask(id: taskID) }
        guard !after.attachments.contains(where: { $0.id == attachmentID }) else {
            throw unverified("task", taskID, "the attachment is still there")
        }
        return after
    }

    static func imageSize(_ file: URL) -> (width: UInt64, height: UInt64)? {
        guard let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
            let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.uint64Value,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.uint64Value
        else { return nil }
        return (width, height)
    }
}
