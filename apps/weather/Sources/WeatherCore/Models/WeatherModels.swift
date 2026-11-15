import Foundation

public struct WeatherSavedLocationSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let identifierAvailability: String
    public let name: String
    public let preciseName: String?
    public let country: String?
    public let latitude: Double
    public let longitude: Double
    public let timeZone: String?

    public init(
        id: String,
        identifierAvailability: String = "native_favorite",
        name: String,
        preciseName: String? = nil,
        country: String? = nil,
        latitude: Double,
        longitude: Double,
        timeZone: String? = nil
    ) {
        self.id = id
        self.identifierAvailability = identifierAvailability
        self.name = name
        self.preciseName = preciseName
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
    }
}

public struct CurrentWeatherSnapshot: Codable, Equatable, Sendable {
    public let locationName: String
    public let latitude: Double
    public let longitude: Double
    public let temperatureCelsius: Double
    public let temperatureFahrenheit: Double
    public let feelsLikeCelsius: Double?
    public let highTemperatureCelsius: Double?
    public let lowTemperatureCelsius: Double?
    public let conditionCode: Int
    public let conditionDescription: String
    public let humidity: Double?
    public let windSpeedKph: Double?
    public let windDirectionDegrees: Double?
    public let uvIndex: Int?
    public let visibilityKm: Double?
    public let pressureMb: Double?
    public let precipitationAmountMm: Double?
    public let observationDate: String?
    public let providerName: String?

    public init(
        locationName: String,
        latitude: Double,
        longitude: Double,
        temperatureCelsius: Double,
        temperatureFahrenheit: Double,
        feelsLikeCelsius: Double?,
        highTemperatureCelsius: Double? = nil,
        lowTemperatureCelsius: Double? = nil,
        conditionCode: Int,
        conditionDescription: String,
        humidity: Double? = nil,
        windSpeedKph: Double? = nil,
        windDirectionDegrees: Double? = nil,
        uvIndex: Int? = nil,
        visibilityKm: Double? = nil,
        pressureMb: Double? = nil,
        precipitationAmountMm: Double? = nil,
        observationDate: String? = nil,
        providerName: String? = nil
    ) {
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.temperatureCelsius = temperatureCelsius
        self.temperatureFahrenheit = temperatureFahrenheit
        self.feelsLikeCelsius = feelsLikeCelsius
        self.highTemperatureCelsius = highTemperatureCelsius
        self.lowTemperatureCelsius = lowTemperatureCelsius
        self.conditionCode = conditionCode
        self.conditionDescription = conditionDescription
        self.humidity = humidity
        self.windSpeedKph = windSpeedKph
        self.windDirectionDegrees = windDirectionDegrees
        self.uvIndex = uvIndex
        self.visibilityKm = visibilityKm
        self.pressureMb = pressureMb
        self.precipitationAmountMm = precipitationAmountMm
        self.observationDate = observationDate
        self.providerName = providerName
    }
}

public struct HourlyForecastSnapshot: Codable, Equatable, Sendable {
    public let date: String
    public let temperatureCelsius: Double
    public let temperatureFahrenheit: Double
    public let conditionCode: Int
    public let conditionDescription: String
    public let precipitationChance: Double?
    public let humidity: Double?
    public let windSpeedKph: Double?
    public let windDirectionDegrees: Double?
    public let uvIndex: Int?

    public init(
        date: String,
        temperatureCelsius: Double,
        temperatureFahrenheit: Double,
        conditionCode: Int,
        conditionDescription: String,
        precipitationChance: Double? = nil,
        humidity: Double? = nil,
        windSpeedKph: Double? = nil,
        windDirectionDegrees: Double? = nil,
        uvIndex: Int? = nil
    ) {
        self.date = date
        self.temperatureCelsius = temperatureCelsius
        self.temperatureFahrenheit = temperatureFahrenheit
        self.conditionCode = conditionCode
        self.conditionDescription = conditionDescription
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.windSpeedKph = windSpeedKph
        self.windDirectionDegrees = windDirectionDegrees
        self.uvIndex = uvIndex
    }
}

public struct DailyForecastSnapshot: Codable, Equatable, Sendable {
    public let date: String
    public let highTemperatureCelsius: Double
    public let highTemperatureFahrenheit: Double
    public let lowTemperatureCelsius: Double
    public let lowTemperatureFahrenheit: Double
    public let conditionCode: Int
    public let conditionDescription: String
    public let precipitationChance: Double?
    public let humidity: Double?
    public let windSpeedKph: Double?
    public let uvIndex: Int?

