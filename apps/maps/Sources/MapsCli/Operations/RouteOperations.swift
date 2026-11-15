import GesherKit
import GesherPlatform
import Foundation
import MapsCore

/// Travel modes as the Maps app names them, mapped to GeoServices transport types.
enum TravelMode: String, Codable, Sendable, CaseIterable {
    case driving, walking, cycling, transit

    var native: String {
        switch self {
        case .driving: "automobile"
        case .walking: "walking"
        case .cycling: "bicycle"
        case .transit: "transit"
        }
    }
}

private let endpointSummary = "a place id (geo:...), a name or address, or 'lat,lon'"
private let timeParams: [Param] = [
    .date("departAt", "Leave at this time, e.g. 'tomorrow 8:30'. Default: now."),
    .date("arriveBy", "Arrive by this time instead (not with departAt)."),
]

/// `departAt` and `arriveBy` exclude each other; checked while decoding, before Maps is touched.
private func makeTimepoint(departAt: NaturalDate?, arriveBy: NaturalDate?) throws -> MapTimepoint? {
    switch (departAt, arriveBy) {
    case (nil, nil): return nil
    case (let depart?, nil): return MapTimepoint(.departAt, depart.date)
    case (nil, let arrive?): return MapTimepoint(.arriveBy, arrive.date)
    default: throw AgentError.invalid("Use departAt or arriveBy, not both.")
    }
}

private func endpoints(_ from: String, _ to: String, _ context: MapsContext) throws -> (
    MapPlaceSnapshot, MapPlaceSnapshot
) {
    let origin = try context.resolve(from, near: nil)
    // The destination is ranked near the origin, as in the Maps app.
    return (origin, try context.resolve(to, near: origin.coordinate))
}

enum Directions: AgentOperation {
    struct Input: Decodable, Sendable {
        var from: String
        var to: String
        var mode: TravelMode
        var timepoint: MapTimepoint?
        var steps: Bool

        enum CodingKeys: String, CodingKey { case from, to, mode, departAt, arriveBy, steps }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            from = try container.decode(String.self, forKey: .from)
            to = try container.decode(String.self, forKey: .to)
            mode = try container.decode(TravelMode.self, forKey: .mode)
            steps = try container.decode(Bool.self, forKey: .steps)
            timepoint = try makeTimepoint(
                departAt: container.decodeIfPresent(NaturalDate.self, forKey: .departAt),
                arriveBy: container.decodeIfPresent(NaturalDate.self, forKey: .arriveBy))
        }
    }

    static let path = ["route"]
    static let summary = "Directions between two places for one mode: distance, duration, times and turn-by-turn steps."
    static let params: [Param] =
        [
            .string("from", "Start: \(endpointSummary).", required: true),
            .string("to", "Destination: \(endpointSummary).", required: true),
            .choice("mode", TravelMode.allCases.map(\.rawValue), "Travel mode.", default: "driving"),
        ] + timeParams + [.boolean("steps", "Include turn-by-turn steps.", default: true)]
    static let examples = [
        "route --from 'Haifa' --to 'Tel Aviv'", "route --from 32.79,34.99 --to 'Acre' --mode cycling --no-steps",
        "route --from 'Louvre' --to 'Eiffel Tower' --mode transit --depart-at 'tomorrow 9:00'",
    ]

    static func validate(_ input: Input) throws {
        try PlaceSelector.check(input.from)
        try PlaceSelector.check(input.to)
    }

    static func run(_ input: Input, _ context: MapsContext) throws -> RouteOutput {
        let (origin, destination) = try endpoints(input.from, input.to, context)
        let route = try context.read.route(
            origin: origin, destination: destination, transportType: input.mode.native, timepoint: input.timepoint)
        return RouteOutput(route, mode: input.mode, timepoint: input.timepoint, steps: input.steps)
    }
}

/// Batch over modes: each mode succeeds or fails on its own, with no estimate for a failed one.
enum TravelTimes: AgentOperation {
    struct Input: Decodable, Sendable {
        var from: String
        var to: String
        var mode: [TravelMode]
        var timepoint: MapTimepoint?

        enum CodingKeys: String, CodingKey { case from, to, mode, departAt, arriveBy }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            from = try container.decode(String.self, forKey: .from)
            to = try container.decode(String.self, forKey: .to)
            mode = try container.decodeIfPresent([TravelMode].self, forKey: .mode) ?? [.driving]
            timepoint = try makeTimepoint(
                departAt: container.decodeIfPresent(NaturalDate.self, forKey: .departAt),
                arriveBy: container.decodeIfPresent(NaturalDate.self, forKey: .arriveBy))
        }
    }

    static let path = ["eta"]
    static let summary = "Travel time, distance, departure and arrival between two places for one or more modes."
    static let params: [Param] =
        [
            .string("from", "Start: \(endpointSummary).", required: true),
            .string("to", "Destination: \(endpointSummary).", required: true),
            .list(
                "mode", "Travel modes to compare (repeat the flag). Default: driving.",
                of: .choice(TravelMode.allCases.map(\.rawValue))),
        ] + timeParams
    static let examples = [
        "eta --from 'Haifa' --to 'Tel Aviv' --mode driving --mode transit",
        "eta --from 32.79,34.99 --to 'Haifa Port' --mode walking --arrive-by 'today 18:00'",
    ]

    static func validate(_ input: Input) throws {
        try PlaceSelector.check(input.from)
        try PlaceSelector.check(input.to)
        guard !input.mode.isEmpty else { throw AgentError.invalid("Pass at least one mode.") }
    }

    static func run(_ input: Input, _ context: MapsContext) throws -> EtaOutput {
        let (origin, destination) = try endpoints(input.from, input.to, context)
        var modes: [TravelMode] = []
        for mode in input.mode where !modes.contains(mode) { modes.append(mode) }
        let results = Batch.run(modes, label: \.rawValue) { mode in
            let route = try context.read.route(
                origin: origin, destination: destination, transportType: mode.native, timepoint: input.timepoint)
            return RouteOutput(route, mode: mode, timepoint: input.timepoint, steps: false).eta
        }
        return EtaOutput(
            from: PlaceSummary(origin, from: nil), to: PlaceSummary(destination, from: nil), results: results)
    }
}
