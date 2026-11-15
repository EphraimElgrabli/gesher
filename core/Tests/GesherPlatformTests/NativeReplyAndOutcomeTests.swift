import XCTest
@testable import GesherPlatform

final class NativeReplyAndOutcomeTests: XCTestCase {
    func testDuplicateCallbacksCannotReplaceFirstResult() throws {
        let reply = NativeServiceReply()
        reply.complete(value: "first" as NSString, error: nil)
        reply.complete(value: "second" as NSString, error: nil)
        XCTAssertEqual(try reply.wait() as? String, "first")
    }

    func testLateCompletionAfterTimeoutIsIgnored() {
        let reply = NativeServiceReply()
        XCTAssertThrowsError(try reply.wait(timeout: 0.001))
        reply.complete(value: "late" as NSString, error: nil)
        XCTAssertThrowsError(try reply.wait(timeout: 0.001))
    }

    func testAbsenceMustNotAcceptBackendFailureOrSurvivingObject() {
        XCTAssertNoThrow(
            try MutationVerification.absence(id: "fixture") {
                throw PlatformError.objectNotFound(type: "fixture", id: "fixture")
            })
        XCTAssertThrowsError(try MutationVerification.absence(id: "fixture") { "still exists" })
        XCTAssertThrowsError(
            try MutationVerification.absence(id: "fixture") {
                throw PlatformError.fetchFailed("permission/daemon failure")
            })
    }

    func testPostWriteReadbackFailureRetainsIDAndPhase() {
        XCTAssertThrowsError(
            try MutationVerification.readback(type: "note", id: "native-ID") {
                throw PlatformError.fetchFailed("offline")
            }
        ) { error in
            let coded = error as? CLIErrorCodeProviding
            XCTAssertEqual(coded?.code, "save_failed")
            XCTAssertEqual(coded?.details["affectedID"], "native-ID")
            XCTAssertEqual(coded?.details["phase"], "post_write_verification")
        }
    }

    func testSignatureMismatchIsRejectedBeforeDispatch() throws {
        let fixture = SignatureFixture()
        XCTAssertEqual(DynamicRuntime().sendObject(fixture, selector: "object") as? String, "value")
        XCTAssertNil(DynamicRuntime().sendObject(fixture, selector: "scalar"))
        XCTAssertThrowsError(try DynamicRuntime().sendVoidDouble(fixture, selector: "setText:", value: 1))
        XCTAssertEqual(fixture.text, "original")
        try DynamicRuntime().sendVoidInteger(fixture, selector: "setMode:", value: 2)
        XCTAssertEqual(fixture.mode, 2)
        XCTAssertThrowsError(try DynamicRuntime().sendVoidInteger(fixture, selector: "setMode:", value: -1))
    }
}

private final class SignatureFixture: NSObject {
    @objc var text = "original"
    @objc var mode: UInt32 = 0
    @objc func object() -> NSString { "value" }
    @objc func scalar() -> Double { 42 }
}
