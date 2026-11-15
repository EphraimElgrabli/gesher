import Foundation

/// Backups hold the user's private data (deleted events, tasks, contacts), so their folder is
/// readable only by the user (0700) and each file only by the user (0600).
public enum PrivateStorage {
    public static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    public static func write(_ data: Data, to url: URL, options: Data.WritingOptions = .atomic) throws {
        try data.write(to: url, options: options)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
