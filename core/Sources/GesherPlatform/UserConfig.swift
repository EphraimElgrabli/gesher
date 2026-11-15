import Foundation

/// Optional user defaults shared by CLI and MCP, e.g. a default Reminders list or Weather location.
///
/// File: `$GESHER_CONFIG`, else `~/.config/gesher/config.json`:
/// ```json
/// { "weather": { "location": "Haifa", "units": "metric" }, "reminders": { "list": "Inbox" } }
/// ```
/// Resolution order for any default: explicit input > this file > the app's native default
/// (default list, calendar, account) > a documented fallback. A missing or unreadable file is
/// simply "no configured defaults".
public struct UserConfig: Sendable {
    public let values: [String: [String: String]]

    public init(values: [String: [String: String]]) { self.values = values }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> UserConfig {
        let path =
            environment["GESHER_CONFIG"]
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gesher/config.json").path
        guard let data = FileManager.default.contents(atPath: path),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return UserConfig(values: [:]) }
        var values: [String: [String: String]] = [:]
        for (app, section) in raw {
            guard let section = section as? [String: Any] else { continue }
            values[app] = section.compactMapValues { value in
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return nil
            }
        }
        return UserConfig(values: values)
    }

    public func value(_ app: String, _ key: String) -> String? {
        values[app]?[key].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }
}
