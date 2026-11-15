import GesherPlatform
import XCTest
@testable import WeatherCore

final class WeatherCliTests: XCTestCase {
    func testSavedLocationSnapshotProperties() {
        let location = WeatherSavedLocationSnapshot(
            id: "LocationID:31.7833:35.2333",
            name: "Jerusalem",
            preciseName: "Jerusalem",
            country: "IL",
            latitude: 31.7833,
            longitude: 35.2333,
            timeZone: "Asia/Jerusalem"
        )

        XCTAssertEqual(location.id, "LocationID:31.7833:35.2333")
        XCTAssertEqual(location.name, "Jerusalem")
        XCTAssertEqual(location.country, "IL")
        XCTAssertEqual(location.latitude, 31.7833, accuracy: 0.0001)
        XCTAssertEqual(location.longitude, 35.2333, accuracy: 0.0001)
        XCTAssertEqual(location.timeZone, "Asia/Jerusalem")
    }

    func testCurrentWeatherSnapshotProperties() {
        let current = CurrentWeatherSnapshot(
            locationName: "Tel Aviv",
            latitude: 32.0833,
            longitude: 34.8000,
            temperatureCelsius: 25.0,
            temperatureFahrenheit: 77.0,
            feelsLikeCelsius: 26.5,
            highTemperatureCelsius: 28.0,
            lowTemperatureCelsius: 19.0,
            conditionCode: 32,
            conditionDescription: WeatherConditionCodeMapper.description(for: 32),
            humidity: nil,
            windSpeedKph: 14.0,
            windDirectionDegrees: nil,
            uvIndex: 6
        )

        XCTAssertEqual(current.locationName, "Tel Aviv")
        XCTAssertEqual(current.temperatureCelsius, 25.0)
        XCTAssertEqual(current.conditionDescription, "Sunny")
        XCTAssertNil(current.humidity)
        XCTAssertEqual(current.windSpeedKph, 14.0)
        XCTAssertNil(current.windDirectionDegrees)
        XCTAssertEqual(current.uvIndex, 6)
    }

    func testForecastAndAirQualitySnapshots() {
        let hourly = HourlyForecastSnapshot(
            date: "2026-10-13T14:00:00Z",
            temperatureCelsius: 24.0,
            temperatureFahrenheit: 75.2,
            conditionCode: 30,
            conditionDescription: WeatherConditionCodeMapper.description(for: 30),
            precipitationChance: nil,
            humidity: 50.0,
            windSpeedKph: 10.0,
            windDirectionDegrees: nil,
            uvIndex: 4
        )
        XCTAssertEqual(hourly.date, "2026-10-13T14:00:00Z")
        XCTAssertEqual(hourly.temperatureCelsius, 24.0)
        XCTAssertNil(hourly.precipitationChance)
        XCTAssertEqual(hourly.humidity, 50.0)

        let daily = DailyForecastSnapshot(
            date: "2026-10-04T04:00:00Z",
            highTemperatureCelsius: 27.0,
            highTemperatureFahrenheit: 80.6,
            lowTemperatureCelsius: 16.0,
            lowTemperatureFahrenheit: 60.8,
            conditionCode: 30,
            conditionDescription: WeatherConditionCodeMapper.description(for: 30),
            precipitationChance: nil,
            humidity: nil,
            windSpeedKph: 12.0,
            uvIndex: nil
        )
        XCTAssertEqual(daily.conditionDescription, "Partly Cloudy")
        XCTAssertEqual(daily.highTemperatureCelsius, 27.0)
        XCTAssertNil(daily.precipitationChance)
        XCTAssertNil(daily.humidity)
        XCTAssertNil(daily.uvIndex)

        let aqi = AirQualitySnapshot(
            locationName: "Paris",
            latitude: 48.8567,
            longitude: 2.3510,
            airQualityIndex: nil,
            category: nil,
            primaryPollutant: "OZONE",
            primaryPollutantAmount: 39.2,
            primaryPollutantUnit: "ppb"
        )
        XCTAssertEqual(aqi.locationName, "Paris")
        XCTAssertNil(aqi.airQualityIndex)
        XCTAssertNil(aqi.category)
        XCTAssertEqual(aqi.primaryPollutant, "OZONE")
    }

    func testCoordinatesSelector() throws {
        let parsed = try XCTUnwrap(try WeatherReadRepository.coordinates("32.0853, 34.7818"))
        XCTAssertEqual(parsed.latitude, 32.0853, accuracy: 0.0001)
        XCTAssertNil(try WeatherReadRepository.coordinates("Tel Aviv"))
        XCTAssertThrowsError(try WeatherReadRepository.coordinates("91,34")) { error in
            XCTAssertEqual((error as? AgentError)?.code, "invalid_argument")
        }
        let place = try WeatherReadRepository(runtime: WeatherRuntime(), describeCoordinates: false)
            .resolvePlace("32.0853,34.7818")
        XCTAssertEqual(place.latitude, 32.0853, accuracy: 0.0001)
        XCTAssertEqual(place.identifierAvailability, "derived_coordinates_not_favorite_id")
    }

    func testEmptyFavoriteSelectorIsRejectedBeforeOpeningStore() {
        let runtime = WeatherRuntime()
        let writeRepo = WeatherWriteRepository(
            runtime: runtime, readRepository: WeatherReadRepository(runtime: runtime))
        XCTAssertThrowsError(try writeRepo.removeLocation(idOrName: "   ")) { error in
            XCTAssertEqual((error as? CLIErrorCodeProviding)?.code, "invalid_argument")
        }
        XCTAssertThrowsError(try writeRepo.addLocation(place: " "))
    }
}
