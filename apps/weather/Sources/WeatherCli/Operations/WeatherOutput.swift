import GesherPlatform
import Foundation
import WeatherCore

/// Agent-facing output models. They carry what a user asks about, in the requested units, with
/// local times; native codes, providers and duplicate unit fields stay out. Optional values the
/// service did not provide are omitted.

enum Units: String, Codable, Sendable {
    case metric, imperial

    func temperature(_ celsius: Double) -> Double { round1(self == .metric ? celsius : celsius * 9 / 5 + 32) }
    func speed(_ kph: Double) -> Double { round1(self == .metric ? kph : kph / 1.609344) }
    func distance(_ km: Double) -> Double { round1(self == .metric ? km : km / 1.609344) }
    func precipitation(_ mm: Double) -> Double { self == .metric ? round1(mm) : (mm / 25.4 * 100).rounded() / 100 }
    func pressure(_ hPa: Double) -> Double { self == .metric ? round1(hPa) : (hPa * 0.02953 * 100).rounded() / 100 }

    var temperatureUnit: String { self == .metric ? "°C" : "°F" }
    var speedUnit: String { self == .metric ? "km/h" : "mph" }
}

func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

/// The place a forecast was resolved to. Always returned so the caller can confirm it.
struct Place: Encodable, Sendable {
    let name: String
    let country: String?
    let latitude: Double
    let longitude: Double
    let timeZone: String?

    init(_ location: WeatherSavedLocationSnapshot) {
        name = location.name
        country = location.country
        latitude = (location.latitude * 10_000).rounded() / 10_000
        longitude = (location.longitude * 10_000).rounded() / 10_000
        timeZone = location.timeZone
    }

    var zone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? .current }
}

struct SavedLocation: Encodable, Sendable {
    let id: String
    let name: String
    let country: String?
    let latitude: Double
    let longitude: Double
    let timeZone: String?

    init(_ location: WeatherSavedLocationSnapshot) {
        id = location.id
        name = location.name
        country = location.country
        latitude = (location.latitude * 10_000).rounded() / 10_000
        longitude = (location.longitude * 10_000).rounded() / 10_000
        timeZone = location.timeZone
    }
}

struct CurrentOutput: Encodable, Sendable {
    let place: Place
    let units: Units
    let observedAt: String?
    let condition: String
    let temperature: Double
    let feelsLike: Double?
    let high: Double?
    let low: Double?
    let humidity: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let uvIndex: Int?
    let visibility: Double?
    let pressure: Double?
    let precipitation: Double?

    init(_ snapshot: CurrentWeatherSnapshot, place: Place, units: Units) {
        self.place = place
        self.units = units
        observedAt = snapshot.observationDate.flatMap(DateOutput.parse).map { DateOutput.iso($0, timeZone: place.zone) }
        condition = snapshot.conditionDescription
        temperature = units.temperature(snapshot.temperatureCelsius)
        feelsLike = snapshot.feelsLikeCelsius.map(units.temperature)
        high = snapshot.highTemperatureCelsius.map(units.temperature)
        low = snapshot.lowTemperatureCelsius.map(units.temperature)
        humidity = snapshot.humidity
        windSpeed = snapshot.windSpeedKph.map(units.speed)
        windDirection = snapshot.windDirectionDegrees
        uvIndex = snapshot.uvIndex
        visibility = snapshot.visibilityKm.map(units.distance)
        pressure = snapshot.pressureMb.map(units.pressure)
        precipitation = snapshot.precipitationAmountMm.map(units.precipitation)
    }
}

struct HourlyOutput: Encodable, Sendable {
    struct Hour: Encodable, Sendable {
        let time: String
        let condition: String
        let temperature: Double
        let precipitationChance: Double?
        let humidity: Double?
        let windSpeed: Double?
        let uvIndex: Int?
    }
    let place: Place
    let units: Units
    let hours: [Hour]
}

struct DailyOutput: Encodable, Sendable {
    struct Day: Encodable, Sendable {
        let date: String
        let condition: String
        let high: Double
        let low: Double
        let precipitationChance: Double?
        let humidity: Double?
        let windSpeed: Double?
        let uvIndex: Int?
    }
    let place: Place
    let units: Units
    let days: [Day]
}

struct AirQualityOutput: Encodable, Sendable {
    struct Pollutant: Encodable, Sendable {
        let name: String
        let amount: Double?
        let unit: String?
    }
    let place: Place
    let index: Int?
    let category: String?
    let primaryPollutant: Pollutant?
    let recommendation: String?
}

struct LocationsOutput: Encodable, Sendable {
    let locations: [SavedLocation]
}

struct SearchOutput: Encodable, Sendable {
    let results: [Place]
}

