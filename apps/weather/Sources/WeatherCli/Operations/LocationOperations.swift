import GesherKit
import GesherPlatform
import Foundation
import WeatherCore

enum ListLocations: AgentOperation {
    static let path = ["location", "list"]
    static let summary = "List saved Weather locations in the app's order."
    static let params: [Param] = []
    static let examples = ["location list"]

    static func run(_ input: NoInput, _ context: WeatherContext) throws -> LocationsOutput {
        LocationsOutput(locations: try context.read.fetchSavedLocations().map(SavedLocation.init))
    }
}

enum SearchLocations: AgentOperation {
    struct Input: Decodable, Sendable {
        var query: String
        var limit: Int
    }

    static let path = ["location", "search"]
    static let summary = "Find places matching a name or address (does not save anything)."
    static let params: [Param] = [
        .string("query", "Place name or address.", required: true, positional: true),
        .integer("limit", "Maximum results.", default: 5, min: 1, max: 10),
    ]
    static let examples = ["location search Springfield --limit 3"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> SearchOutput {
        SearchOutput(results: try context.runtime.geocodeCandidates(input.query).prefix(input.limit).map(Place.init))
    }
}

/// Batch: several places can be saved in one call; each is verified independently.
enum AddLocations: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: [String]
        var name: String?
        var timeZone: String?
    }

    static let path = ["location", "add"]
    static let summary = "Save one or more places as Weather locations (re-adding the same place is a no-op)."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .list("place", "Places to save: city, address or 'lat,lon'.", required: true, positional: true),
        .string("name", "Display name (only when saving a single place)."),
        .string("timeZone", "IANA time zone, needed only for coordinates without a known zone."),
    ]
    static let examples = [
        "location add Haifa 'Tel Aviv'", "location add 32.08,34.78 --name Home --time-zone Asia/Jerusalem",
    ]

    static func run(_ input: Input, _ context: WeatherContext) throws -> BatchResult<SavedLocation> {
        guard input.name == nil || input.place.count == 1 else {
            throw AgentError.invalid(
                "name applies to a single place.", hint: "Add places one at a time to name them.")
        }
        return Batch.run(input.place, label: { $0 }) { place in
            SavedLocation(try context.write.addLocation(place: place, name: input.name, timeZone: input.timeZone))
        }
    }
}

/// Batch, destructive: selectors must match a saved location's id or exact name (no fuzzy matching).
enum RemoveLocations: AgentOperation {
    struct Input: Decodable, Sendable {
        var location: [String]
    }

    static let path = ["location", "remove"]
    static let summary = "Remove saved Weather locations by exact name or id; other locations are kept."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("location", "Saved location names or ids.", required: true, positional: true)
    ]
    static let examples = ["location remove Haifa", "location remove 'Tel Aviv' Eilat"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> BatchResult<SavedLocation> {
        Batch.run(input.location, label: { $0 }) { selector in
            SavedLocation(try context.write.removeLocation(idOrName: selector))
        }
    }
}
