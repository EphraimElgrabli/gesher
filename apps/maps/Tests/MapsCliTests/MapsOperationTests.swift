import GesherKit
import GesherPlatform
import Foundation
import XCTest

@testable import MapsCli
@testable import MapsCore

/// Answers like GeoServices from fixed fixtures and records what was asked (no network).
private final class FakeMaps: MapsReading {
    var places: [String: [MapPlaceSnapshot]] = [:]
    var byID: [String: MapPlaceSnapshot] = [:]
    var reverse: [MapPlaceSnapshot] = []
    var routes: [String: Result<Double, Error>] = [:]
    private(set) var searches: [(query: String, near: MapCoordinateSnapshot?)] = []
    private(set) var routeRequests: [String] = []

    func search(query: String, maxResults: Int, near: MapCoordinateSnapshot?) throws -> [MapPlaceSnapshot] {
        searches.append((query, near))
        return Array((places[query] ?? []).prefix(maxResults))
    }

    func place(id: String) throws -> MapPlaceSnapshot {
        guard let place = byID[id] else { throw AgentError.notFound("place", id) }
        return place
    }

    func reverseGeocode(latitude: Double, longitude: Double) throws -> [MapPlaceSnapshot] { reverse }

    func route(
        origin: MapPlaceSnapshot, destination: MapPlaceSnapshot, transportType: String, timepoint: MapTimepoint?
    ) throws -> MapRouteSnapshot {
        routeRequests.append(transportType)
        let seconds = try (routes[transportType] ?? .success(600)).get()
        return MapRouteSnapshot(
            origin: origin, destination: destination, transportType: transportType, distanceMeters: 1_200,
            durationSeconds: seconds)
    }
}

private func place(_ name: String, _ latitude: Double, _ longitude: Double, id: String? = nil) -> MapPlaceSnapshot {
    MapPlaceSnapshot(
        id: id, name: name, formattedAddress: "\(name) street",
        coordinate: .init(latitude: latitude, longitude: longitude),
        timeZone: "Asia/Jerusalem")
}

final class MapsOperationTests: XCTestCase {
    private let center = place("QA center", 32.80, 35.00, id: "geo:1:100")

    private func run(_ fake: FakeMaps, _ args: [String], config: [String: [String: String]] = [:]) -> (
        code: Int32, json: JSONValue?
    ) {
        let context = MapsContext(read: fake, config: UserConfig(values: config))
        var out = ""
        let code = MapsApp.make(context: { context }).run(args, stdout: { out += $0 }, stderr: { _ in })
        return (code, try? JSONDecoder().decode(JSONValue.self, from: Data(out.utf8)))
    }

    func testSearchEchoesPlacesWithDistanceFromTheBias() throws {
        let fake = FakeMaps()
        fake.places["QA center"] = [center]
        fake.places["coffee"] = [place("QA cafe", 32.81, 35.00, id: "geo:1:1")]
        let (code, json) = run(fake, ["search", "coffee", "--near", "QA center"])
        XCTAssertEqual(code, 0)
        let first = json?["places"]?.arrayValue?.first
        XCTAssertEqual(first?["name"], "QA cafe")
        XCTAssertEqual(first?["distanceKm"], 1.1)
        XCTAssertEqual(fake.searches.last?.near, center.coordinate, "near is sent as the bias")
    }

    func testNearbyKeepsTheRadiusAndSortsByDistance() throws {
        let fake = FakeMaps()
        fake.places["cafe"] = [
            place("far", 32.90, 35.00), place("close", 32.801, 35.00), place("middle", 32.805, 35.00),
        ]
        let (code, json) = run(fake, ["nearby", "cafe", "--near", "32.80,35.00", "--radius", "1000"])
        XCTAssertEqual(code, 0)
        XCTAssertEqual(json?["places"]?.arrayValue?.map { $0["name"] }, ["close", "middle"])
    }

