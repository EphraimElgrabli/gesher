import GesherKit
import GesherPlatform
import Foundation
import XCTest
@testable import MapsCli
@testable import MapsCore

private func at(_ value: JSONValue?, _ index: Int) -> JSONValue? {
    guard case .array(let items)? = value, items.indices.contains(index) else { return nil }
    return items[index]
}

final class MapsCliTests: XCTestCase {
    private func appWithoutContext() -> AgentApp<MapsContext> {
        MapsApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
    }

    private func run(_ app: AgentApp<MapsContext>, _ args: [String]) -> (code: Int32, out: String) {
        var out: [String] = []
        let code = app.run(args, stdout: { out.append($0) }, stderr: { _ in })
        return (code, out.joined(separator: "\n"))
    }

    private let origin = MapPlaceSnapshot(
        id: "geo:1:2", name: "Origin", formattedAddress: "Street 1", coordinate: .init(latitude: 32.1, longitude: 34.8),
        timeZone: "Asia/Jerusalem")

    func testExamplesAndToolNames() {
        let app = MapsApp.make()
        XCTAssertEqual(app.exampleFailures(), [])
        XCTAssertEqual(
            app.operations.map(\.toolName), ["search", "nearby", "place", "reverse", "route", "eta", "doctor"])
        XCTAssertTrue(app.operations.allSatisfy { $0.effect == .read })
    }

    func testInvalidInputFailsBeforeTouchingMaps() {
        let app = appWithoutContext()
        XCTAssertEqual(run(app, ["search"]).code, 64)
        XCTAssertEqual(run(app, ["nearby", "cafe", "--radius", "5"]).code, 64)
        XCTAssertEqual(run(app, ["reverse", "north"]).code, 64)
        XCTAssertEqual(run(app, ["reverse", "91,10"]).code, 64)
        XCTAssertEqual(run(app, ["route", "--from", "A"]).code, 64)
        XCTAssertEqual(run(app, ["route", "--from", "A", "--to", "B", "--mode", "flying"]).code, 64)
        let both = run(
            app, ["eta", "--from", "A", "--to", "B", "--depart-at", "today 9:00", "--arrive-by", "today 10:00"])
        XCTAssertEqual(both.code, 64)
        XCTAssertTrue(both.out.contains("not both"))
    }

