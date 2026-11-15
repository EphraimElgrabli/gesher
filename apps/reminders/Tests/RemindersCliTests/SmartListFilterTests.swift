import GesherPlatform
import Foundation
import XCTest

@testable import RemindersCli
@testable import RemindersCore

final class SmartListFilterTests: XCTestCase {
    private func json(_ filter: SmartListFilter) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: filter.nativeData()) as? [String: Any])
    }

    /// Compact sorted JSON of a value, for comparing heterogeneous native structures.
    private func text(_ value: Any?) -> String {
        guard let value,
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        else { return "nil" }
        return String(decoding: data, as: UTF8.self)
    }

    func testWritesTheAppsV2Format() throws {
        let filter = SmartListFilter(
            match: "any", tags: ["#work"], excludeTags: ["later"], tagsMatch: "any", date: "next 3 days",
            includeOverdue: true, time: "none", priorities: ["high", "none"], flagged: true, location: "car-connected",
            lists: ["REMCDList:00000000-0000-0000-0000-000000000001"])
        let object = try json(filter)
        XCTAssertEqual(object["operation"] as? String, "or")
        XCTAssertEqual(
            text(object["hashtags"]),
            text(["hashtags": ["include": ["work"], "exclude": ["later"], "operation": "or"]] as [String: Any]))
        XCTAssertEqual(
            text(object["date"]),
            text(
                ["relativeRange": ["direction": "inNext", "magnitude": "3", "units": "day", "includePastDue": true]]
                    as [String: Any]))
        XCTAssertEqual(text(object["time"]), text(["noTime": ""] as [String: Any]))
        XCTAssertEqual(text(object["location"]), text(["vehicle": "connected"] as [String: Any]))
        XCTAssertEqual(
            text(object["lists"]),
            text(["include": ["00000000-0000-0000-0000-000000000001"], "exclude": [String]()] as [String: Any]))
        XCTAssertEqual(
            text(try json(SmartListFilter(date: "on 2026-11-05"))["date"]),
            text(["onDate": "05-11-2026"] as [String: Any]))
        XCTAssertEqual(
            text(try json(SmartListFilter(date: "between 2026-11-01 and 2026-11-30"))["date"]),
            text(["dateRange": ["01-11-2026", "30-11-2026"]] as [String: Any]))
        XCTAssertEqual(
            text(try json(SmartListFilter(tagged: false))["hashtags"]), text(["untagged": ""] as [String: Any]))
    }

    func testRoundTripsAndReadsLegacyData() throws {
        let filter = SmartListFilter(
            match: "all", tags: ["home"], tagsMatch: "all", date: "between 2026-11-01 and 2026-11-30",
            priorities: ["low"], lists: ["REMCDList:00000000-0000-0000-0000-000000000002"])
        XCTAssertEqual(try SmartListFilter(native: filter.nativeData()), filter)
        let legacy = try SmartListFilter(
            native: Data(#"{"hashtags":{"hashtags":["a","b"]},"date":{"relativeRange":["inPast","2","week"]}}"#.utf8))
        XCTAssertEqual(legacy.tags, ["a", "b"])
        XCTAssertEqual(legacy.tagsMatch, "any")
        XCTAssertEqual(legacy.date, "past 2 weeks")
        let unknown = try SmartListFilter(native: Data(#"{"future":{"x":1},"flagged":true}"#.utf8))
        XCTAssertEqual(unknown.flagged, true)
        XCTAssertEqual(unknown.other, ["future": #"{"x":1}"#])
        XCTAssertNotNil(try json(unknown)["future"])
    }

    func testRejectsInvalidFilters() {
        for filter in [
            SmartListFilter(date: "someday"), SmartListFilter(time: "noon"), SmartListFilter(priorities: ["urgent"]),
            SmartListFilter(flagged: false), SmartListFilter(tags: ["a"], tagged: true),
            SmartListFilter(lists: ["Groceries"]), SmartListFilter(match: "most"),
        ] {
            XCTAssertThrowsError(try filter.nativeData(), "\(filter)")
        }
    }

    func testNaturalDatesInFilterInput() throws {
        let input = DateInput(timeZone: .current, now: Date())
        XCTAssertEqual(try FilterInput.normalizedDate("on 2026-11-05", input: input), "on 2026-11-05")
        XCTAssertEqual(try FilterInput.normalizedDate("Next 3 Days", input: input), "next 3 days")
        XCTAssertTrue(
            try FilterInput.normalizedDate("between today and 2026-12-01", input: input).hasSuffix("2026-12-01"))
        XCTAssertThrowsError(try FilterInput.normalizedDate("on someday", input: input))
    }
}