    func testNearbyUsesTheConfiguredCenterAndNeedsOne() throws {
        let fake = FakeMaps()
        fake.places["cafe"] = [place("close", 32.801, 35.00)]
        XCTAssertEqual(run(fake, ["nearby", "cafe"], config: ["maps": ["near": "32.80,35.00"]]).code, 0)
        let missing = run(fake, ["nearby", "cafe"])
        XCTAssertEqual(missing.code, 64)
        XCTAssertNotNil(missing.json?["error"]?["hint"])
    }

    func testPlaceByIdNameAndCoordinate() throws {
        let fake = FakeMaps()
        fake.byID["geo:1:100"] = center
        fake.places["QA center"] = [center]
        fake.reverse = [place("QA address", 32.8, 35.0)]
        XCTAssertEqual(run(fake, ["place", "geo:1:100"]).json?["name"], "QA center")
        XCTAssertEqual(run(fake, ["place", "QA center"]).json?["id"], "geo:1:100")
        XCTAssertEqual(run(fake, ["place", "32.8,35.0"]).json?["name"], "QA address")
        let unknown = run(fake, ["place", "nowhere at all"])
        XCTAssertEqual(unknown.code, 1)
        XCTAssertEqual(unknown.json?["error"]?["code"], "not_found")
        fake.reverse = []
        XCTAssertEqual(run(fake, ["place", "1,1"]).json?["error"]?["code"], "not_found")
    }

    func testRouteRanksTheDestinationNearTheStart() throws {
        let fake = FakeMaps()
        fake.places["QA center"] = [center]
        fake.places["QA port"] = [place("QA port", 32.82, 35.0)]
        let (code, json) = run(fake, ["route", "--from", "QA center", "--to", "QA port", "--mode", "walking"])
        XCTAssertEqual(code, 0)
        XCTAssertEqual(json?["mode"], "walking")
        XCTAssertEqual(json?["durationMin"], 10)
        XCTAssertEqual(fake.searches.last?.query, "QA port")
        XCTAssertEqual(fake.searches.last?.near, center.coordinate)
        XCTAssertEqual(fake.routeRequests, ["walking"])
    }

    func testEtaReportsEachModeAndNeverEstimatesAFailedOne() throws {
        let fake = FakeMaps()
        fake.routes["bicycle"] = .failure(
            NativeDirectionsError(
                native: NSError(domain: "GEOErrorDomain", code: -7, userInfo: ["DirectionsError": "OUT_OF_COVERAGE"]),
                transportType: "bicycle"))
        let partial = run(
            fake, ["eta", "--from", "32.8,35.0", "--to", "32.9,35.0", "--mode", "driving", "--mode", "cycling"])
        XCTAssertEqual(partial.code, 1, "a failed mode makes the batch exit 1 but prints every result")
        XCTAssertEqual(partial.json?["succeeded"], 1)
        let results = partial.json?["results"]?.arrayValue ?? []
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.last?["error"]?["code"], "route_service_error")
        XCTAssertNil(results.last?["durationMin"])
        // Repeating a mode asks once.
        _ = run(fake, ["eta", "--from", "32.8,35.0", "--to", "32.9,35.0", "--mode", "walking", "--mode", "walking"])
        XCTAssertEqual(fake.routeRequests.suffix(1), ["walking"])
    }

    func testBadPlaceIdsAndEmptyTextFailBeforeMaps() {
        let app = MapsApp.make(context: {
            XCTFail("context created for invalid input")
            throw AgentError(code: "internal_error", message: "unexpected")
        })
        for args in [
            ["place", "geo:abc"], ["place", " "], ["search", " "], ["nearby", " "],
            ["search", "x", "--near", "geo:1:0"],
            ["route", "--from", "geo:x:1", "--to", "B"], ["eta", "--from", "A", "--to", ""],
        ] {
            XCTAssertEqual(app.run(args, stdout: { _ in }, stderr: { _ in }), 64, "\(args)")
        }
    }

    func testPlaceIDParsing() {
        XCTAssertEqual(MapPlaceID.parse("geo:7618:123")?.muid, 123)
        XCTAssertNil(MapPlaceID.parse("geo:7618:0"))
        XCTAssertNil(MapPlaceID.parse("geo:1:2:3"))
        XCTAssertNil(MapPlaceID.parse("geo::5"))
    }
}

extension JSONValue {
    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }
}
