import GesherPlatform
import CoreLocation
import Foundation
import ObjCRuntimeSupport

public final class WeatherRuntime: @unchecked Sendable {
    private let loader = FrameworkLoader()
    private let runtime = DynamicRuntime.shared

    private let weatherFoundationCandidates = [
        "/System/Library/PrivateFrameworks/WeatherFoundation.framework/WeatherFoundation"
    ]
    private let weatherCoreCandidates = [
        "/System/Library/PrivateFrameworks/WeatherCore.framework/WeatherCore"
    ]
    private let geoServicesCandidates = [
        "/System/Library/PrivateFrameworks/GeoServices.framework/GeoServices"
    ]

    private(set) var loaded = false

    public init() {}

    public func load() throws {
        guard !loaded else { return }
        try loader.loadFirst(from: weatherFoundationCandidates)
        _ = loader.loadOptional(from: weatherCoreCandidates)
        _ = loader.loadOptional(from: geoServicesCandidates)
        loaded = true
    }

    public func makeWeatherStoreService() throws -> AnyObject {
        try load()
        return try runtime.allocInit("WFWeatherStoreService")
    }

    public func makeWFLocation(
        name: String,
        latitude: Double,
        longitude: Double,
        country: String? = nil,
        timeZoneIdentifier: String? = nil
    ) throws -> AnyObject {
        try load()
        let wfLoc = try runtime.allocInit("WFLocation")
        let clLoc = CLLocation(latitude: latitude, longitude: longitude)

        let setGeoSel = NSSelectorFromString("setGeoLocation:")
        _ = try NativeProperty.selector(wfLoc, "setGeoLocation:", returns: "v", arguments: ["@#"])
        ObjCSendVoidId(wfLoc, setGeoSel, clLoc)

        let setDisplaySel = NSSelectorFromString("setDisplayName:")
        if wfLoc.responds(to: setDisplaySel) {
            ObjCSendVoidId(wfLoc, setDisplaySel, name as NSString)
        }

        let setCitySel = NSSelectorFromString("setCity:")
        if wfLoc.responds(to: setCitySel) {
            ObjCSendVoidId(wfLoc, setCitySel, name as NSString)
        }

        if let country, !country.isEmpty {
            let setCountrySel = NSSelectorFromString("setCountryAbbreviation:")
            if wfLoc.responds(to: setCountrySel) {
                ObjCSendVoidId(wfLoc, setCountrySel, country as NSString)
            }
        }

        if let timeZoneIdentifier, let tz = TimeZone(identifier: timeZoneIdentifier) {
            let setTzSel = NSSelectorFromString("setTimeZone:")
            if wfLoc.responds(to: setTzSel) {
                ObjCSendVoidId(wfLoc, setTzSel, tz as NSTimeZone)
            }
        }

        return wfLoc
    }

    /// The top-ranked native geocoding result. Callers echo the resolved name and country back.
    public func geocodeQuery(_ query: String) throws -> WeatherSavedLocationSnapshot {
        guard let location = try geocodeCandidates(query).first else {
            throw AgentError(
                code: "not_found", message: "No place found for '\(query)'.",
                hint: "Add a country or region (e.g. 'Springfield, IL'), or pass 'latitude,longitude'.")
        }
        return location
    }

    public func geocodeCandidates(_ query: String) throws -> [WeatherSavedLocationSnapshot] {
        try load()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlatformError.invalidArgument("Location query cannot be empty.")
        }

        let serviceClass: AnyClass = try runtime.requireClass("GEOMapService")
        let sharedSel = NSSelectorFromString("sharedService")
        guard (serviceClass as AnyObject).responds(to: sharedSel),
            let service = ObjCSendId(serviceClass, sharedSel) as AnyObject?
        else {
            throw PlatformError.storeInitializationFailed("Could not obtain GEOMapService.sharedService")
        }

        let traits = try DynamicRuntime.shared.requireObject(service, selector: "defaultTraits")
        let ticketSel = NSSelectorFromString("ticketForSearchQuery:completionItem:retainedSearch:maxResults:traits:")
        guard service.responds(to: ticketSel) else {
            throw PlatformError.missingSelector(
                className: "GEOMapService",
                selector: "ticketForSearchQuery:completionItem:retainedSearch:maxResults:traits:"
            )
        }

