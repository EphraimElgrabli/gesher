import GesherPlatform
import Foundation

/// Severe-weather alerts and next-hour precipitation. Both come from WeatherFoundation's typed
/// aggregate request (`forecast:forLocation:locale:requestIdentifier:completionHandler:`), the
/// one the Weather app uses for its alert banner and next-hour chart.
extension WeatherReadRepository {
    /// WeatherFoundation forecast type bits (verified on macOS 27).
    enum ForecastType: UInt {
        case severeWeather = 1024
        case nextHourPrecipitation = 2048
    }

    /// Alerts currently issued for the place. An empty list means the service reported none; where
    /// Apple has no alert provider the list is empty too.
    public func fetchAlerts(at location: WeatherSavedLocationSnapshot) throws -> [WeatherAlertSnapshot] {
        let response = try fetchAggregate(at: location, types: [.severeWeather])
        guard let events = try NativeProperty.value(response, key: "severeWeatherEvents") as? [NSObject] else {
            throw PlatformError.fetchFailed("The weather service returned no alert collection for \(location.name).")
        }
        return try events.map(Self.parseAlert)
    }

    /// Next-hour precipitation, or `not_available` where Apple does not offer it.
    public func fetchNextHour(at location: WeatherSavedLocationSnapshot) throws -> NextHourSnapshot {
        let response = try fetchAggregate(at: location, types: [.nextHourPrecipitation])
        let native = try NativeProperty.value(response, key: "nextHourPrecipitation") as? NSObject
        guard let native, let snapshot = try Self.parseNextHour(native) else {
            throw AgentError(
                code: "not_available",
                message: "Apple Weather has no next-hour precipitation for \(location.name).",
                hint: "Next-hour precipitation covers only some countries; use hourly for the rain chance by hour.")
        }
        return snapshot
    }

    static func parseAlert(_ event: NSObject) throws -> WeatherAlertSnapshot {
        func string(_ key: String) throws -> String? {
            (try NativeProperty.value(event, key: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let id = try string("identifier"), let title = try string("eventDescription") else {
            throw PlatformError.fetchFailed("A severe-weather alert has no identifier or description.")
        }
        let url = try NativeProperty.value(event, key: "URL")
        return WeatherAlertSnapshot(
            id: id, title: title, area: try string("areaName"), source: try string("source"),
            expiresAt: try NativeProperty.value(event, key: "expirationDate") as? Date,
            url: (url as? URL)?.absoluteString ?? (url as? String))
    }

    /// Nil when the service sent no minutes (the place is not covered).
    static func parseNextHour(_ native: NSObject) throws -> NextHourSnapshot? {
        guard let rawMinutes = try NativeProperty.value(native, key: "minutes") as? [NSObject], !rawMinutes.isEmpty
        else { return nil }
        let minutes = try rawMinutes.map { minute -> NextHourSnapshot.Minute in
            guard let date = try NativeProperty.value(minute, key: "date") as? Date,
                let chance = (try NativeProperty.value(minute, key: "chance") as? NSNumber)?.doubleValue,
                let intensity = (try NativeProperty.value(minute, key: "intensity") as? NSNumber)?.doubleValue,
                chance.isFinite, intensity.isFinite
            else { throw PlatformError.fetchFailed("A next-hour precipitation minute is incomplete.") }
            return NextHourSnapshot.Minute(date: date, chance: chance, intensity: intensity)
        }
        var summary: String?
        if let description = try NativeProperty.value(native, key: "currentDescription") as? NSObject {
            // A template with unfilled {placeholders} is not shown.
            summary = ["longDescription", "longTemplate"].lazy
                .compactMap { try? NativeProperty.value(description, key: $0) as? String }
                .first { !$0.isEmpty && !$0.contains("{") }
        }
        return NextHourSnapshot(summary: summary, minutes: minutes)
    }

    private func fetchAggregate(at location: WeatherSavedLocationSnapshot, types: [ForecastType]) throws -> NSObject {
        let wfLocation = try runtime.makeWFLocation(
            name: location.name, latitude: location.latitude, longitude: location.longitude,
            country: location.country, timeZoneIdentifier: location.timeZone)
        let store = try runtime.makeWeatherStoreService()
        let name = "forecast:forLocation:locale:requestIdentifier:completionHandler:"
        let selector = NSSelectorFromString(name)
        guard store.responds(to: selector) else {
            throw PlatformError.missingSelector(className: "WFWeatherStoreService", selector: name)
        }
        let reply = NativeServiceReply()
        typealias Completion = @convention(block) (AnyObject?, AnyObject?) -> Void
        let block: Completion = { reply.complete(value: $0, error: $1) }
        typealias Function =
            @convention(c) (AnyObject, Selector, UInt, AnyObject, AnyObject, AnyObject, AnyObject) -> Void
        let function = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: Function.self)
        function(
            store, selector, types.reduce(0) { $0 | $1.rawValue }, wfLocation, NSLocale.current as NSLocale,
            UUID() as NSUUID, block as AnyObject)
        guard let response = try reply.wait() as? NSObject else {
            throw PlatformError.fetchFailed("Empty weather response for \(location.name).")
        }
        return response
    }
}
