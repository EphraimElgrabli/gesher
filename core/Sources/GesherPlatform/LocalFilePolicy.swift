import Foundation

/// Decides which local files an agent may hand to an app that stores or syncs them (attachments to
/// notes and reminders, files added to Freeform boards) and where exports may be written.
///
/// Attachments leave the Mac through iCloud and, in shared notes, lists and boards, reach other
/// people. A prompt-injected instruction must not be able to attach `~/.ssh/id_ed25519` or a token
/// file, so hidden files and folders, `~/Library` (Keychains, app data; iCloud Drive excepted) and
/// key or credential files are refused, after resolving symbolic links. There is no override: the
/// user can copy a file to a regular folder first. Exports are kept out of the same places.
public enum LocalFilePolicy {
    /// File name extensions of keys, certificates, keychains and password databases.
    static let sensitiveExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "p8", "keychain", "keychain-db", "kdbx", "kdb", "ovpn", "gpg", "asc",
        "netrc", "pgpass", "tfstate",
    ]

    /// File names (lowercased) that hold credentials whatever their folder.
    static let sensitiveNames: Set<String> = [
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "id_ecdsa_sk", "id_ed25519_sk", "authorized_keys",
        "known_hosts", "credentials", "credentials.json", "secrets.json", "token.json", "service-account.json",
    ]

    /// An existing, readable regular file the caller may attach. `home` is injectable for tests.
    public static func attachable(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser)
        throws -> URL
    {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
            FileManager.default.isReadableFile(atPath: url.path)
        else { throw AgentError.invalid("No readable file at \(path).", hint: "Give the path of an existing file.") }
        if let reason = refusal(url.resolvingSymlinksInPath(), home: home.resolvingSymlinksInPath())
            ?? refusal(url, home: home)
        {
            throw AgentError(
                code: "file_not_allowed", message: "\(path) was not attached: \(reason).",
                hint:
                    "Gesher does not attach hidden, system or credential files. If the user really wants this file "
                    + "shared, ask them to copy it to a regular folder such as Documents and pass that copy.")
        }
        return url
    }

    /// A folder exports may be written to (created when missing). Hidden folders, `~/Library` and
    /// system folders are refused, so an attachment named by someone else (a shared note's file
    /// name) cannot land in `~/Library/LaunchAgents` or a shell configuration folder.
    public static func exportDirectory(
        _ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        if let reason = refusal(url.resolvingSymlinksInPath(), home: home.resolvingSymlinksInPath(), file: false)
            ?? refusal(url, home: home, file: false)
        {
            throw AgentError(
                code: "file_not_allowed", message: "Gesher does not write to \(path): \(reason).",
                hint: "Choose a regular folder such as Downloads, Documents or Desktop.")
        }
        return url
    }

    /// Why a file must not be attached (or a folder written to), or nil when it may be.
    public static func refusal(_ url: URL, home: URL, file: Bool = true) -> String? {
        let components = url.standardizedFileURL.pathComponents
        let name = url.lastPathComponent.lowercased()
        if components.dropFirst().contains(where: { $0.hasPrefix(".") }) {
            return file ? "it is a hidden file or inside a hidden folder" : "it is a hidden folder"
        }
        let keyLike = name.hasPrefix("id_") && url.pathExtension.isEmpty
        if file,
            sensitiveNames.contains(name) || keyLike || sensitiveExtensions.contains(url.pathExtension.lowercased())
        {
            return "it looks like a key, certificate or credential file"
        }
        let homeComponents = home.standardizedFileURL.pathComponents
        if components.starts(with: homeComponents) {
            let relative = Array(components.dropFirst(homeComponents.count))
            if relative.first == "Library" {
                let iCloudDrive = ["Library", "Mobile Documents", "com~apple~CloudDocs"]
                return relative.starts(with: iCloudDrive) ? nil : "it is inside ~/Library (app data and keychains)"
            }
            return nil
        }
        let systemRoots = [
            ["/", "Library"], ["/", "System"], ["/", "private", "etc"], ["/", "etc"], ["/", "private", "var", "db"],
            ["/", "var", "db"], ["/", "usr"], ["/", "bin"], ["/", "sbin"],
        ]
        if systemRoots.contains(where: { components.starts(with: $0) }) {
            return "it is a system file"
        }
        if components.count > 2, components[1] == "Users", components[2] != "Shared" {
            return "it belongs to another user"
        }
        return nil
    }
}
