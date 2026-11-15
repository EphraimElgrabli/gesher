import GesherPlatform
import CoreLocation
import Foundation
import ObjCRuntimeSupport

public final class MapsRuntime: @unchecked Sendable {
    private let loader = FrameworkLoader()
    private let runtime = DynamicRuntime.shared

    private let frameworkCandidates = [
        "/System/Library/PrivateFrameworks/GeoServices.framework/GeoServices",
        "/System/Library/PrivateFrameworks/MapsSupport.framework/MapsSupport",
    ]

    private(set) var loaded = false

    public init() {}

    public func load() throws {
        guard !loaded else { return }
        try loader.loadFirst(from: frameworkCandidates)
        loaded = true
    }

    public func sharedMapService() throws -> AnyObject {
        try load()
        let serviceClass = try runtime.requireClass("GEOMapService")
        let sel = NSSelectorFromString("sharedService")
        guard (serviceClass as AnyObject).responds(to: sel),
            let service = ObjCSendId(serviceClass, sel) as AnyObject?
        else {
            throw PlatformError.storeInitializationFailed("Could not access GEOMapService.sharedService")
        }
        return service
    }

    public func sharedDirectionsService() throws -> AnyObject {
        try load()
        let serviceClass = try runtime.requireClass("GEODirectionsService")
        let sel = NSSelectorFromString("sharedService")
        guard (serviceClass as AnyObject).responds(to: sel),
            let service = ObjCSendId(serviceClass, sel) as AnyObject?
        else {
            throw PlatformError.storeInitializationFailed("Could not access GEODirectionsService.sharedService")
        }
        return service
    }

    /// A `GEOLocation` for a coordinate (search bias and route waypoints).
    func location(_ coordinate: MapCoordinateSnapshot) throws -> AnyObject {
        try load()
        let locationClass: AnyClass = try runtime.requireClass("GEOLocation")
        let selector = NSSelectorFromString("initWithLatitude:longitude:")
        guard let allocated = ObjCSendId(locationClass, NSSelectorFromString("alloc")) as AnyObject?,
            ObjCMatchesMethodSignature(allocated, selector, "@", ["d", "d"])
        else {
            throw PlatformError.missingSelector(className: "GEOLocation", selector: "initWithLatitude:longitude:")
        }
        typealias LocationInit = @convention(c) (AnyObject, Selector, Double, Double) -> AnyObject?
        let send = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: LocationInit.self)
        guard let location = send(allocated, selector, coordinate.latitude, coordinate.longitude) else {
            throw PlatformError.storeInitializationFailed("Cannot initialize a native location.")
        }
        return location
    }

    public func objectIDString(from object: AnyObject) -> String {
        runtime.objectIDString(from: object)
    }

    public func stringValue(from object: AnyObject, selectors: [String]) -> String? {
        runtime.stringValue(from: object, selectors: selectors)
    }

    public func objectArray(_ value: Any?) -> [AnyObject]? {
        runtime.objectArray(value)
    }

    public func objectValue(from object: AnyObject, selectors: [String]) -> AnyObject? {
        runtime.objectValue(from: object, selectors: selectors)
    }
}
