import GesherPlatform
import CoreLocation
import Foundation
import ObjCRuntimeSupport

public final class MapsReadRepository: @unchecked Sendable {
    private let runtime: MapsRuntime

    public init(runtime: MapsRuntime) {
        self.runtime = runtime
    }

    /// Ranked search. `near` is sent as the device location, as the Maps app does for "near me":
    /// it biases ranking without filtering. With a bias the service sometimes ranks a far-away
    /// namesake of a landmark first (seen: "Eiffel Tower" near the Louvre returned one in India),
    /// so the unbiased best match is also fetched and put first when it is closer to `near`.
    public func search(query: String, maxResults: Int = 10, near: MapCoordinateSnapshot? = nil) throws
        -> [MapPlaceSnapshot]
    {
        let biased = try rawSearch(query: query, maxResults: maxResults, near: near)
        guard let near, let global = try rawSearch(query: query, maxResults: 1, near: nil).first else {
            return biased
        }
        return Self.preferCloser(global, over: biased, to: near, limit: maxResults)
    }

    static func preferCloser(
        _ global: MapPlaceSnapshot, over biased: [MapPlaceSnapshot], to near: MapCoordinateSnapshot, limit: Int
    ) -> [MapPlaceSnapshot] {
        guard let first = biased.first else { return [global] }
        guard global.coordinate.distance(to: near) < first.coordinate.distance(to: near) else { return biased }
        return uniquePlaces([global] + biased, limit: limit)
    }

    private func rawSearch(query: String, maxResults: Int, near: MapCoordinateSnapshot?) throws
        -> [MapPlaceSnapshot]
    {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlatformError.invalidArgument("Search query cannot be empty.")
        }
        guard (1...100).contains(maxResults) else {
            throw PlatformError.invalidArgument("maxResults must be between 1 and 100.")
        }
        let service = try runtime.sharedMapService()
        // Copy: the default traits object must not keep one call's location for the next.
        let shared = try DynamicRuntime.shared.requireObject(service, selector: "defaultTraits")
        let traits = try DynamicRuntime.shared.requireObject(shared, selector: "copy")
        if let near {
            try DynamicRuntime.shared.sendVoidId(
                traits, selector: "setDeviceLocation:", argument: try runtime.location(near))
        }
        let ticketSel = NSSelectorFromString("ticketForSearchQuery:completionItem:retainedSearch:maxResults:traits:")
        guard service.responds(to: ticketSel) else {
            throw PlatformError.missingSelector(
                className: "GEOMapService",
                selector: "ticketForSearchQuery:completionItem:retainedSearch:maxResults:traits:")
        }

