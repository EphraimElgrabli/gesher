import Foundation

/// What the Maps operations read. `MapsReadRepository` answers from GeoServices; tests inject a
/// stand-in so operation logic runs without the network.
public protocol MapsReading: AnyObject {
    func search(query: String, maxResults: Int, near: MapCoordinateSnapshot?) throws -> [MapPlaceSnapshot]
    func place(id: String) throws -> MapPlaceSnapshot
    func reverseGeocode(latitude: Double, longitude: Double) throws -> [MapPlaceSnapshot]
    func route(
        origin: MapPlaceSnapshot, destination: MapPlaceSnapshot, transportType: String, timepoint: MapTimepoint?
    ) throws -> MapRouteSnapshot
}

extension MapsReadRepository: MapsReading {}

/// A `geo:<provider>:<muid>` place id, as returned by search.
public enum MapPlaceID {
    public static func parse(_ id: String) -> (provider: Int32, muid: UInt64)? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "geo", let provider = Int32(parts[1]), let muid = UInt64(parts[2]),
            muid != 0
        else { return nil }
        return (provider, muid)
    }
}
