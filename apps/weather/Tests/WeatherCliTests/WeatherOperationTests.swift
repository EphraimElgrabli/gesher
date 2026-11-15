import GesherKit
import GesherPlatform
import XCTest
@testable import WeatherCli
@testable import WeatherCore

final class WeatherOperationTests: XCTestCase {
    /// An app whose context must not be created: input validation happens first.
    private func appWithoutContext() -> AgentApp<WeatherContext> {
        WeatherApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
    }

    private func run(_ app: AgentApp<WeatherContext>, _ args: [String]) -> (code: Int32, out: String) {
        var out: [String] = []
        let code = app.run(args, stdout: { out.append($0) }, stderr: { _ in })
        return (code, out.joined(separator: "\n"))
    }

    func testExamplesAndSchemas() {
        let app = WeatherApp.make()
        XCTAssertEqual(app.exampleFailures(), [])
        XCTAssertEqual(
            app.operations.map(\.toolName),
            [
                "current", "hourly", "daily", "air_quality", "alerts", "next_hour", "location_list",
                "location_search", "location_add", "location_remove", "doctor",
            ])
        let remove = app.operations.first { $0.toolName == "location_remove" }
        XCTAssertEqual(remove?.effect, .destructive)
    }

    func testInvalidInputFailsBeforeTouchingWeather() {
        let app = appWithoutContext()
        XCTAssertEqual(run(app, ["hourly", "--hours", "0"]).code, 64)
        XCTAssertEqual(run(app, ["daily", "--units", "kelvin"]).code, 64)
        XCTAssertEqual(run(app, ["hourly", "--from", "someday"]).code, 64)
        XCTAssertEqual(run(app, ["location", "remove"]).code, 64)
        XCTAssertTrue(run(app, ["current", "--plcae", "Haifa"]).out.contains("Did you mean --place?"))
    }

    func testUnitsAndCompactOutput() throws {
        XCTAssertEqual(Units.imperial.temperature(20), 68)
        XCTAssertEqual(Units.imperial.speed(16.09344), 10)
        XCTAssertEqual(Units.metric.temperature(23.449), 23.4)
        let snapshot = CurrentWeatherSnapshot(
            locationName: "Fixture", latitude: 32.123456, longitude: 34.987654, temperatureCelsius: 20,
            temperatureFahrenheit: 68, feelsLikeCelsius: nil, conditionCode: 32, conditionDescription: "Sunny",
            observationDate: "2026-11-03T16:00:00Z", providerName: "Provider")
        let location = WeatherSavedLocationSnapshot(
            id: "x", name: "Fixture", latitude: 32.123456, longitude: 34.987654, timeZone: "Asia/Jerusalem")
        let output = CurrentOutput(snapshot, place: Place(location), units: .metric)
        let json = try JSONValue.encode(output)
        XCTAssertEqual(json["observedAt"], "2026-11-03T18:00:00+02:00")
        XCTAssertEqual(json["place"]?["latitude"], 32.1235)
        XCTAssertNil(json["feelsLike"])
        XCTAssertNil(json["providerName"])
        XCTAssertNil(json["conditionCode"])
    }

    /// Full add → idempotent re-add → batch remove cycle through the CLI, against an isolated
    /// native favorites store in a temporary directory (never the user's favorites).
    func testFavoritesLifecycleInIsolatedStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QA-gesher-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do { _ = try WeatherFavoritesStore(storageDirectory: directory) } catch let error as PlatformError {
            throw XCTSkip("Native favorites ABI unavailable: \(error.code)")
        }
        let runtime = WeatherRuntime()
        let read = WeatherReadRepository(runtime: runtime)
        let write = WeatherWriteRepository(
            readRepository: read, makeStore: { try WeatherFavoritesStore(storageDirectory: directory) })
        let context = WeatherContext(runtime: runtime, read: read, write: write, config: UserConfig(values: [:]))
        let app = WeatherApp.make(context: { context })

        let add = ["location", "add", "32.08,34.78", "--name", "QA-gesher-home", "--time-zone", "Asia/Jerusalem"]
        let first = run(app, add)
        XCTAssertEqual(first.code, 0, first.out)
        let id = try XCTUnwrap(
            try JSONDecoder().decode(JSONValue.self, from: Data(first.out.utf8))["results"].flatMap {
                if case .array(let items) = $0 { return items.first?["result"]?["id"]?.stringValue }
                return nil
            })
        let again = run(app, add)
        XCTAssertTrue(again.out.contains(id), "re-adding returns the existing favorite")

        let removed = run(app, ["location", "remove", "qa-gesher-home", "QA-missing"])
        XCTAssertEqual(removed.code, 1, "one selector does not exist")
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(removed.out.utf8))
        XCTAssertEqual(value["succeeded"], 1)
        XCTAssertEqual(value["failed"], 1)
        XCTAssertTrue(try WeatherFavoritesStore(storageDirectory: directory).all().isEmpty)
    }
}