        typealias TicketFunc =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?, UInt32, AnyObject?) -> AnyObject?
        let tf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: TicketFunc.self)
        guard let ticket = tf(service, ticketSel, trimmed as NSString, nil, nil, UInt32(maxResults), traits) else {
            throw PlatformError.fetchFailed("Could not create ticket for search query: \(trimmed)")
        }

        let rawItems = try submitTicket(ticket)
        return Self.uniquePlaces(try rawItems.map { try parseMapItem($0) }, limit: maxResults)
    }

    static func uniquePlaces(_ places: [MapPlaceSnapshot], limit: Int) -> [MapPlaceSnapshot] {
        var seen = Set<String>()
        return Array(
            places.filter { place in
                let key =
                    place.id
                    ?? "\(place.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))|\(place.coordinate.latitude)|\(place.coordinate.longitude)"
                return seen.insert(key).inserted
            }.prefix(limit))
    }

    public func reverseGeocode(latitude: Double, longitude: Double) throws -> [MapPlaceSnapshot] {
        guard (-90.0...90.0).contains(latitude) else {
            throw PlatformError.invalidArgument("Latitude must be between -90 and 90.")
        }
        guard (-180.0...180.0).contains(longitude) else {
            throw PlatformError.invalidArgument("Longitude must be between -180 and 180.")
        }

        let service = try runtime.sharedMapService()
        let sel = NSSelectorFromString("ticketForReverseGeocodeCoordinate:shiftLocationsIfNeeded:traits:")
        guard service.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: "GEOMapService", selector: "ticketForReverseGeocodeCoordinate:shiftLocationsIfNeeded:traits:"
            )
        }

        typealias RevFunc = @convention(c) (AnyObject, Selector, CLLocationCoordinate2D, Bool, AnyObject?) -> AnyObject?
        let rf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: RevFunc.self)
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard let ticket = rf(service, sel, coord, false, nil) else {
            throw PlatformError.fetchFailed(
                "Could not create reverse geocode ticket for (\(latitude), \(longitude))")
        }

        let rawItems = try submitTicket(ticket)
        return try rawItems.map { try parseMapItem($0) }
    }

    public func route(
        origin: MapPlaceSnapshot, destination: MapPlaceSnapshot, transportType: String = "automobile",
        timepoint: MapTimepoint? = nil
    ) throws -> MapRouteSnapshot {
        guard ["automobile", "walking", "transit", "bicycle"].contains(transportType) else {
            throw PlatformError.invalidArgument("Transport type must be automobile, walking, transit, or bicycle.")
        }
        for point in [origin.coordinate, destination.coordinate] {
            guard point.latitude.isFinite, point.longitude.isFinite, (-90...90).contains(point.latitude),
                (-180...180).contains(point.longitude)
            else {
                throw PlatformError.invalidArgument("Route coordinates are outside valid ranges.")
            }
        }
        return try DirectionsClient(runtime: runtime).route(
            from: origin, to: destination, transportType: transportType, timepoint: timepoint)
    }

    /// Looks a place up by the `geo:<provider>:<muid>` id returned by search.
    public func place(id: String) throws -> MapPlaceSnapshot {
        guard let (provider, muid) = MapPlaceID.parse(id) else {
            throw PlatformError.invalidArgument("Place id must look like geo:<provider>:<muid>.")
        }
        let service = try runtime.sharedMapService()
        let traits = try DynamicRuntime.shared.requireObject(service, selector: "defaultTraits")
        let selector = NSSelectorFromString("ticketForMUIDs:resultProviderID:contentProvider:traits:")
        guard ObjCMatchesMethodSignature(service, selector, "@", ["@", "i", "@", "@"]) else {
            throw PlatformError.missingSelector(
                className: "GEOMapService", selector: "ticketForMUIDs:resultProviderID:contentProvider:traits:")
        }
        typealias TicketFunc =
            @convention(c) (AnyObject, Selector, AnyObject, Int32, AnyObject?, AnyObject?) -> AnyObject?
        let send = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: TicketFunc.self)
        guard let ticket = send(service, selector, [NSNumber(value: muid)] as NSArray, provider, nil, traits) else {
            throw PlatformError.fetchFailed("Could not create a place lookup for \(id).")
        }
        guard let item = try submitTicket(ticket).first else {
            throw PlatformError.objectNotFound(type: "place", id: id)
        }
        return try parseMapItem(item)
    }

    private func submitTicket(_ ticket: AnyObject) throws -> [AnyObject] {
        let submitSel = NSSelectorFromString("submitWithHandler:networkActivity:")
        guard ticket.responds(to: submitSel) else {
            throw PlatformError.missingSelector(
                className: "GEOMapServiceTicket", selector: "submitWithHandler:networkActivity:")
        }

        let reply = NativeServiceReply()
        typealias Handler = @convention(block) (AnyObject?, AnyObject?) -> Void
        let handler: Handler = { reply.complete(value: $0, error: $1) }

        typealias SubmitFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
        let sf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: SubmitFunc.self)
        sf(ticket, submitSel, handler as AnyObject, nil)

        guard let resultItems = try reply.wait() as? [AnyObject] else {
            throw PlatformError.fetchFailed("Search returned an invalid native response.")
        }
        return resultItems
    }

    /// One line: native lines can themselves contain line breaks.
    static func address(_ lines: [String]) -> String? {
        let parts = lines.flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func nativeIdentifier(provider: Int32, muid: UInt64) -> String? {
        guard muid != 0, provider > 0 else { return nil }
        return "geo:\(provider):\(muid)"
    }

    private func parseMapItem(_ item: AnyObject) throws -> MapPlaceSnapshot {
        let name = runtime.stringValue(from: item, selectors: ["name"]) ?? "Unknown Place"
        var id: String?
        if let identifier = runtime.objectValue(from: item, selectors: ["_identifier"]),
            identifier.responds(to: NSSelectorFromString("muid")),
            identifier.responds(to: NSSelectorFromString("resultProviderID"))
        {
            typealias MUID = @convention(c) (AnyObject, Selector) -> UInt64
            typealias Provider = @convention(c) (AnyObject, Selector) -> Int32
            let send = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")!
            let muid = unsafeBitCast(send, to: MUID.self)(identifier, NSSelectorFromString("muid"))
            let provider = unsafeBitCast(send, to: Provider.self)(identifier, NSSelectorFromString("resultProviderID"))
            id = Self.nativeIdentifier(provider: provider, muid: muid)
        }

        var formattedAddress: String? = nil
        let addrDict = runtime.objectValue(from: item, selectors: ["addressDictionary"]) as? [String: Any]
        if let lines = addrDict?["FormattedAddressLines"] as? [String] {
            formattedAddress = Self.address(lines)
        }

        let coordSel = try NativeProperty.coordinateSelector(item)
        typealias CoordFunc = @convention(c) (AnyObject, Selector) -> CLLocationCoordinate2D
        let cf = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: CoordFunc.self)
        let clCoord = cf(item, coordSel)
        guard clCoord.latitude.isFinite, clCoord.longitude.isFinite,
            (-90...90).contains(clCoord.latitude), (-180...180).contains(clCoord.longitude)
        else {
            throw PlatformError.fetchFailed("Place has invalid native coordinates.")
        }
        let coordinate = MapCoordinateSnapshot(latitude: clCoord.latitude, longitude: clCoord.longitude)

        let category = Self.categoryName(
            runtime.stringValue(from: item, selectors: ["_mapsCategoryId"]),
            poi: runtime.stringValue(from: item, selectors: ["_poiCategory", "poiCategory"]))
        let phone = runtime.stringValue(from: item, selectors: ["_telephone", "telephone"])
        let url = runtime.stringValue(from: item, selectors: ["_businessURL", "_webURL", "_url", "url"])
        let timeZone = (runtime.objectValue(from: item, selectors: ["timezone"]) as? TimeZone)?.identifier
        var ratingPercent: Double?
        var ratingCount: Int?
        let send = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")!
        let hasScore = NSSelectorFromString("_hasUserRatingScore")
        let score = NSSelectorFromString("_normalizedUserRatingScore")
        let samples = NSSelectorFromString("_sampleSizeForUserRatingScore")
        if ObjCMatchesMethodSignature(item, hasScore, "Bc", []), ObjCSendBool(item, hasScore),
            ObjCMatchesMethodSignature(item, score, "f", []), ObjCMatchesMethodSignature(item, samples, "I", [])
        {
            typealias FloatFunc = @convention(c) (AnyObject, Selector) -> Float
            typealias UIntFunc = @convention(c) (AnyObject, Selector) -> UInt32
            let value = Double(unsafeBitCast(send, to: FloatFunc.self)(item, score))
            let count = Int(unsafeBitCast(send, to: UIntFunc.self)(item, samples))
            if value.isFinite, (0...100).contains(value), count > 0 {
                ratingPercent = value
                ratingCount = count
            }
        }
        return MapPlaceSnapshot(
            id: id, name: name, formattedAddress: formattedAddress, coordinate: coordinate, category: category,
            phoneNumber: phone, url: url, timeZone: timeZone, hours: try hours(item), ratingPercent: ratingPercent,
            ratingCount: ratingCount)
    }

    /// `travel_and_leisure.museum.art_museum` -> "art museum"; `GEOPOICategoryCafe` -> "cafe".
    static func categoryName(_ mapsCategory: String?, poi: String?) -> String? {
        if let leaf = mapsCategory?.split(separator: ".").last, !leaf.isEmpty {
            return leaf.replacingOccurrences(of: "_", with: " ")
        }
        guard let poi, poi.hasPrefix("GEOPOICategory"), poi.count > "GEOPOICategory".count else { return poi }
        let name = poi.dropFirst("GEOPOICategory".count)
        return name.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result += " " }
            result += character.lowercased()
        }
    }

    /// Normalized local hours per weekday from `GEOBusinessHours.placeDailyNormalizedHours`.
    private func hours(_ item: AnyObject) throws -> [MapDailyHoursSnapshot]? {
        let dynamic = DynamicRuntime.shared
        guard let all = runtime.objectArray(runtime.objectValue(from: item, selectors: ["_businessHours"])),
            let business = all.first,
            let days = runtime.objectArray(dynamic.sendObject(business, selector: "placeDailyNormalizedHours"))
        else { return nil }
        let result = days.compactMap { day -> MapDailyHoursSnapshot? in
            guard let weekday = dynamic.intValue(from: day, selectors: ["weekday"]), (1...7).contains(weekday),
                let intervals = runtime.objectArray(dynamic.sendObject(day, selector: "localTimeIntervals"))
            else { return nil }
            let ranges = intervals.compactMap { interval -> ClosedRange<Double>? in
                guard let start = dynamic.doubleValue(from: interval, selectors: ["startTime"]),
                    let end = dynamic.doubleValue(from: interval, selectors: ["endTime"]), start.isFinite, end.isFinite,
                    end >= start
                else { return nil }
                return start...end
            }
            return MapDailyHoursSnapshot(weekday: weekday, intervals: ranges)
        }
        return result.isEmpty ? nil : result.sorted { $0.weekday < $1.weekday }
    }
}
