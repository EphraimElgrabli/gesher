import GesherPlatform
import XCTest
@testable import WeatherCore

private final class NativeTemperatureFixture: NSObject {
    @objc var celsius: Double { 22 }
    @objc var fahrenheit: Double { 71.6 }
}
private final class NativeConditionsFixture: NSObject {
    @objc var dictionaryRepresentation: NSDictionary {
        ["WFWeatherTemperatureComponent": NativeTemperatureFixture(), "WFWeatherConditionComponent": 35]
    }
}

private final class NativeEmptyForecastFixture: NSObject {
    @objc var forecasts: NSArray { [] }
}

final class WeatherMissingDataTests: XCTestCase {
    func testMissingFeelsLikeRemainsUnavailable() throws {
        let repository = WeatherReadRepository(runtime: WeatherRuntime())
        let location = WeatherSavedLocationSnapshot(id: "fixture", name: "fixture", latitude: 0, longitude: 0)
        let result = try repository.parseCurrentConditions(NativeConditionsFixture(), location: location)
        XCTAssertEqual(result.temperatureCelsius, 22)
        XCTAssertNil(result.feelsLikeCelsius)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        XCTAssertNil(json["feelsLikeCelsius"])
    }

    func testUnknownNativeGetterDoesNotRaiseKVCException() throws {
        let repository = WeatherReadRepository(runtime: WeatherRuntime())
        XCTAssertTrue(try repository.componentDict(from: NSObject()).isEmpty)
        XCTAssertNil(repository.extractTemp(NSObject()))
    }

    func testMalformedForecastIsNotAnEmptySuccess() {
        XCTAssertThrowsError(try WeatherReadRepository.forecastCollection(NSObject()))
        XCTAssertThrowsError(try WeatherReadRepository.forecastCollection(nil))
    }

    func testDecodedEmptyForecastRemainsAnEmptyCollection() throws {
        XCTAssertTrue(try WeatherReadRepository.forecastCollection(NativeEmptyForecastFixture()).isEmpty)
    }

}
