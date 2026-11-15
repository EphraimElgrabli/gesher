import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// GeoServices request type 1 is a fresh route. Callback ABI is waypoints/request/response/error/directionsError.
final class DirectionsClient {
    let runtime: MapsRuntime
    init(runtime: MapsRuntime) { self.runtime = runtime }

    func route(
        from start: MapPlaceSnapshot, to end: MapPlaceSnapshot, transportType: String, timepoint: MapTimepoint?
    ) throws -> MapRouteSnapshot {
        let dynamic = DynamicRuntime.shared
        let service = try runtime.sharedDirectionsService()
        let params = try dynamic.allocInit("GEODirectionsServiceRequestParameters")
        let mapService = try runtime.sharedMapService()
        let traits = try dynamic.requireObject(mapService, selector: "defaultTraits")
        try dynamic.sendVoidId(params, selector: "setTraits:", argument: traits)
        try dynamic.sendVoidId(
            params, selector: "setWaypoints:", argument: [waypoint(start), waypoint(end)] as NSArray)
        try dynamic.sendVoidId(params, selector: "setCommonOptions:", argument: dynamic.allocInit("GEOCommonOptions"))
        let attributesClass = try dynamic.requireClass("GEORouteAttributes")
        let attributes = try dynamic.requireObject(attributesClass, selector: "defaultRouteAttributes")
        try dynamic.sendVoidId(params, selector: "setRouteAttributes:", argument: attributes)
        try dynamic.sendVoidInteger(params, selector: "setRequestType:", value: 1)
        try dynamic.sendVoidInteger(params, selector: "setMaxRouteCount:", value: 1)
        let modes = ["automobile": 0, "walking": 2, "transit": 1, "bicycle": 3]
        try dynamic.sendVoidInteger(params, selector: "setTransportType:", value: modes[transportType]!)
        try dynamic.sendVoidInteger(attributes, selector: "setMainTransportType:", value: modes[transportType]!)
        if let timepoint { try Self.setTimepoint(timepoint, on: attributes) }
        let selector = NSSelectorFromString("requestDirections:handler:")
        guard service.responds(to: selector) else {
            throw PlatformError.missingSelector(
                className: "GEODirectionsService", selector: "requestDirections:handler:")
        }
        let state = RouteReply()
        let handler: @convention(block) (AnyObject?, AnyObject?, AnyObject?, NSError?, AnyObject?) -> Void = {
            waypoints, nativeRequest, response, error, _ in
            state.finish(waypoints: waypoints, request: nativeRequest, response: response, error: error)
        }
        guard let request = ObjCSendIdId(service, selector, params, handler as AnyObject) as AnyObject? else {
            throw PlatformError.fetchFailed("Native directions request could not be started.")
        }
        let deadline = Date().addingTimeInterval(15)
        while !state.snapshot().done && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let reply = state.snapshot()
        guard reply.done else {
            try dynamic.sendVoid(request, selector: "cancel")
            throw PlatformError.fetchFailed("Native directions request timed out.")
        }
        if let error = reply.error {
            throw NativeDirectionsError(native: error, transportType: transportType)
        }
        if transportType == "transit", let response = reply.response,
            let suggestions = dynamic.sendObject(response, selector: "suggestedRoutes") as? [AnyObject],
            let selected = suggestions.first,
            let fields = dynamic.sendObject(selected, selector: "dictionaryRepresentation") as? [String: Any]
        {
            return try TransitRouteDecoder.decode(fields, origin: start, destination: end)
        }
        guard let response = reply.response else {
            throw PlatformError.fetchFailed("Native directions reply has no response object.")
        }
        if let object = response as? NSObject,
            let count = try NativeProperty.value(object, key: "waypointRoutesCount") as? NSNumber,
            count.intValue == 0
        {
            throw PlatformError.routeUnavailable(
                "Native service returned zero waypoint routes for these endpoints and transport mode.")
        }
        guard let routes = dynamic.sendObject(response, selector: "waypointRoutes") as? [AnyObject]
        else {
            throw PlatformError.fetchFailed("Native directions reply is malformed: missing routes collection.")
        }
        guard let waypointRoute = routes.first else {
            throw PlatformError.routeUnavailable(
                "No native \(transportType) route exists for these endpoints. Try a supported mode or another pair of points."
            )
        }
        guard let legs = dynamic.sendObject(waypointRoute, selector: "routeLegs") as? [AnyObject] else {
            throw PlatformError.fetchFailed("Native directions reply is malformed: missing route legs collection.")
        }
        guard !legs.isEmpty else {
            throw PlatformError.routeUnavailable(
                "No native \(transportType) route legs are available for these endpoints.")
        }
        return try ComposedRouteDecoder.decode(
            waypointRoute: waypointRoute, response: response, waypoints: reply.waypoints,
            attributes: attributes, origin: start, destination: end, transportType: transportType)
    }