/// `--format pretty` renderers; JSON output never goes through these.
enum WeatherPretty {
    static func header(_ place: Place) -> String {
        place.name + (place.country.map { ", \($0)" } ?? "")
    }

    static func current(_ output: CurrentOutput) -> String {
        let t = output.units.temperatureUnit
        var lines = ["\(header(output.place)): \(output.temperature)\(t), \(output.condition)"]
        var details: [String] = []
        if let feels = output.feelsLike { details.append("feels \(feels)\(t)") }
        if let high = output.high, let low = output.low { details.append("high \(high)\(t) / low \(low)\(t)") }
        if let humidity = output.humidity { details.append("humidity \(Int(humidity))%") }
        if let wind = output.windSpeed { details.append("wind \(wind) \(output.units.speedUnit)") }
        if let uv = output.uvIndex { details.append("UV \(uv)") }
        if !details.isEmpty { lines.append("  " + details.joined(separator: " · ")) }
        return lines.joined(separator: "\n")
    }

    static func hourly(_ output: HourlyOutput) -> String {
        let t = output.units.temperatureUnit
        return
            ([header(output.place)]
            + output.hours.map { hour in
                let time = hour.time.dropFirst(11).prefix(5)
                let rain = hour.precipitationChance.map { " · rain \(Int($0))%" } ?? ""
                return "  \(time)  \(hour.temperature)\(t)  \(hour.condition)\(rain)"
            }).joined(separator: "\n")
    }

    static func daily(_ output: DailyOutput) -> String {
        let t = output.units.temperatureUnit
        return
            ([header(output.place)]
            + output.days.map { day in
                let rain = day.precipitationChance.map { " · rain \(Int($0))%" } ?? ""
                return "  \(day.date)  \(day.low)–\(day.high)\(t)  \(day.condition)\(rain)"
            }).joined(separator: "\n")
    }
}

struct AlertsOutput: Encodable, Sendable {
    struct Alert: Encodable, Sendable {
        let id: String
        let title: String
        let area: String?
        let source: String?
        let expires: String?
        let url: String?

        init(_ snapshot: WeatherAlertSnapshot, zone: TimeZone) {
            id = snapshot.id
            title = snapshot.title
            area = snapshot.area
            source = snapshot.source
            expires = snapshot.expiresAt.map { DateOutput.iso($0, timeZone: zone) }
            url = snapshot.url
        }
    }
    let place: Place
    let alerts: [Alert]
}

struct NextHourOutput: Encodable, Sendable {
    /// A run of consecutive minutes with a chance of precipitation.
    struct Period: Encodable, Sendable {
        let start: String
        let end: String
        /// Highest chance in the period, percent.
        let peakChance: Int
        /// Highest intensity in the period: mm/h (metric) or in/h (imperial).
        let peakIntensity: Double
    }
    struct Minute: Encodable, Sendable {
        let time: String
        let chance: Int
        let intensity: Double
    }
    let place: Place
    let units: Units
    let summary: String?
    /// True when any minute in the next hour has a chance of precipitation.
    let precipitation: Bool
    let periods: [Period]?
    /// Every minute of the next hour, only when asked for.
    let minutes: [Minute]?

    init(_ snapshot: NextHourSnapshot, place: Place, units: Units, everyMinute: Bool = false, now: Date = Date()) {
        self.place = place
        self.units = units
        summary = snapshot.summary
        let window = snapshot.minutes.filter {
            $0.date >= now.addingTimeInterval(-60) && $0.date < now.addingTimeInterval(3600)
        }
        func wet(_ minute: NextHourSnapshot.Minute) -> Bool { minute.chance > 0 || minute.intensity > 0 }
        var runs: [[NextHourSnapshot.Minute]] = []
        for minute in window {
            if wet(minute) {
                if let last = runs.last?.last, wet(last), minute.date.timeIntervalSince(last.date) <= 61 {
                    runs[runs.count - 1].append(minute)
                } else {
                    runs.append([minute])
                }
            } else if runs.last?.last.map(wet) == true {
                runs.append([])
            }
        }
        runs.removeAll { $0.isEmpty }
        precipitation = !runs.isEmpty
        let zone = place.zone
        periods =
            runs.isEmpty
            ? nil
            : runs.map { run in
                Period(
                    start: DateOutput.iso(run[0].date, timeZone: zone),
                    end: DateOutput.iso(run[run.count - 1].date.addingTimeInterval(60), timeZone: zone),
                    peakChance: Int(run.map(\.chance).max()!.rounded()),
                    peakIntensity: units.precipitation(run.map(\.intensity).max()!))
            }
        minutes =
            everyMinute
            ? window.map {
                Minute(
                    time: DateOutput.iso($0.date, timeZone: zone), chance: Int($0.chance.rounded()),
                    intensity: units.precipitation($0.intensity))
            } : nil
    }
}
