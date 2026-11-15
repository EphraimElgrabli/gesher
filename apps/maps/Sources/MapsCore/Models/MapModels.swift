import GesherPlatform
import Foundation

public struct MapCoordinateSnapshot: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in meters (haversine), used to rank nearby results.
    public func distance(to other: MapCoordinateSnapshot) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Opening hours for one weekday, as local times of the place. `weekday` follows the Gregorian
/// calendar (1 = Sunday ... 7 = Saturday). Intervals are seconds after local midnight.
public struct MapDailyHoursSnapshot: Codable, Sendable, Equatable {
    public let weekday: Int
    public let intervals: [ClosedRange<Double>]

    public init(weekday: Int, intervals: [ClosedRange<Double>]) {
        self.weekday = weekday
        self.intervals = intervals
    }
}

public struct MapPlaceSnapshot: Codable, Sendable {
    /// `geo:<provider>:<muid>` when GeoServices returns a native POI identity; nil otherwise.
    public let id: String?
    public let name: String
    public let formattedAddress: String?
    public let coordinate: MapCoordinateSnapshot
    public let category: String?
    public let phoneNumber: String?
    public let url: String?
    public let timeZone: String?
    /// Nil when the service has no hours for the place.
    public let hours: [MapDailyHoursSnapshot]?
    /// Apple's normalized user rating, 0–100, and the number of ratings it is based on.
    public let ratingPercent: Double?
    public let ratingCount: Int?

    public init(
        id: String?, name: String, formattedAddress: String?, coordinate: MapCoordinateSnapshot,
        category: String? = nil, phoneNumber: String? = nil, url: String? = nil, timeZone: String? = nil,
        hours: [MapDailyHoursSnapshot]? = nil, ratingPercent: Double? = nil, ratingCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.formattedAddress = formattedAddress
        self.coordinate = coordinate
        self.category = category
        self.phoneNumber = phoneNumber
        self.url = url
        self.timeZone = timeZone
        self.hours = hours
        self.ratingPercent = ratingPercent
        self.ratingCount = ratingCount
    }
}

public struct MapRouteStepSnapshot: Codable, Sendable {
    public let instruction: String?
    public let maneuver: String?
    public let roadName: String?
    public let distanceMeters: Double
    public let durationSeconds: Double

    public init(
        instruction: String?, distanceMeters: Double, durationSeconds: Double, maneuver: String? = nil,
        roadName: String? = nil
    ) {
        let text = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instruction = text?.isEmpty == false ? text : nil
        self.maneuver = maneuver
        let road = roadName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.roadName = road?.isEmpty == false ? road : nil
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

/// Native route points in travel order; explicit latitude/longitude avoids axis-order ambiguity.
public struct MapRouteGeometrySnapshot: Codable, Sendable {
    public let coordinates: [MapCoordinateSnapshot]

    public init(coordinates: [MapCoordinateSnapshot]) {
        self.coordinates = coordinates
    }
}

/// When the traveller leaves or must arrive. Nil means "leave now".
public struct MapTimepoint: Sendable, Equatable {
    public enum Kind: Int32, Sendable {
        case departAt = 0
        case arriveBy = 1
    }

    public let kind: Kind
    public let date: Date

    public init(_ kind: Kind, _ date: Date) {
        self.kind = kind
        self.date = date
    }
}

public struct MapRouteSnapshot: Codable, Sendable {
    public let origin: MapPlaceSnapshot
    public let destination: MapPlaceSnapshot
    public let transportType: String
    /// Nil when the service did not report a distance (transit suggestions).
    public let distanceMeters: Double?
    public let durationSeconds: Double
    /// Scheduled departure and arrival, when the service returns them (transit).
    public let departure: Date?
    public let arrival: Date?
    public let steps: [MapRouteStepSnapshot]
    public let geometry: MapRouteGeometrySnapshot?

    public init(
        origin: MapPlaceSnapshot, destination: MapPlaceSnapshot, transportType: String, distanceMeters: Double?,
        durationSeconds: Double, departure: Date? = nil, arrival: Date? = nil, steps: [MapRouteStepSnapshot] = [],
        geometry: MapRouteGeometrySnapshot? = nil
    ) {
        self.origin = origin
        self.destination = destination
        self.transportType = transportType
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.departure = departure
        self.arrival = arrival
        self.steps = steps
        self.geometry = geometry
    }
}
