import GesherKit
import GesherPlatform
import XCTest

@testable import WeatherCli
@testable import WeatherCore

/// Stand-ins with the native property names WeatherFoundation uses (read through KVC).
@objc private final class FakeAlert: NSObject {
    @objc var identifier: String?
    @objc var eventDescription: String?
    @objc var areaName: String?
    @objc var source: String?
    @objc var expirationDate: Date?
    @objc var URL: URL?

    init(id: String?, title: String?) {
        identifier = id
        eventDescription = title
    }
}

@objc private final class FakeMinute: NSObject {
    @objc var date: Date
    @objc var chance: NSNumber
    @objc var intensity: NSNumber

    init(_ date: Date, _ chance: Double, _ intensity: Double) {
        self.date = date
        self.chance = NSNumber(value: chance)
        self.intensity = NSNumber(value: intensity)
    }
}

@objc private final class FakeDescription: NSObject {
    @objc var longDescription: String?
    @objc var longTemplate: String?
}

@objc private final class FakeNextHour: NSObject {
    @objc var minutes: [FakeMinute]
    @objc var currentDescription: FakeDescription?

    init(_ minutes: [FakeMinute]) { self.minutes = minutes }
}

final class WeatherAlertsTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let london = WeatherSavedLocationSnapshot(
        id: "x", name: "QA place", latitude: 51.5, longitude: -0.12, timeZone: "Europe/London")

    func testToolsAreReadOnlyAndValidateFirst() {
        let app = WeatherApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
        let tools = Dictionary(uniqueKeysWithValues: app.operations.map { ($0.toolName, $0.effect) })
        XCTAssertEqual(tools["alerts"], .read)
        XCTAssertEqual(tools["next_hour"], .read)
        for args in [["next-hour", "--units", "kelvin"], ["alerts", "--bogus"], ["next-hour", "a", "b"]] {
            XCTAssertEqual(app.run(args, stdout: { _ in }, stderr: { _ in }), 64, "\(args)")
        }
    }

    func testAlertParsingAndOutput() throws {
        let native = FakeAlert(id: "a1", title: "Yellow Warning for Wind")
        native.source = "QA service"
        native.areaName = ""
        native.expirationDate = start
        native.URL = Foundation.URL(string: "https://example.com/alert")
        let alert = try WeatherReadRepository.parseAlert(native)
        XCTAssertEqual(alert.title, "Yellow Warning for Wind")
        XCTAssertNil(alert.area, "empty strings are omitted")
        XCTAssertEqual(alert.url, "https://example.com/alert")
        let json = try JSONValue.encode(AlertsOutput.Alert(alert, zone: TimeZone(identifier: "Asia/Tokyo")!))
        XCTAssertEqual(json["expires"], "2027-01-15T17:00:00+09:00")
        XCTAssertNil(json["area"])
        XCTAssertThrowsError(try WeatherReadRepository.parseAlert(FakeAlert(id: nil, title: "x")))
        XCTAssertThrowsError(try WeatherReadRepository.parseAlert(FakeAlert(id: "x", title: nil)))
    }

    func testNextHourWithoutMinutesIsNotCovered() throws {
        XCTAssertNil(try WeatherReadRepository.parseNextHour(FakeNextHour([])))
    }

    func testNextHourGroupsWetMinutesIntoPeriods() throws {
        // Dry 0-1, wet 2-4 (peak 80% / 1.5 mm/h), dry 5, wet 6, dry after.
        let profile: [(Double, Double)] = [(0, 0), (0, 0), (20, 0.3), (80, 1.5), (40, 0.4), (0, 0), (10, 0.1), (0, 0)]
        let native = FakeNextHour(
            profile.enumerated().map {
                FakeMinute(start.addingTimeInterval(Double($0.offset) * 60), $0.element.0, $0.element.1)
            })
        native.currentDescription = FakeDescription()
        native.currentDescription?.longTemplate = "Rain starting in {firstAt} min"
        native.currentDescription?.longDescription = "Rain starting in 2 min"
        let snapshot = try XCTUnwrap(try WeatherReadRepository.parseNextHour(native))
        XCTAssertEqual(snapshot.summary, "Rain starting in 2 min")
        let output = NextHourOutput(snapshot, place: Place(london), units: .metric, now: start)
        XCTAssertTrue(output.precipitation)
        XCTAssertNil(output.minutes)
        let periods = try XCTUnwrap(output.periods)
        XCTAssertEqual(periods.count, 2)
        XCTAssertEqual(periods[0].start, DateOutput.iso(start.addingTimeInterval(120), timeZone: Place(london).zone))
        XCTAssertEqual(periods[0].end, DateOutput.iso(start.addingTimeInterval(300), timeZone: Place(london).zone))
        XCTAssertEqual(periods[0].peakChance, 80)
        XCTAssertEqual(periods[0].peakIntensity, 1.5)
        XCTAssertEqual(periods[1].peakChance, 10)
        let imperial = NextHourOutput(snapshot, place: Place(london), units: .imperial, everyMinute: true, now: start)
        XCTAssertEqual(imperial.periods?.first?.peakIntensity, 0.06)
        XCTAssertEqual(imperial.minutes?.count, profile.count)
    }

    func testDryHourAndUnfilledTemplate() throws {
        let native = FakeNextHour((0..<60).map { FakeMinute(start.addingTimeInterval(Double($0) * 60), 0, 0) })
        native.currentDescription = FakeDescription()
        native.currentDescription?.longTemplate = "Rain stopping in {lastAt} min"
        let snapshot = try XCTUnwrap(try WeatherReadRepository.parseNextHour(native))
        XCTAssertNil(snapshot.summary, "a template with placeholders is never shown")
        let json = try JSONValue.encode(NextHourOutput(snapshot, place: Place(london), units: .metric, now: start))
        XCTAssertEqual(json["precipitation"], false)
        XCTAssertNil(json["periods"])
        XCTAssertNil(json["summary"])
    }

    func testIncompleteMinuteIsAnError() {
        @objc final class Broken: NSObject {
            @objc var minutes: [NSObject] = [NSObject()]
        }
        XCTAssertThrowsError(try WeatherReadRepository.parseNextHour(Broken()))
    }

    func testCoordinatesKeepTheirValuesAndTakeTheFoundZone() {
        let point = WeatherSavedLocationSnapshot(
            id: "LocationID:1", identifierAvailability: "derived_coordinates_not_favorite_id", name: "51.5000, -0.1200",
            latitude: 51.5, longitude: -0.12)
        let found = WeatherSavedLocationSnapshot(
            id: "other", name: "QA square", country: "GB", latitude: 51.6, longitude: -0.2, timeZone: "Europe/London")
        let described = WeatherReadRepository.described(point, by: found)
        XCTAssertEqual(described.name, "QA square")
        XCTAssertEqual(described.latitude, 51.5)
        XCTAssertEqual(described.timeZone, "Europe/London")
        XCTAssertEqual(described.id, "LocationID:1")
        XCTAssertEqual(WeatherReadRepository.described(point, by: nil), point)
    }
}