        typealias TicketFunc =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?, UInt32, AnyObject?) -> AnyObject?
        let tf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: TicketFunc.self)
        guard let ticket = tf(service, ticketSel, trimmed as NSString, nil, nil, 10, traits) else {
            throw PlatformError.fetchFailed("Could not create geocode ticket for query: \(trimmed)")
        }

        return try submitGeocodeTicket(ticket, fallbackName: trimmed)
    }

    /// The ISO country code of the place at a coordinate (native reverse geocoding), or nil.
    public func reverseGeocodeCountry(latitude: Double, longitude: Double) throws -> String? {
        try reverseGeocodeCandidates(latitude: latitude, longitude: longitude).lazy.compactMap(\.country).first
    }

    /// The best named place at a coordinate (native reverse geocoding), or nil.
    public func reverseGeocodePlace(latitude: Double, longitude: Double) throws -> WeatherSavedLocationSnapshot? {
        try reverseGeocodeCandidates(latitude: latitude, longitude: longitude).first { !$0.name.isEmpty }
    }

    private func reverseGeocodeCandidates(latitude: Double, longitude: Double) throws
        -> [WeatherSavedLocationSnapshot]
    {
        try load()
        let serviceClass: AnyClass = try runtime.requireClass("GEOMapService")
        guard let service = ObjCSendId(serviceClass, NSSelectorFromString("sharedService")) as AnyObject? else {
            throw PlatformError.storeInitializationFailed("Could not obtain GEOMapService.sharedService")
        }
        let traits = try DynamicRuntime.shared.requireObject(service, selector: "defaultTraits")
        let selectorName = "ticketForReverseGeocodeCoordinate:shiftLocationsIfNeeded:traits:"
        let ticketSel = NSSelectorFromString(selectorName)
        guard service.responds(to: ticketSel) else {
            throw PlatformError.missingSelector(className: "GEOMapService", selector: selectorName)
        }
        typealias TicketFunc =
            @convention(c) (AnyObject, Selector, CLLocationCoordinate2D, Bool, AnyObject?) -> AnyObject?
        let tf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: TicketFunc.self)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard let ticket = tf(service, ticketSel, coordinate, true, traits) else {
            throw PlatformError.fetchFailed("Could not create a reverse geocode ticket.")
        }
        return try submitGeocodeTicket(ticket, fallbackName: "")
    }

    private func submitGeocodeTicket(_ ticket: AnyObject, fallbackName trimmed: String) throws
        -> [WeatherSavedLocationSnapshot]
    {
        let submitSel = NSSelectorFromString("submitWithHandler:networkActivity:")
        guard ticket.responds(to: submitSel) else {
            throw PlatformError.missingSelector(
                className: "GEOMapServiceTicket",
                selector: "submitWithHandler:networkActivity:"
            )
        }

        let reply = NativeServiceReply()
        typealias Handler = @convention(block) (AnyObject?, AnyObject?) -> Void
        let handler: Handler = { reply.complete(value: $0, error: $1) }

        typealias SubmitFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
        let sf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: SubmitFunc.self)
        sf(ticket, submitSel, handler as AnyObject, nil)

        guard let items = try reply.wait() as? [AnyObject] else {
            throw PlatformError.fetchFailed("Native geocoding response has no result collection.")
        }
        return try items.map { item in
            let name = stringValue(from: item, selectors: ["name"]) ?? trimmed
            let coordSel = try NativeProperty.coordinateSelector(item)
            typealias CoordFunc = @convention(c) (AnyObject, Selector) -> CLLocationCoordinate2D
            let cf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: CoordFunc.self)
            let clCoord = cf(item, coordSel)
            guard clCoord.latitude.isFinite, clCoord.longitude.isFinite,
                (-90.0...90.0).contains(clCoord.latitude), (-180.0...180.0).contains(clCoord.longitude)
            else {
                throw PlatformError.fetchFailed("Location has invalid native coordinates.")
            }
            let lat = clCoord.latitude
            let lon = clCoord.longitude

            let addrDict = objectValue(from: item, selectors: ["addressDictionary"]) as? [String: Any]
            let countryCode = addrDict?["CountryCode"] as? String
            let tzObj = objectValue(from: item, selectors: ["timezone"]) as? TimeZone

            let id = String(format: "LocationID:%.4f:%.4f", lat, lon)
            return WeatherSavedLocationSnapshot(
                id: id,
                identifierAvailability: "derived_coordinates_not_favorite_id",
                name: name,
                preciseName: name,
                country: countryCode,
                latitude: lat,
                longitude: lon,
                timeZone: tzObj?.identifier
            )
        }
    }

    public func objectIDString(from object: AnyObject) -> String {
        runtime.objectIDString(from: object)
    }

    public func objectValue(from object: AnyObject, selectors: [String]) -> AnyObject? {
        runtime.objectValue(from: object, selectors: selectors)
    }

    public func stringValue(from object: AnyObject, selectors: [String]) -> String? {
        runtime.stringValue(from: object, selectors: selectors)
    }

    public func intValue(from object: AnyObject, selectors: [String]) -> Int? {
        runtime.intValue(from: object, selectors: selectors)
    }

    public func doubleValue(from object: AnyObject, selectors: [String]) -> Double? {
        runtime.doubleValue(from: object, selectors: selectors)
    }

    public func boolValue(from object: AnyObject, selectors: [String]) -> Bool? {
        runtime.boolValue(from: object, selectors: selectors)
    }

    public func dateStringValue(from object: AnyObject, selectors: [String]) -> String? {
        runtime.dateStringValue(from: object, selectors: selectors)
    }

    public func objectArray(_ value: Any?) -> [AnyObject]? {
        runtime.objectArray(value)
    }
}
