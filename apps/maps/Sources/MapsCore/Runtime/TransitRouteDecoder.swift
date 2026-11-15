import GesherPlatform
import Foundation

/// Transit uses scheduled suggested routes, not the automobile waypoint-leg representation.
enum TransitRouteDecoder {
    /// `abs_start_time`/`abs_end_time` are absolute times (seconds since 2001-01-01 UTC).
    static func decode(_ fields: [String: Any], origin: MapPlaceSnapshot, destination: MapPlaceSnapshot) throws
        -> MapRouteSnapshot
    {
        guard let departure = fields["abs_start_time"] as? NSNumber,
            let arrival = fields["abs_end_time"] as? NSNumber,
            departure.doubleValue.isFinite, arrival.doubleValue.isFinite,
            arrival.doubleValue >= departure.doubleValue
        else {
            throw PlatformError.fetchFailed("Native transit suggestion has missing or malformed scheduled times.")
        }
        // Distance and street instructions are not part of a transit suggestion; never infer them.
        return MapRouteSnapshot(
            origin: origin, destination: destination, transportType: "transit", distanceMeters: nil,
            durationSeconds: arrival.doubleValue - departure.doubleValue,
            departure: Date(timeIntervalSinceReferenceDate: departure.doubleValue),
            arrival: Date(timeIntervalSinceReferenceDate: arrival.doubleValue))
    }
}