    public init(
        date: String,
        highTemperatureCelsius: Double,
        highTemperatureFahrenheit: Double,
        lowTemperatureCelsius: Double,
        lowTemperatureFahrenheit: Double,
        conditionCode: Int,
        conditionDescription: String,
        precipitationChance: Double? = nil,
        humidity: Double? = nil,
        windSpeedKph: Double? = nil,
        uvIndex: Int? = nil
    ) {
        self.date = date
        self.highTemperatureCelsius = highTemperatureCelsius
        self.highTemperatureFahrenheit = highTemperatureFahrenheit
        self.lowTemperatureCelsius = lowTemperatureCelsius
        self.lowTemperatureFahrenheit = lowTemperatureFahrenheit
        self.conditionCode = conditionCode
        self.conditionDescription = conditionDescription
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.windSpeedKph = windSpeedKph
        self.uvIndex = uvIndex
    }
}

public struct AirQualitySnapshot: Codable, Equatable, Sendable {
    public let locationName: String
    public let latitude: Double
    public let longitude: Double
    public let airQualityIndex: Int?
    public let category: String?
    public let primaryPollutant: String?
    public let primaryPollutantAmount: Double?
    public let primaryPollutantUnit: String?
    public let scaleIdentifier: String?
    public let recommendation: String?
    public let provider: String?

    public init(
        locationName: String,
        latitude: Double,
        longitude: Double,
        airQualityIndex: Int? = nil,
        category: String? = nil,
        primaryPollutant: String? = nil,
        primaryPollutantAmount: Double? = nil,
        primaryPollutantUnit: String? = nil,
        scaleIdentifier: String? = nil,
        recommendation: String? = nil,
        provider: String? = nil
    ) {
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.airQualityIndex = airQualityIndex
        self.category = category
        self.primaryPollutant = primaryPollutant
        self.primaryPollutantAmount = primaryPollutantAmount
        self.primaryPollutantUnit = primaryPollutantUnit
        self.scaleIdentifier = scaleIdentifier
        self.recommendation = recommendation
        self.provider = provider
    }
}

public enum WeatherConditionCodeMapper {
    public static func description(for code: Int) -> String {
        switch code {
        case 1: return "Tornado"
        case 2: return "Tropical Storm"
        case 3: return "Hurricane"
        case 4: return "Severe Thunderstorms"
        case 5: return "Thunderstorms"
        case 6: return "Mixed Rain and Snow"
        case 7: return "Mixed Rain and Sleet"
        case 8: return "Mixed Snow and Sleet"
        case 9: return "Freezing Drizzle"
        case 10: return "Drizzle"
        case 11: return "Freezing Rain"
        case 12: return "Showers"
        case 13: return "Snow Flurries"
        case 14: return "Light Snow Showers"
        case 15: return "Blowing Snow"
        case 16: return "Snow"
        case 17: return "Hail"
        case 18: return "Sleet"
        case 19: return "Dust"
        case 20: return "Foggy"
        case 21: return "Haze"
        case 22: return "Smoky"
        case 23: return "Blustery"
        case 24: return "Windy"
        case 25: return "Cold"
        case 26: return "Cloudy"
        case 27: return "Mostly Cloudy (Night)"
        case 28: return "Mostly Cloudy"
        case 29: return "Partly Cloudy (Night)"
        case 30: return "Partly Cloudy"
        case 31: return "Clear (Night)"
        case 32: return "Sunny"
        case 33: return "Fair (Night)"
        case 34: return "Fair"
        case 35: return "Mixed Rain and Hail"
        case 36: return "Hot"
        case 37: return "Isolated Thunderstorms"
        case 38: return "Scattered Thunderstorms"
        case 39: return "Scattered Showers"
        case 40: return "Heavy Snow"
        case 41: return "Scattered Snow Showers"
        case 42: return "Partly Cloudy"
        case 43: return "Snow Showers"
        case 44: return "Isolated Thundershowers"
        default: return "Unknown"
        }
    }
}

/// A severe-weather alert issued for a place (`WFSevereWeatherEvent`).
public struct WeatherAlertSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let area: String?
    public let source: String?
    public let expiresAt: Date?
    public let url: String?

    public init(id: String, title: String, area: String?, source: String?, expiresAt: Date?, url: String?) {
        self.id = id
        self.title = title
        self.area = area
        self.source = source
        self.expiresAt = expiresAt
        self.url = url
    }
}

/// Minute-by-minute precipitation for the next hour (`WFNextHourPrecipitation`).
public struct NextHourSnapshot: Sendable, Equatable {
    public struct Minute: Sendable, Equatable {
        public let date: Date
        /// Percent (0...100), as the service reports it.
        public let chance: Double
        /// Millimeters per hour.
        public let intensity: Double

        public init(date: Date, chance: Double, intensity: Double) {
            self.date = date
            self.chance = chance
            self.intensity = intensity
        }
    }

    public let summary: String?
    public let minutes: [Minute]

    public init(summary: String?, minutes: [Minute]) {
        self.summary = summary
        self.minutes = minutes
    }
}
