import GesherPlatform
import Foundation
import ObjCRuntimeSupport

extension WeatherReadRepository {
    func componentDict(from conditions: NSObject) throws -> [String: Any] {
        let dictSel = NSSelectorFromString("dictionaryRepresentation")
        if conditions.responds(to: dictSel),
            let dict = try NativeProperty.value(conditions, key: "dictionaryRepresentation") as? [String: Any]
        {
            return dict
        }
        return [:]
    }

    func extractTemp(_ value: Any?) -> (celsius: Double, fahrenheit: Double)? {
        guard let obj = value as? NSObject else { return nil }
        let cSel = NSSelectorFromString("celsius")
        let fSel = NSSelectorFromString("fahrenheit")

        let cVal: Double? = {
            if obj.responds(to: cSel) {
                typealias DblFn = @convention(c) (AnyObject, Selector) -> Double
                let fn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: DblFn.self)
                return fn(obj, cSel)
            }
            return nil
        }()
        guard let c = cVal, c.isFinite else { return nil }

        let fVal: Double? = {
            if obj.responds(to: fSel) {
                typealias DblFn = @convention(c) (AnyObject, Selector) -> Double
                let fn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"), to: DblFn.self)
                return fn(obj, fSel)
            }
            return nil
        }()
        let f = (fVal != nil && fVal!.isFinite) ? fVal! : (c * 9.0 / 5.0 + 32.0)
        return (c, f)
    }

    func doubleComponent(_ dict: [String: Any], key: String) -> Double? {
        if let d = dict[key] as? Double { return d }
        if let n = dict[key] as? NSNumber { return n.doubleValue }
        return nil
    }

    func intComponent(_ dict: [String: Any], key: String) -> Int? {
        if let i = dict[key] as? Int { return i }
        if let n = dict[key] as? NSNumber { return n.intValue }
        return nil
    }

    func dateString(_ dict: [String: Any], key: String) -> String? {
        if let date = dict[key] as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        if let str = dict[key] as? String {
            return str
        }
        return nil
    }

    // WF codes are not the legacy Yahoo/TWC values used by the English label table.
    // The private framework supplies its own conversion; never reinterpret a raw WF code.
    func conditionDescription(for code: Int) -> String {
        guard let handle = dlopen(nil, RTLD_NOW),
            let symbol = dlsym(handle, "LegacyWeatherConditionCodeFromWFConditionCode")
        else {
            return "Unknown (native condition code \(code))"
        }
        typealias Convert = @convention(c) (Int) -> Int
        let legacyCode = unsafeBitCast(symbol, to: Convert.self)(code)
        return WeatherConditionCodeMapper.description(for: legacyCode)
    }

    func parseCurrentConditions(
        _ conditions: NSObject,
        location: WeatherSavedLocationSnapshot
    ) throws -> CurrentWeatherSnapshot {
        let dict = try componentDict(from: conditions)
        guard let temp = extractTemp(dict["WFWeatherTemperatureComponent"]) else {
            throw PlatformError.fetchFailed("Could not parse temperature from weather response.")
        }
        let feelsLike = extractTemp(dict["WFWeatherFeelsLikeTemperatureComponent"])?.celsius
        let high = extractTemp(dict["WFWeatherHighTemperatureComponent"])?.celsius
        let low = extractTemp(dict["WFWeatherLowTemperatureComponent"])?.celsius
        guard let code = intComponent(dict, key: "WFWeatherConditionComponent") else {
            throw PlatformError.fetchFailed("Native weather response is missing its condition code.")
        }
        let desc = conditionDescription(for: code)
        let humidity = doubleComponent(dict, key: "WFWeatherHumidityComponent")
        let windSpeed = doubleComponent(dict, key: "WFWeatherWindSpeedComponent")
        let windDir = doubleComponent(dict, key: "WFWeatherWindDirectionComponent")
        let uv = intComponent(dict, key: "WFWeatherUVIndexComponent")
        let vis = doubleComponent(dict, key: "WFWeatherVisibilityComponent")
        let pressure = doubleComponent(dict, key: "WFWeatherPressureComponent")
        let precip = doubleComponent(dict, key: "WFWeatherPrecipitationAmountComponent")
        let obsDate = dateString(dict, key: "WFWeatherForecastDateComponent")
        let provider = dict["WFWeatherDataProviderName"] as? String

        return CurrentWeatherSnapshot(
            locationName: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            temperatureCelsius: temp.celsius,
            temperatureFahrenheit: temp.fahrenheit,
            feelsLikeCelsius: feelsLike,
            highTemperatureCelsius: high,
            lowTemperatureCelsius: low,
            conditionCode: code,
            conditionDescription: desc,
            humidity: humidity,
            windSpeedKph: windSpeed,
            windDirectionDegrees: windDir,
            uvIndex: uv,
            visibilityKm: vis,
            pressureMb: pressure,
            precipitationAmountMm: precip,
            observationDate: obsDate,
            providerName: provider
        )
    }

    func parseHourlyConditions(_ conditions: NSObject) throws -> HourlyForecastSnapshot {
        let dict = try componentDict(from: conditions)
        guard let date = dateString(dict, key: "WFWeatherForecastDateComponent"), !date.isEmpty else {
            throw PlatformError.fetchFailed("Missing forecast date in hourly conditions.")
        }
        guard let temp = extractTemp(dict["WFWeatherTemperatureComponent"]) else {
            throw PlatformError.fetchFailed("Missing temperature in hourly conditions.")
        }
        guard let code = intComponent(dict, key: "WFWeatherConditionComponent") else {
            throw PlatformError.fetchFailed("Native weather response is missing its condition code.")
        }
        let desc = conditionDescription(for: code)
        let precipChance = doubleComponent(dict, key: "WFWeatherPrecipitationChanceComponent")
        let humidity = doubleComponent(dict, key: "WFWeatherHumidityComponent")
        let windSpeed = doubleComponent(dict, key: "WFWeatherWindSpeedComponent")
        let windDir = doubleComponent(dict, key: "WFWeatherWindDirectionComponent")
        let uv = intComponent(dict, key: "WFWeatherUVIndexComponent")

        return HourlyForecastSnapshot(
            date: date,
            temperatureCelsius: temp.celsius,
            temperatureFahrenheit: temp.fahrenheit,
            conditionCode: code,
            conditionDescription: desc,
            precipitationChance: precipChance,
            humidity: humidity,
            windSpeedKph: windSpeed,
            windDirectionDegrees: windDir,
            uvIndex: uv
        )
    }

    func parseDailyConditions(_ conditions: NSObject) throws -> DailyForecastSnapshot {
        let dict = try componentDict(from: conditions)
        guard let date = dateString(dict, key: "WFWeatherForecastDateComponent"), !date.isEmpty else {
            throw PlatformError.fetchFailed("Missing forecast date in daily conditions.")
        }
        guard let high = extractTemp(dict["WFWeatherHighTemperatureComponent"]) else {
            throw PlatformError.fetchFailed("Missing high temperature in daily conditions.")
        }
        guard let low = extractTemp(dict["WFWeatherLowTemperatureComponent"]) else {
            throw PlatformError.fetchFailed("Missing low temperature in daily conditions.")
        }
        guard let code = intComponent(dict, key: "WFWeatherConditionComponent") else {
            throw PlatformError.fetchFailed("Native weather response is missing its condition code.")
        }
        let desc = conditionDescription(for: code)
        let precipChance = doubleComponent(dict, key: "WFWeatherPrecipitationChanceComponent")
        let humidity = doubleComponent(dict, key: "WFWeatherHumidityComponent")
        let windSpeed = doubleComponent(dict, key: "WFWeatherWindSpeedComponent")
        let uv = intComponent(dict, key: "WFWeatherUVIndexComponent")

        return DailyForecastSnapshot(
            date: date,
            highTemperatureCelsius: high.celsius,
            highTemperatureFahrenheit: high.fahrenheit,
            lowTemperatureCelsius: low.celsius,
            lowTemperatureFahrenheit: low.fahrenheit,
            conditionCode: code,
            conditionDescription: desc,
            precipitationChance: precipChance,
            humidity: humidity,
            windSpeedKph: windSpeed,
            uvIndex: uv
        )
    }
}