    /// `-[GEORouteAttributes setTimepoint:]` takes `struct GEOTimepoint { double currentUserTime;
    /// double time; int type; has-bits }` (24 bytes). Absolute times are seconds since 2001.
    /// On arm64 a composite larger than 16 bytes is passed by reference, so a pointer to the
    /// struct bytes is the argument. The selector's type encoding is checked first.
    static func setTimepoint(_ timepoint: MapTimepoint, on attributes: AnyObject) throws {
        let selector = NSSelectorFromString("setTimepoint:")
        guard let method = class_getInstanceMethod(object_getClass(attributes), selector),
            let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }),
            encoding.contains("{GEOTimepoint=ddi{?=b1b1b1}}")
        else { throw PlatformError.missingSelector(className: "GEORouteAttributes", selector: "setTimepoint:") }
        #if arch(arm64)
            var bytes = [UInt8](repeating: 0, count: 24)
            bytes.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: Date().timeIntervalSinceReferenceDate, toByteOffset: 0, as: Double.self)
                raw.storeBytes(of: timepoint.date.timeIntervalSinceReferenceDate, toByteOffset: 8, as: Double.self)
                raw.storeBytes(of: timepoint.kind.rawValue, toByteOffset: 16, as: Int32.self)
                raw.storeBytes(of: UInt8(0b111), toByteOffset: 20, as: UInt8.self)
            }
            typealias Setter = @convention(c) (AnyObject, Selector, UnsafeRawPointer) -> Void
            let send = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: Setter.self)
            bytes.withUnsafeBytes { send(attributes, selector, $0.baseAddress!) }
        #else
            throw PlatformError.unsupportedPrivateAPI(
                selector: "setTimepoint:", reason: "Departure and arrival times need an arm64 Mac.")
        #endif
    }

    private func waypoint(_ place: MapPlaceSnapshot) throws -> AnyObject {
        let waypointClass: AnyClass = try DynamicRuntime.shared.requireClass("GEOComposedWaypoint")
        let selector = NSSelectorFromString("initWithLocation:isCurrentLocation:")
        let location = try runtime.location(place.coordinate)
        guard let allocated = ObjCSendId(waypointClass, NSSelectorFromString("alloc")) as AnyObject?,
            ObjCMatchesMethodSignature(allocated, selector, "@", ["@", "Bc"])
        else {
            throw PlatformError.missingSelector(
                className: "GEOComposedWaypoint", selector: "initWithLocation:isCurrentLocation:")
        }
        typealias WaypointInit = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> AnyObject?
        let send = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: WaypointInit.self)
        guard let waypoint = send(allocated, selector, location, false) else {
            throw PlatformError.storeInitializationFailed("Cannot initialize native waypoint.")
        }
        return waypoint
    }
}

private final class RouteReply {
    private let lock = NSLock()
    private var done = false
    private var waypoints: AnyObject?
    private var request: AnyObject?
    private var response: AnyObject?
    private var error: NSError?
    func finish(waypoints: AnyObject?, request: AnyObject?, response: AnyObject?, error: NSError?) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        self.waypoints = waypoints; self.request = request; self.response = response; self.error = error; done = true
    }
    func snapshot() -> (done: Bool, waypoints: AnyObject?, request: AnyObject?, response: AnyObject?, error: NSError?) {
        lock.lock(); defer { lock.unlock() }
        return (done, waypoints, request, response, error)
    }
}
