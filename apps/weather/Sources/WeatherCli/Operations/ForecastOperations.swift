import GesherKit
import GesherPlatform
import Foundation
import WeatherCore

private let placeParam = Param.string(
    "place", "City, address, saved location name, or 'lat,lon'. Default: your default place.", positional: true)
private let unitsParam = Param.choice("units", ["metric", "imperial"], "Units. Default: your locale.")

enum CurrentWeather: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String?
        var units: Units?
    }

    static let path = ["current"]
    static let summary = "Current conditions for a place."
    static let params = [placeParam, unitsParam]
    static let examples = ["current", "current Haifa", "current 'Tel Aviv' --units imperial", "current 32.08,34.78"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> CurrentOutput {
        let location = try context.place(input.place)
        let snapshot = try context.read.fetchCurrentWeather(at: location)
        return CurrentOutput(snapshot, place: Place(location), units: context.units(input.units))
    }

    static func pretty(_ output: CurrentOutput) -> String? { WeatherPretty.current(output) }
}

enum HourlyForecast: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String?
        var hours: Int
        var from: NaturalDate?
        var units: Units?
    }

    static let path = ["hourly"]
    static let summary = "Hour-by-hour forecast (temperature, rain chance, wind) for a place."
    static let params: [Param] = [
        placeParam,
        .integer("hours", "Number of hours to return.", default: 24, min: 1, max: 240),
        .date("from", "First hour to include, e.g. 'tomorrow 6:00'. Default: now."),
        unitsParam,
    ]
    static let examples = ["hourly Haifa --hours 6", "hourly --from 'tomorrow 6:00' --hours 12"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> HourlyOutput {
        let location = try context.place(input.place)
        let place = Place(location)
        let units = context.units(input.units)
        let start = input.from?.date ?? Date().addingTimeInterval(-3600)
        // Fetch enough hours to cover the requested window, then slice it.
        let lead = max(0, Int(start.timeIntervalSinceNow / 3600))
        let snapshots = try context.read.fetchHourlyForecast(at: location, limit: min(240, lead + input.hours + 1))
        let hours = snapshots.compactMap { snapshot -> HourlyOutput.Hour? in
            guard let date = DateOutput.parse(snapshot.date), date >= start else { return nil }
            return HourlyOutput.Hour(
                time: DateOutput.iso(date, timeZone: place.zone), condition: snapshot.conditionDescription,
                temperature: units.temperature(snapshot.temperatureCelsius),
                precipitationChance: snapshot.precipitationChance, humidity: snapshot.humidity,
                windSpeed: snapshot.windSpeedKph.map(units.speed), uvIndex: snapshot.uvIndex)
        }
        return HourlyOutput(place: place, units: units, hours: Array(hours.prefix(input.hours)))
    }

    static func pretty(_ output: HourlyOutput) -> String? { WeatherPretty.hourly(output) }
}

enum DailyForecast: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String?
        var days: Int
        var units: Units?
    }

    static let path = ["daily"]
    static let summary = "Day-by-day forecast (high, low, rain chance) for a place."
    static let params: [Param] = [
        placeParam,
        .integer("days", "Number of days to return, starting today.", default: 7, min: 1, max: 10),
        unitsParam,
    ]
    static let examples = ["daily", "daily Jerusalem --days 3"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> DailyOutput {
        let location = try context.place(input.place)
        let place = Place(location)
        let units = context.units(input.units)
        let days = try context.read.fetchDailyForecast(at: location, limit: input.days).map { snapshot in
            DailyOutput.Day(
                date: DateOutput.parse(snapshot.date).map { DateOutput.day($0, timeZone: place.zone) } ?? snapshot.date,
                condition: snapshot.conditionDescription, high: units.temperature(snapshot.highTemperatureCelsius),
                low: units.temperature(snapshot.lowTemperatureCelsius),
                precipitationChance: snapshot.precipitationChance, humidity: snapshot.humidity,
                windSpeed: snapshot.windSpeedKph.map(units.speed), uvIndex: snapshot.uvIndex)
        }
        return DailyOutput(place: place, units: units, days: days)
    }

    static func pretty(_ output: DailyOutput) -> String? { WeatherPretty.daily(output) }
}

enum AirQuality: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String?
    }

    static let path = ["air-quality"]
    static let summary = "Air quality index, category and main pollutant for a place."
    static let params = [placeParam]
    static let examples = ["air-quality", "air-quality Haifa"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> AirQualityOutput {
        let location = try context.place(input.place)
        let snapshot = try context.read.fetchAirQuality(at: location)
        return AirQualityOutput(
            place: Place(location), index: snapshot.airQualityIndex, category: snapshot.category,
            primaryPollutant: snapshot.primaryPollutant.map {
                .init(name: $0, amount: snapshot.primaryPollutantAmount, unit: snapshot.primaryPollutantUnit)
            },
            recommendation: snapshot.recommendation)
    }
}

enum WeatherAlerts: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String?
    }

    static let path = ["alerts"]
    static let summary =
        "Severe-weather alerts (warnings, watches) currently issued for a place, with source and expiry."
    static let params = [placeParam]
    static let examples = ["alerts", "alerts Paris"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> AlertsOutput {
        let location = try context.place(input.place)
        let place = Place(location)
        return AlertsOutput(
            place: place,
            alerts: try context.read.fetchAlerts(at: location).map { AlertsOutput.Alert($0, zone: place.zone) })
    }
}

enum NextHourPrecipitation: AgentOperation {
    struct Input: Decodable, Sendable {
        var place: String?
        var units: Units?
        var everyMinute: Bool
    }

    static let path = ["next-hour"]
    static let summary =
        "Rain or snow in the next hour, minute by minute (where Apple offers it): a summary and the wet periods."
    static let params: [Param] = [
        placeParam, unitsParam, .boolean("everyMinute", "Also list each of the next 60 minutes."),
    ]
    static let examples = ["next-hour", "next-hour London --units imperial", "next-hour --every-minute"]

    static func run(_ input: Input, _ context: WeatherContext) throws -> NextHourOutput {
        let location = try context.place(input.place)
        return NextHourOutput(
            try context.read.fetchNextHour(at: location), place: Place(location), units: context.units(input.units),
            everyMinute: input.everyMinute)
    }
}
