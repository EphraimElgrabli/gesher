import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Let GeoServices decode routing-path bytes and resolve localized instruction arguments.
enum ComposedRouteDecoder {
    static func decode(
        waypointRoute: AnyObject, response: AnyObject, waypoints: AnyObject?, attributes: AnyObject,
        origin: MapPlaceSnapshot, destination: MapPlaceSnapshot, transportType: String
    ) throws -> MapRouteSnapshot {
        let dynamic = DynamicRuntime.shared
        guard let waypoints else {
            throw PlatformError.fetchFailed("Native directions reply is missing resolved waypoints.")
        }
        let initializerClass = try dynamic.requireClass("GEORouteInitializerData")
        let routeClass = try dynamic.requireClass("GEOComposedRoute")
        let initializer = try dynamic.alloc(initializerClass)
        let initializerSelector = NSSelectorFromString("initWithWaypoints:routeAttributes:directionsResponse:")
        guard ObjCMatchesMethodSignature(initializer, initializerSelector, "@", ["@", "@", "@"]),
            let data = ObjCSendIdIdId(initializer, initializerSelector, waypoints, attributes, response)
        else { throw PlatformError.fetchFailed("Native route initializer ABI is unavailable.") }
        let allocated = try dynamic.alloc(routeClass)
        let routeSelector = NSSelectorFromString("initWithGeoWaypointRoute:initializerData:")
        guard ObjCMatchesMethodSignature(allocated, routeSelector, "@", ["@", "@"]),
            let route = ObjCSendIdId(allocated, routeSelector, waypointRoute, data) as? NSObject
        else { throw PlatformError.fetchFailed("Native composed route ABI is unavailable.") }
        guard let distance = try measurement(route, selector: "distance"),
            let duration = try NativeProperty.value(route, key: "expectedTime") as? NSNumber,
            duration.doubleValue.isFinite, duration.doubleValue >= 0,
            let nativeSteps = dynamic.sendObject(route, selector: "steps") as? [AnyObject]
        else { throw PlatformError.fetchFailed("Native composed route is missing required measurements.") }
        let steps = try nativeSteps.map { step -> MapRouteStepSnapshot in
            guard let meters = try measurement(step, selector: "distance"),
                let seconds = try measurement(step, selector: "travelTime")
            else { throw PlatformError.fetchFailed("Native route step is missing required measurements.") }
            let instruction =
                text(step, selector: "instructionStringsForListView")
                ?? text(step, selector: "normalInstructionStringsForSignView")
            return MapRouteStepSnapshot(
                instruction: instruction, distanceMeters: meters, durationSeconds: seconds,
                maneuver: dynamic.stringValue(from: step, selectors: ["maneuverDescription"]),
                roadName: dynamic.stringValue(from: step, selectors: ["maneuverRoadName"]))
        }
        var geometryError: NSError?
        let nativePoints = ObjCReadTripleDoublePoints(route, &geometryError)
        if let geometryError, geometryError.code != 1 {
            throw PlatformError.fetchFailed(
                "Native route geometry could not be decoded: \(geometryError.localizedDescription)")
        }
        let geometry = try RouteGeometryDecoder.decode(nativePoints)
        return MapRouteSnapshot(
            origin: origin, destination: destination, transportType: transportType, distanceMeters: distance,
            durationSeconds: duration.doubleValue, steps: steps, geometry: geometry)
    }

    private static func measurement(_ value: AnyObject, selector: String) throws -> Double? {
        guard let object = value as? NSObject else { return nil }
        let value = try NativeProperty.value(object, key: selector) as? NSNumber
        guard let number = value?.doubleValue, number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func text(_ step: AnyObject, selector: String) -> String? {
        let dynamic = DynamicRuntime.shared
        guard let strings = dynamic.sendObject(step, selector: selector) as? [AnyObject] else { return nil }
        // These are alternative renderings, not consecutive instructions. Choose the first complete one.
        for string in strings {
            if let text = dynamic.sendObject(string, selector: "stringWithDefaultOptions") as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return text
            }
        }
        return nil
    }
}
