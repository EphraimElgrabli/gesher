import XCTest
@testable import GesherPlatform

final class GesherPlatformTests: XCTestCase {
    func testPlatformErrorCodesAndDetails() {
        let err = PlatformError.objectNotFound(type: "note", id: "123-abc")
        XCTAssertEqual(err.code, "not_found")
        XCTAssertEqual(err.details["type"], "note")
        XCTAssertEqual(err.details["id"], "123-abc")
    }
}
