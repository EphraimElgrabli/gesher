import GesherKit
import GesherPlatform
import Foundation
import MapsCore

let nearParam = Param.string(
    "near", "Bias results to this area: a place name, address or 'lat,lon'. Default: configured maps.near.")

enum SearchPlaces: AgentOperation {
    struct Input: Decodable, Sendable {
        var query: String
        var near: String?
        var limit: Int
    }

    static let path = ["search"]
    static let summary = "Search Apple Maps for places or addresses, ranked for an area when `near` is given."
    static let params: [Param] = [
        .string("query", "What to look for: a name, address or kind of place.", required: true, positional: true),
        nearParam,
        .integer("limit", "Maximum results.", default: 10, min: 1, max: 25),
    ]
    static let examples = [
        "search 'Apple Park'", "search 'coffee' --near 'Haifa' --limit 5",
        "search 'pharmacy' --near 32.79,34.99",
    ]

    static func validate(_ input: Input) throws {
        guard !input.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalid("The search query is empty.")
        }
        try PlaceSelector.check(input.near)
    }

    static func run(_ input: Input, _ context: MapsContext) throws -> PlacesOutput {
        let center = try context.center(input.near)
        let places = try context.read.search(query: input.query, maxResults: input.limit, near: center)
        return PlacesOutput(places: places.map { PlaceSummary($0, from: center) })
    }
}

enum NearbyPlaces: AgentOperation {
    struct Input: Decodable, Sendable {
        var category: String
        var near: String?
        var radius: Int
        var limit: Int
    }

    static let path = ["nearby"]
    static let summary = "Places of a kind (cafe, pharmacy, parking...) within a radius of a place, closest first."
    static let params: [Param] = [
        .string(
            "category", "Kind of place, e.g. cafe, restaurant, pharmacy, ATM, parking.", required: true,
            positional: true),
        .string("near", "Center: a place name, address or 'lat,lon'. Default: configured maps.near."),
        .integer("radius", "Maximum distance in meters.", default: 2_000, min: 100, max: 50_000),
        .integer("limit", "Maximum results.", default: 10, min: 1, max: 25),
    ]
    static let examples = [
        "nearby cafe --near 'Bahai Gardens Haifa'", "nearby pharmacy --near 32.79,34.99 --radius 800",
    ]

    static func validate(_ input: Input) throws {
        guard !input.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalid("The category is empty.", hint: "Example: nearby cafe --near Haifa")
        }
        try PlaceSelector.check(input.near)
    }

    static func run(_ input: Input, _ context: MapsContext) throws -> PlacesOutput {
        guard let center = try context.center(input.near) else {
            throw AgentError.invalid(
                "nearby needs a center.", hint: "Pass near (a place or 'lat,lon'), or configure maps.near.")
        }
        let radius = Double(input.radius)
        let places = try context.read.search(
            query: input.category, maxResults: min(50, input.limit * 3), near: center)
        let within =
            places
            .map { ($0, $0.coordinate.distance(to: center)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .prefix(input.limit)
        return PlacesOutput(places: within.map { PlaceSummary($0.0, from: center) })
    }
}

enum PlaceDetails: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String
        var near: String?
    }

    static let path = ["place"]
    static let summary = "Details of one place: address, phone, website, category, opening hours, rating."
    static let params: [Param] = [
        .string(
            "place", "Place id (geo:...) from search, a name or address, or 'lat,lon'.", required: true,
            positional: true),
        nearParam,
    ]
    static let examples = ["place 'Louvre Museum'", "place geo:7618:123456789", "place 'Cafe Nero' --near Haifa"]

    static func validate(_ input: Input) throws {
        try PlaceSelector.check(input.place)
        try PlaceSelector.check(input.near)
    }

    static func run(_ input: Input, _ context: MapsContext) throws -> PlaceDetail {
        if let coordinate = Coordinates.parse(input.place) {
            guard
                let place = try context.read.reverseGeocode(
                    latitude: coordinate.latitude, longitude: coordinate.longitude
                ).first
            else { throw AgentError.notFound("place", input.place) }
            return PlaceDetail(place)
        }
        return PlaceDetail(try context.resolve(input.place, near: try context.center(input.near)))
    }
}

enum ReverseGeocode: AgentOperation {
    struct Input: Decodable, Sendable {
        var location: LatLon
    }

    static let path = ["reverse"]
    static let summary = "Address of a coordinate ('lat,lon')."
    static let params: [Param] = [
        .string("location", "Coordinates as 'lat,lon', e.g. 32.8191,34.9983.", required: true, positional: true)
    ]
    static let examples = ["reverse 32.8191,34.9983", "reverse '48.8606, 2.3376'"]

    static func run(_ input: Input, _ context: MapsContext) throws -> PlacesOutput {
        let coordinate = input.location.coordinate
        let places = try context.read.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return PlacesOutput(places: places.map { PlaceSummary($0, from: nil) })
    }
}
