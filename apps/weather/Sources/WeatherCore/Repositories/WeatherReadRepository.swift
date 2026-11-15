import GesherPlatform
import Foundation
import ObjCRuntimeSupport

public final class WeatherReadRepository: @unchecked Sendable {
    let runtime: WeatherRuntime
    /// Names coordinates and finds their time zone by native reverse geocoding (off in tests).
    let describeCoordinates: Bool

    public init(runtime: WeatherRuntime, describeCoordinates: Bool = true) {
        self.runtime = runtime
        self.describeCoordinates = describeCoordinates
    }

    public func fetchCurrentWeather(at loc: WeatherSavedLocationSnapshot) throws -> CurrentWeatherSnapshot {
        let wfLoc = try runtime.makeWFLocation(
            name: loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            country: loc.country,
            timeZoneIdentifier: loc.timeZone
        )
        let store = try runtime.makeWeatherStoreService()
        let sel = NSSelectorFromString("forecastForLocation:locale:onDate:requestIdentifier:options:completionHandler:")
        guard store.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: "WFWeatherStoreService",
                selector: "forecastForLocation:locale:onDate:requestIdentifier:options:completionHandler:"
            )
        }

        let reply = NativeServiceReply()
        typealias CompletionBlock = @convention(block) (AnyObject?, AnyObject?) -> Void
        let block: CompletionBlock = { reply.complete(value: $0, error: $1) }

        typealias CurFn =
            @convention(c) (
                AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject, AnyObject?, AnyObject
            ) -> Void
        let fn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: CurFn.self)
        fn(
            store,
            sel,
            wfLoc,
            NSLocale.current as NSLocale,
            Date() as NSDate,
            UUID() as NSUUID,
            nil,
            block as AnyObject
        )

        guard let resp = try reply.wait() as? NSObject else {
            throw PlatformError.fetchFailed("Empty weather forecast response.")
        }

        let forecastSel = NSSelectorFromString("forecast")
        let conditionsObj: NSObject? = try {
            if resp.responds(to: forecastSel),
                let val = resp.perform(forecastSel)?.takeUnretainedValue() as? NSObject
            {
                return val
            }
            if resp.responds(to: NSSelectorFromString("forecast")),
                let val = try NativeProperty.value(resp, key: "forecast") as? NSObject
            {
                return val
            }
            return nil
        }()

        guard let conditions = conditionsObj else {
            throw PlatformError.fetchFailed("Empty weather forecast response.")
        }

        return try parseCurrentConditions(conditions, location: loc)
    }

    public func fetchHourlyForecast(at loc: WeatherSavedLocationSnapshot, limit: Int = 24) throws
        -> [HourlyForecastSnapshot]
    {
        guard limit > 0 else {
            throw PlatformError.invalidArgument("Limit must be greater than 0.")
        }
        let wfLoc = try runtime.makeWFLocation(
            name: loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            country: loc.country,
            timeZoneIdentifier: loc.timeZone
        )
        let store = try runtime.makeWeatherStoreService()
        let sel = NSSelectorFromString("hourlyForecastForLocation:locale:requestIdentifier:completionHandler:")
        guard store.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: "WFWeatherStoreService",
                selector: "hourlyForecastForLocation:locale:requestIdentifier:completionHandler:"
            )
        }

        let rawList = try invokeAggregateForecast(store: store, selector: sel, wfLocation: wfLoc)
        return try Array(rawList.prefix(limit)).map { try parseHourlyConditions($0) }
    }

    public func fetchDailyForecast(at loc: WeatherSavedLocationSnapshot, limit: Int = 10) throws
        -> [DailyForecastSnapshot]
    {
        guard limit > 0 else {
            throw PlatformError.invalidArgument("Limit must be greater than 0.")
        }
        let wfLoc = try runtime.makeWFLocation(
            name: loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            country: loc.country,
            timeZoneIdentifier: loc.timeZone
        )
        let store = try runtime.makeWeatherStoreService()
        let sel = NSSelectorFromString("dailyForecastForLocation:locale:requestIdentifier:completionHandler:")
        guard store.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: "WFWeatherStoreService",
                selector: "dailyForecastForLocation:locale:requestIdentifier:completionHandler:"
            )
        }

        let rawList = try invokeAggregateForecast(store: store, selector: sel, wfLocation: wfLoc)
        return try Array(rawList.prefix(limit)).map { try parseDailyConditions($0) }
    }

    public func fetchAirQuality(at loc: WeatherSavedLocationSnapshot) throws -> AirQualitySnapshot {
        // The air-quality service rejects requests without the place's country code.
        let country = try loc.country ?? runtime.reverseGeocodeCountry(latitude: loc.latitude, longitude: loc.longitude)
        let wfLoc = try runtime.makeWFLocation(
            name: loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            country: country,
            timeZoneIdentifier: loc.timeZone
        )
        let store = try runtime.makeWeatherStoreService()
        let sel = NSSelectorFromString("airQualityForLocation:locale:requestIdentifier:options:completionHandler:")
        guard store.responds(to: sel) else {
            throw PlatformError.missingSelector(
                className: "WFWeatherStoreService",
                selector: "airQualityForLocation:locale:requestIdentifier:options:completionHandler:"
            )
        }

        let reply = NativeServiceReply()
        typealias CompletionBlock = @convention(block) (AnyObject?, AnyObject?) -> Void
        let block: CompletionBlock = { reply.complete(value: $0, error: $1) }

        typealias AQFn =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject?, AnyObject) -> Void
        let fn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: AQFn.self)
        fn(store, sel, wfLoc, NSLocale.current as NSLocale, UUID() as NSUUID, nil, block as AnyObject)

        guard let resp = try reply.wait() as? NSObject else {
            throw PlatformError.fetchFailed("Air quality data is not available for " + loc.name + ".")
        }

        let aqSel = NSSelectorFromString("airQualityConditions")
        let aqObj: NSObject? = try {
            if resp.responds(to: aqSel),
                let val = resp.perform(aqSel)?.takeUnretainedValue() as? NSObject
            {
                return val
            }
            if resp.responds(to: NSSelectorFromString("airQualityConditions")),
                let val = try NativeProperty.value(resp, key: "airQualityConditions") as? NSObject
            {
                return val
            }
            return nil
        }()

        guard let aq = aqObj else {
            if let error = try? NativeProperty.value(resp, key: "error") as? NSError {
                // WeatherFoundation error 5: the provider does not serve this place.
                throw AgentError(
                    code: "not_available",
                    message:
                        "Apple's air-quality service has no data for \(loc.name)\(country.map { " (\($0))" } ?? "")"
                        + ": \(error.localizedDescription)",
                    hint: "Air quality is not offered for every country; retrying will not help.")
            }
            throw PlatformError.fetchFailed("Air quality data is not available for " + loc.name + ".")
        }

        func value(_ object: NSObject, _ key: String) throws -> AnyObject? {
            try NativeProperty.value(object, key: key)
        }
        let aqi =
            try (value(aq, "airQualityIndex") as? NSNumber)?.intValue
            ?? (value(aq, "currentCategoryIndex") as? NSNumber)?.intValue
        let scale = try value(aq, "currentScaleCategory") as? NSObject
        let category =
            try (value(aq, "localizedAirQualityCategory") as? String)
            ?? scale.flatMap { try value($0, "categoryName") as? String }
        let recommendation =
            try (value(aq, "localizedRecommendation") as? String)
            ?? scale.flatMap { try value($0, "recommendation") as? String }
        let scaleIdentifier = try value(aq, "scaleIdentifier") as? String
        let provider = try value(aq, "provider") as? String
        var pollutantName: String?
        var pollutantAmount: Double?
        var pollutantUnit: String?
        if let primary = try value(aq, "primaryPollutant") as? NSObject {
            pollutantName = try value(primary, "localizedName") as? String
            pollutantAmount = try (value(primary, "amount") as? NSNumber)?.doubleValue
            pollutantUnit = try value(primary, "unit") as? String
        }
        guard aqi != nil || category != nil else {
            throw PlatformError.fetchFailed("Native air-quality response has neither index nor category.")
        }

        return AirQualitySnapshot(
            locationName: loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            airQualityIndex: aqi,
            category: category,
            primaryPollutant: pollutantName,
            primaryPollutantAmount: pollutantAmount,
            primaryPollutantUnit: pollutantUnit,
            scaleIdentifier: scaleIdentifier,
            recommendation: recommendation,
            provider: provider
        )
    }

    // MARK: - Helpers

    private func invokeAggregateForecast(
        store: AnyObject,
        selector: Selector,
        wfLocation: AnyObject
    ) throws -> [NSObject] {
        let reply = NativeServiceReply()
        typealias CompletionBlock = @convention(block) (AnyObject?, AnyObject?) -> Void
        let block: CompletionBlock = { reply.complete(value: $0, error: $1) }

        typealias ForecastFn =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject) -> Void
        let fn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: ForecastFn.self)
        fn(store, selector, wfLocation, NSLocale.current as NSLocale, UUID() as NSUUID, block as AnyObject)

        return try Self.forecastCollection(try reply.wait())
    }

    static func forecastCollection(_ response: AnyObject?) throws -> [NSObject] {
        guard let resp = response as? NSObject,
            let forecasts = try NativeProperty.value(resp, key: "forecasts") as? [NSObject]
        else {
            throw PlatformError.fetchFailed("Native forecast response is missing its forecasts collection.")
        }
        return forecasts
    }
}
