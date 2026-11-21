// swift-tools-version: 6.0

import PackageDescription
import Foundation

// Standalone CLIs carry the privacy purpose strings required for native macOS prompts.
func privacyLinkerSettings(_ app: String) -> [LinkerSetting] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let plist = root.appendingPathComponent("config/privacy/" + app + ".plist").path
    return [
        .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", plist])
    ]
}

let package = Package(
    name: "Gesher",
    // The lowest deployment target the code compiles for. Runtime support is what matters: the private
    // frameworks are only tested on macOS 27 (see README, Requirements).
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Core platform libraries
        .library(name: "GesherPlatform", targets: ["GesherPlatform"]),

        // App domain core libraries
        .library(name: "RemindersCore", targets: ["RemindersCore"]),
        .library(name: "NotesCore", targets: ["NotesCore"]),
        .library(name: "CalendarCore", targets: ["CalendarCore"]),
        .library(name: "ContactsCore", targets: ["ContactsCore"]),
        .library(name: "MapsCore", targets: ["MapsCore"]),
        .library(name: "WeatherCore", targets: ["WeatherCore"]),
        .library(name: "FreeformCore", targets: ["FreeformCore"]),

        // Executables
        .executable(name: "reminders-cli", targets: ["RemindersCli"]),
        .executable(name: "notes-cli", targets: ["NotesCli"]),
        .executable(name: "calendar-cli", targets: ["CalendarCli"]),
        .executable(name: "contacts-cli", targets: ["ContactsCli"]),
        .executable(name: "maps-cli", targets: ["MapsCli"]),
        .executable(name: "weather-cli", targets: ["WeatherCli"]),
        .executable(name: "freeform-cli", targets: ["FreeformCli"]),
    ],
    targets: [
        // MARK: - Core Shared Layer
        .target(
            name: "ObjCRuntimeSupport",
            dependencies: [],
            path: "core/Sources/ObjCRuntimeSupport"
        ),
        .target(
            name: "GesherPlatform",
            dependencies: ["ObjCRuntimeSupport"],
            path: "core/Sources/GesherPlatform"
        ),
        .testTarget(
            name: "GesherPlatformTests",
            dependencies: ["GesherPlatform"],
            path: "core/Tests/GesherPlatformTests"
        ),

        .target(
            name: "GesherKit",
            dependencies: ["GesherPlatform"],
            path: "core/Sources/GesherKit"
        ),
        .testTarget(
            name: "GesherKitTests",
            dependencies: ["GesherKit"],
            path: "core/Tests/GesherKitTests"
        ),
        // MARK: - Reminders
        .target(
            name: "RemindersCore",
            dependencies: [
                "ObjCRuntimeSupport",
                "GesherPlatform",
            ],
            path: "apps/reminders/Sources/RemindersCore"
        ),
        .executableTarget(
            name: "RemindersCli",
            dependencies: [
                "GesherKit",
                "RemindersCore",
                "GesherPlatform",
            ],
            path: "apps/reminders/Sources/RemindersCli",
            linkerSettings: privacyLinkerSettings("reminders")
        ),
        .testTarget(
            name: "RemindersCliTests",
            dependencies: ["RemindersCore", "RemindersCli", "GesherKit", "GesherPlatform"],
            path: "apps/reminders/Tests/RemindersCliTests"
        ),

        // MARK: - Notes
        .target(
            name: "NotesCore",
            dependencies: [
                "ObjCRuntimeSupport",
                "GesherPlatform",
            ],
            path: "apps/notes/Sources/NotesCore"
        ),
        .executableTarget(
            name: "NotesCli",
            dependencies: [
                "GesherKit",
                "NotesCore",
                "GesherPlatform",
            ],
            path: "apps/notes/Sources/NotesCli",
            linkerSettings: privacyLinkerSettings("notes")
        ),
        .testTarget(
            name: "NotesCliTests",
            dependencies: ["NotesCore", "NotesCli", "GesherKit", "GesherPlatform"],
            path: "apps/notes/Tests/NotesCliTests"
        ),

        // MARK: - Calendar
        .target(
            name: "CalendarCore",
            dependencies: [
                "ObjCRuntimeSupport",
                "GesherPlatform",
            ],
            path: "apps/calendar/Sources/CalendarCore"
        ),
        .executableTarget(
            name: "CalendarCli",
            dependencies: [
                "GesherKit",
                "CalendarCore",
                "GesherPlatform",
            ],
            path: "apps/calendar/Sources/CalendarCli",
            linkerSettings: privacyLinkerSettings("calendar")
        ),
        .testTarget(
            name: "CalendarCliTests",
            dependencies: ["CalendarCore", "CalendarCli", "GesherKit", "GesherPlatform"],
            path: "apps/calendar/Tests/CalendarCliTests"
        ),

        // MARK: - Contacts
        .target(
            name: "ContactsCore",
            dependencies: [
                "ObjCRuntimeSupport",
                "GesherPlatform",
            ],
            path: "apps/contacts/Sources/ContactsCore"
        ),
        .executableTarget(
            name: "ContactsCli",
            dependencies: [
                "GesherKit",
                "ContactsCore",
                "GesherPlatform",
            ],
            path: "apps/contacts/Sources/ContactsCli",
            linkerSettings: privacyLinkerSettings("contacts")
        ),
        .testTarget(
            name: "ContactsCliTests",
            dependencies: ["ContactsCore", "ContactsCli", "GesherKit", "GesherPlatform"],
            path: "apps/contacts/Tests/ContactsCliTests"
        ),

        // MARK: - Maps
        .target(
            name: "MapsCore",
            dependencies: [
                "ObjCRuntimeSupport",
                "GesherPlatform",
            ],
            path: "apps/maps/Sources/MapsCore"
        ),
        .executableTarget(
            name: "MapsCli",
            dependencies: [
                "GesherKit",
                "MapsCore",
                "GesherPlatform",
            ],
            path: "apps/maps/Sources/MapsCli",
            linkerSettings: privacyLinkerSettings("maps")
        ),
        .testTarget(
            name: "MapsCliTests",
            dependencies: ["MapsCore", "MapsCli", "GesherKit", "GesherPlatform"],
            path: "apps/maps/Tests/MapsCliTests"
        ),

        // MARK: - Weather
        .target(
            name: "WeatherCore",
            dependencies: [
                "ObjCRuntimeSupport",
                "GesherPlatform",
            ],
            path: "apps/weather/Sources/WeatherCore"
        ),
        .executableTarget(
            name: "WeatherCli",
            dependencies: [
                "GesherKit",
                "WeatherCore",
                "GesherPlatform",
            ],
            path: "apps/weather/Sources/WeatherCli",
            linkerSettings: privacyLinkerSettings("weather")
        ),
        .testTarget(
            name: "WeatherCliTests",
            dependencies: ["WeatherCore", "WeatherCli", "GesherKit", "GesherPlatform"],
            path: "apps/weather/Tests/WeatherCliTests"
        ),

        // MARK: - Freeform
        .target(
            name: "FreeformCore",
            dependencies: ["ObjCRuntimeSupport", "GesherPlatform"],
            path: "apps/freeform/Sources/FreeformCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "FreeformCli",
            dependencies: ["GesherKit", "FreeformCore", "GesherPlatform"],
            path: "apps/freeform/Sources/FreeformCli",
            linkerSettings: privacyLinkerSettings("freeform")
        ),
        .testTarget(
            name: "FreeformCliTests",
            dependencies: ["FreeformCore", "FreeformCli", "GesherKit", "GesherPlatform"],
            path: "apps/freeform/Tests/FreeformCliTests"
        ),
    ]
)
