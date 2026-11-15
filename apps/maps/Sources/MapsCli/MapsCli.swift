import GesherKit
import GesherPlatform
import Foundation
import MapsCore

@main
enum MapsCli {
    static func main() { MapsApp.make().main() }
}

/// The Maps app: place search and details, reverse geocoding, routes and ETAs from GeoServices.
enum MapsApp {
    static func make(context: @escaping () throws -> MapsContext = { MapsContext() }) -> AgentApp<MapsContext> {
        AgentApp(
            name: "maps",
            summary: "Search places, read place details and get routes and travel times with Apple Maps.",
            instructions: """
                Places accept a name or address, 'lat,lon', or a place id (geo:...) from an earlier result. \
                A name resolves to Apple Maps' best match: check the returned name and address before relying on \
                it, and pass the id or 'lat,lon' afterwards. Use `near` to bias a search to an area. A route \
                applies only to its mode; a failed mode has no time or distance: report it, never estimate.
                """,
            operations: [
                AnyOperation(SearchPlaces.self),
                AnyOperation(NearbyPlaces.self),
                AnyOperation(PlaceDetails.self),
                AnyOperation(ReverseGeocode.self),
                AnyOperation(Directions.self),
                AnyOperation(TravelTimes.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Maps operation for the life of the process (or MCP session).
final class MapsContext {
    let read: MapsReading
    let config: UserConfig

    init(config: UserConfig = .load()) {
        read = MapsReadRepository(runtime: MapsRuntime())
        self.config = config
    }

    /// For tests: answer from a stand-in instead of GeoServices.
    init(read: MapsReading, config: UserConfig) {
        self.read = read
        self.config = config
    }

    /// Explicit `near` > configured `maps.near` > no bias.
    func center(_ near: String?) throws -> MapCoordinateSnapshot? {
        guard let selector = near ?? config.value("maps", "near") else { return nil }
        return try resolve(selector, near: nil).coordinate
    }

    /// Resolves a place selector: `lat,lon`, a `geo:` id, or a name/address (Apple Maps' top match,
    /// optionally biased to `near`).
    func resolve(_ selector: String, near: MapCoordinateSnapshot?) throws -> MapPlaceSnapshot {
        let text = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AgentError.invalid("A place cannot be empty.") }
        if let coordinate = Coordinates.parse(text) {
            return MapPlaceSnapshot(id: nil, name: text, formattedAddress: nil, coordinate: coordinate)
        }
        if text.hasPrefix("geo:") {
            try PlaceSelector.check(text)
            return try read.place(id: text)
        }
        guard let place = try read.search(query: text, maxResults: 1, near: near).first else {
            throw AgentError(
                code: "not_found", message: "Apple Maps found no place for '\(text)'.",
                hint: "Rephrase the name or address, add the city, or pass 'lat,lon'.")
        }
        return place
    }
}

/// Checks a place selector that needs no Maps data, so bad input fails before GeoServices loads.
enum PlaceSelector {
    static func check(_ selector: String?) throws {
        guard let selector else { return }
        let text = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AgentError.invalid("A place cannot be empty.") }
        if text.hasPrefix("geo:"), MapPlaceID.parse(text) == nil {
            throw AgentError.invalid(
                "'\(text)' is not a place id.",
                hint: "Use an id from search (geo:<provider>:<number>), a name or 'lat,lon'.")
        }
    }
}

enum Coordinates {
    /// `32.79,34.99` (spaces allowed). Nil when the text is not a coordinate pair.
    static func parse(_ text: String) -> MapCoordinateSnapshot? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]),
            (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        return MapCoordinateSnapshot(latitude: latitude, longitude: longitude)
    }
}

/// A `lat,lon` parameter value, validated while decoding (before Maps is touched).
struct LatLon: Decodable, Sendable {
    let coordinate: MapCoordinateSnapshot

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let coordinate = Coordinates.parse(text) else {
            throw AgentError.invalid(
                "'\(text)' is not 'lat,lon'.", hint: "Pass decimal degrees, e.g. 32.8191,34.9983.")
        }
        self.coordinate = coordinate
    }
}
