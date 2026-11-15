import GesherPlatform
import Foundation

enum RouteGeometryDecoder {
    static func decode(_ points: [[NSNumber]]?) throws -> MapRouteGeometrySnapshot? {
        guard let points, !points.isEmpty else { return nil }
        guard points.count >= 2 else {
            throw PlatformError.fetchFailed("Native route geometry has fewer than two points.")
        }
        let coordinates = try points.map { point -> MapCoordinateSnapshot in
            guard point.count == 2, point[0].doubleValue.isFinite, point[1].doubleValue.isFinite,
                (-90...90).contains(point[0].doubleValue), (-180...180).contains(point[1].doubleValue)
            else { throw PlatformError.fetchFailed("Native route geometry contains an invalid coordinate.") }
            return MapCoordinateSnapshot(latitude: point[0].doubleValue, longitude: point[1].doubleValue)
        }
        return MapRouteGeometrySnapshot(coordinates: coordinates)
    }
}
