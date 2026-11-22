import GesherPlatform
import Foundation

/// `doctor` and `permissions`, added to every app. Neither opens an app data store.
enum BuiltinOperations {
    static func make<Context>(app: String, permission: TCCService?, backend: any PermissionBackend) -> [AnyOperation<
        Context
    >] {
        var operations: [AnyOperation<Context>] = [
            AnyOperation(
                path: ["doctor"], summary: "Check version, OS and privacy permission without reading app data.",
                params: [], effect: .read
            ) { arguments, _ in
                _ = try ParamValidation.normalize(arguments, params: [], operation: "doctor")
                let report = Doctor(
                    app: app, version: Gesher.version,
                    os: ProcessInfo.processInfo.operatingSystemVersionString,
                    permission: permission.map {
                        PermissionCoordinator(backend: backend).inspect(service: $0).permission
                    },
                    defaults: UserConfig.load().values[app],
                    updateAvailable: {
                        let status = UpdateChecker().cachedStatus(installed: Gesher.version)
                        return status.shouldNotify ? status.latest : nil
                    }())
                return OperationResult(value: try JSONValue.encode(report), pretty: nil, failed: 0, succeeded: 1)
            }
        ]
        if let permission {
            let params: [Param] = [
                .boolean("request", "Show the macOS consent dialog if access is undecided."),
                .boolean("openSettings", "Open the matching Privacy & Security pane."),
            ]
            operations.append(
                AnyOperation(
                    path: ["permissions"],
                    summary: "Show \(permission.displayName) access; --request asks macOS for consent.",
                    params: params, effect: .read
                ) { arguments, _ in
                    let input = try ParamValidation.normalize(arguments, params: params, operation: "permissions")
                    let snapshot = PermissionCoordinator(backend: backend).inspect(
                        service: permission, request: input["request"] == .bool(true))
                    // Services without a dialog (Full Disk Access): --request opens the pane.
                    let settingsOnly = snapshot.requestResult == .settingsRequired
                    if input["openSettings"] == .bool(true) || settingsOnly {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        process.arguments = [permission.settingsURL]
                        try process.run()
                        process.waitUntilExit()
                    }
                    let authorized = snapshot.permission == "authorized"
                    let path = authorized ? nil : ResponsibleProcess.executablePath()
                    // Show the executable in Finder (to drag into the list) and put its path on the clipboard.
                    if settingsOnly, let path {
                        try? BuiltinOperations.run("/usr/bin/open", ["-R", path])
                        try? BuiltinOperations.run("/usr/bin/pbcopy", [], input: path)
                    }
                    let report = PermissionReport(
                        service: permission.displayName, permission: snapshot.permission,
                        requested: snapshot.requestAttempted || settingsOnly ? snapshot.requestResult?.rawValue : nil,
                        executable: path,
                        hint: authorized
                            ? nil
                            : settingsOnly
                                ? "Opened System Settings > Privacy & Security > \(permission.displayName) and showed the "
                                    + "executable in Finder: drag it into the list and turn it on (or click +, press "
                                    + "Cmd-Shift-G and paste the path, which is on the clipboard). Updates keep the grant."
                                : snapshot.recovery)
                    return OperationResult(value: try JSONValue.encode(report), pretty: nil, failed: 0, succeeded: 1)
                })
        }
        return operations
    }

    private static func run(_ executable: String, _ arguments: [String], input: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        if input != nil { process.standardInput = pipe }
        try process.run()
        if let input {
            pipe.fileHandleForWriting.write(Data(input.utf8))
            try pipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
    }

    struct Doctor: Encodable {
        let app: String
        let version: String
        let os: String
        let permission: String?
        let defaults: [String: String]?
        let updateAvailable: String?
    }

    struct PermissionReport: Encodable {
        let service: String
        let permission: String
        let requested: String?
        /// The executable macOS grants access to (its own responsible process).
        let executable: String?
        let hint: String?
    }
}
