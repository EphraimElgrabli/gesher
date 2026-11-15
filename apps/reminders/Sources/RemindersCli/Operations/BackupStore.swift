import GesherPlatform
import Foundation
import RemindersCore

/// JSON snapshots of tasks taken before bulk or destructive changes, so `task_restore` can
/// undo them. Directory: `$GESHER_BACKUP_DIR`, else `~/.config/gesher/backups/`.
struct BackupStore: Sendable {
    /// Bulk changes above this many tasks are backed up first.
    static let bulkThreshold = 5

    struct Entry: Codable, Sendable {
        let task: ReminderTaskSnapshot
        let list: String
        let section: String?
    }

    struct File: Codable, Sendable {
        let app: String
        let operation: String
        let createdAt: String
        let tasks: [Entry]
    }

    let directory: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let path = environment["GESHER_BACKUP_DIR"], !path.isEmpty {
            directory = URL(fileURLWithPath: path)
        } else {
            directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/gesher/backups")
        }
    }

    init(directory: URL) { self.directory = directory }

    /// Writes the snapshot and returns its path. Fails (and so blocks the change) if it cannot be written.
    func save(operation: String, tasks: [ReminderTaskSnapshot], catalog: ReminderCatalog) throws -> String {
        let entries = tasks.map {
            Entry(
                task: $0, list: catalog.list($0.listID)?.title ?? $0.listID,
                section: $0.sectionID.flatMap { catalog.section($0)?.title })
        }
        let stamp = DateOutput.iso(Date(), timeZone: TimeZone(secondsFromGMT: 0)!)
        let file = File(app: "reminders", operation: operation, createdAt: DateOutput.iso(Date()), tasks: entries)
        do {
            try PrivateStorage.createDirectory(directory)
            let name =
                "reminders-\(stamp.replacingOccurrences(of: ":", with: ""))-\(operation)-\(UUID().uuidString.prefix(6)).json"
            let url = directory.appendingPathComponent(name)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try PrivateStorage.write(try encoder.encode(file), to: url)
            return url.path
        } catch {
            throw AgentError(
                code: "backup_failed",
                message: "Could not save the backup before \(operation): \(error.localizedDescription)",
                hint: "Nothing was changed. Check that \(directory.path) is writable, or act on 5 tasks or fewer.")
        }
    }

    func load(_ selector: String) throws -> (path: String, file: File) {
        var path = selector
        if selector == "latest" {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            guard let latest = files.filter({ $0.hasPrefix("reminders-") && $0.hasSuffix(".json") }).sorted().last
            else {
                throw AgentError(code: "not_found", message: "No Reminders backups in \(directory.path).")
            }
            path = directory.appendingPathComponent(latest).path
        } else if !selector.contains("/") {
            path = directory.appendingPathComponent(selector).path
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw AgentError(
                code: "not_found", message: "Backup \(selector) not found.",
                hint: "Pass the path from a result's 'backup' field, or 'latest'.")
        }
        do {
            return (path, try JSONDecoder().decode(File.self, from: data))
        } catch {
            throw AgentError.invalid("\(path) is not a Reminders backup: \(error.localizedDescription)")
        }
    }
}