    func testCoordinatesAndDistance() throws {
        let point = try XCTUnwrap(Coordinates.parse(" 48.8606, 2.3376 "))
        XCTAssertEqual(point.latitude, 48.8606)
        XCTAssertNil(Coordinates.parse("Haifa"))
        XCTAssertNil(Coordinates.parse("10,200"))
        let paris = MapCoordinateSnapshot(latitude: 48.8566, longitude: 2.3522)
        let london = MapCoordinateSnapshot(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(paris.distance(to: london) / 1000, 343.5, accuracy: 1)
    }

    func testCategoryNames() {
        XCTAssertEqual(MapsReadRepository.categoryName("travel_and_leisure.museum.art_museum", poi: nil), "art museum")
        XCTAssertEqual(MapsReadRepository.categoryName(nil, poi: "GEOPOICategoryPublicTransport"), "public transport")
        XCTAssertNil(MapsReadRepository.categoryName(nil, poi: nil))
        XCTAssertEqual(
            MapsReadRepository.address(["Place du Carrousel\n75001 Paris", " France "]),
            "Place du Carrousel, 75001 Paris, France")
        XCTAssertNil(MapsReadRepository.nativeIdentifier(provider: 7618, muid: 0))
        XCTAssertEqual(MapsReadRepository.nativeIdentifier(provider: 7618, muid: 123), "geo:7618:123")
    }

    func testBiasedSearchPrefersACloserGlobalMatch() {
        let near = MapCoordinateSnapshot(latitude: 48.861, longitude: 2.336)
        let far = MapPlaceSnapshot(
            id: "geo:1:1", name: "Tower", formattedAddress: nil, coordinate: .init(latitude: 22.3, longitude: 70.8))
        let close = MapPlaceSnapshot(
            id: "geo:1:2", name: "Tower", formattedAddress: nil, coordinate: .init(latitude: 48.858, longitude: 2.294))
        XCTAssertEqual(
            MapsReadRepository.preferCloser(close, over: [far], to: near, limit: 5).map(\.id), ["geo:1:2", "geo:1:1"])
        XCTAssertEqual(MapsReadRepository.preferCloser(far, over: [close], to: near, limit: 5).map(\.id), ["geo:1:2"])
        XCTAssertEqual(MapsReadRepository.preferCloser(close, over: [close], to: near, limit: 5).count, 1)
    }

    func testPlaceDetailHoursRatingAndCompactOutput() throws {
        // Sunday 09:00–18:00, Saturday 20:00–02:00 (past midnight), Tuesday closed.
        let hours = [
            MapDailyHoursSnapshot(weekday: 1, intervals: [32_400...64_800]),
            MapDailyHoursSnapshot(weekday: 3, intervals: []),
            MapDailyHoursSnapshot(weekday: 7, intervals: [72_000...93_600]),
        ]
        let place = MapPlaceSnapshot(
            id: "geo:1:2", name: "Fixture", formattedAddress: "Street 1",
            coordinate: .init(latitude: 32.123456, longitude: 34.987654), category: "cafe", url: "https://example.com",
            timeZone: "UTC", hours: hours, ratingPercent: 91.6, ratingCount: 40)
        // 2026-11-01 is a Sunday.
        let sundayMorning = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T01:00:00Z"))
        let detail = PlaceDetail(place, now: sundayMorning)
        XCTAssertEqual(detail.openNow, true, "Saturday's range runs past midnight")
        XCTAssertEqual(PlaceDetail(place, now: sundayMorning.addingTimeInterval(5 * 3600)).openNow, false)
        let json = try JSONValue.encode(detail)
        XCTAssertEqual(json["latitude"], 32.1235)
        XCTAssertEqual(json["rating"]?["percent"], 92)
        XCTAssertEqual(json["website"], "https://example.com")
        XCTAssertNil(json["phone"])
        let days = try JSONValue.encode(detail.hours)
        XCTAssertEqual(at(days, 0)?["day"], "Sunday")
        XCTAssertEqual(at(days, 0)?["hours"], "09:00–18:00")
        XCTAssertEqual(at(days, 1)?["hours"], "closed")
        XCTAssertEqual(at(days, 2)?["hours"], "20:00–02:00")
        XCTAssertEqual(PlaceDetail.range(0...86_400), "open 24 hours")
        XCTAssertEqual(PlaceDetail.range(64_800...86_400), "18:00–24:00")
    }

    func testRouteOutputTimesAndSteps() throws {
        let destination = MapPlaceSnapshot(
            id: nil, name: "Destination", formattedAddress: nil, coordinate: .init(latitude: 32.8, longitude: 35))
        let route = MapRouteSnapshot(
            origin: origin, destination: destination, transportType: "automobile", distanceMeters: 95_449,
            durationSeconds: 3_930,
            steps: [
                MapRouteStepSnapshot(instruction: "Head north", distanceMeters: 120.4, durationSeconds: 30),
                MapRouteStepSnapshot(instruction: " ", distanceMeters: 10, durationSeconds: 3, roadName: "Main St"),
            ])
        let arrive = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z"))
        let output = RouteOutput(route, mode: .driving, timepoint: MapTimepoint(.arriveBy, arrive), steps: true)
        XCTAssertEqual(output.distanceKm, 95.4)
        XCTAssertEqual(output.durationMin, 66)
        XCTAssertEqual(output.arriveAt, "2026-11-05T10:00:00+02:00")
        XCTAssertEqual(output.departAt, "2026-11-05T08:54:30+02:00")
        let json = try JSONValue.encode(output)
        XCTAssertNil(at(json["steps"], 1)?["instruction"], "a road name never becomes an instruction")
        XCTAssertEqual(at(json["steps"], 1)?["road"], "Main St")
        XCTAssertNil(try JSONValue.encode(RouteOutput(route, mode: .driving, timepoint: nil, steps: false))["steps"])
    }

    func testTransitUsesNativeScheduleAndNoDistance() throws {
        let route = try TransitRouteDecoder.decode(
            ["abs_start_time": NSNumber(value: 815_000_000), "abs_end_time": NSNumber(value: 815_003_600)],
            origin: origin, destination: origin)
        XCTAssertEqual(route.durationSeconds, 3600)
        XCTAssertNil(route.distanceMeters)
        XCTAssertEqual(route.departure, Date(timeIntervalSinceReferenceDate: 815_000_000))
        XCTAssertThrowsError(try TransitRouteDecoder.decode([:], origin: origin, destination: origin))
        let output = try JSONValue.encode(RouteOutput(route, mode: .transit, timepoint: nil, steps: true))
        XCTAssertNil(output["distanceKm"])
        XCTAssertNil(output["steps"])
    }

    func testDirectionsErrorKeepsReasonOnly() {
        let error = NativeDirectionsError(
            native: NSError(
                domain: "GEOErrorDomain", code: -7, userInfo: ["DirectionsError": "OUT_OF_COVERAGE"]),
            transportType: "bicycle")
        let agent = AgentError.from(error)
        XCTAssertEqual(agent.code, "route_service_error")
        XCTAssertEqual(agent.details, ["reason": "OUT_OF_COVERAGE"])
        XCTAssertNotNil(agent.hint)
        XCTAssertTrue(agent.message.contains("cycling"))
        XCTAssertEqual(
            NativeDirectionsError.reason(
                "GEODirectionsError of type(s): GEOProblemDetail<0x1> {\n    problemType = \"OUT_OF_COVERAGE\";\n}\nTitle: Cycling Directions Not Available\nContent: Not available in this area."
            ), "OUT_OF_COVERAGE: Cycling Directions Not Available: Not available in this area.")
    }
}
