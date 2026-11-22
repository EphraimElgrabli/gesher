import Foundation
import GesherPlatform
import XCTest

final class RuntimeCompatibilityTests: XCTestCase {
    func testOSGenerationComparisonAndFormatting() {
        let gen = OSGeneration(major: 27, minor: 0, patch: 0)
        XCTAssertEqual(gen.description, "macOS 27.0")
        XCTAssertTrue(gen.isAtLeast(26))
        XCTAssertTrue(gen.isAtLeast(27, minor: 0))
        XCTAssertFalse(gen.isAtLeast(27, minor: 1))
        XCTAssertFalse(gen.isAtLeast(28))

        let patched = OSGeneration(major: 15, minor: 4, patch: 2)
        XCTAssertEqual(patched.description, "macOS 15.4.2")
        XCTAssertTrue(patched.isAtLeast(15, minor: 4))
        XCTAssertFalse(patched.isAtLeast(15, minor: 5))
        XCTAssertGreaterThanOrEqual(OSGeneration.current.major, 14)
    }

    func testDynamicRuntimeMultiGenerationFallbacks() throws {
        let runtime = DynamicRuntime()
        let cls: AnyClass = try runtime.resolveFirstClass(["NonExistentFutureClass_v99", "NSString"])
        XCTAssertTrue(cls === NSString.self)

        XCTAssertThrowsError(try runtime.resolveFirstClass(["MissingA", "MissingB"]))

        let sel = try runtime.resolveFirstSelector(
            on: "hello" as NSString, candidates: ["nonExistentFutureSelector", "length"])
        XCTAssertEqual(sel, NSSelectorFromString("length"))

        XCTAssertThrowsError(
            try runtime.resolveFirstSelector(on: "hello" as NSString, candidates: ["missingA", "missingB"]))

        let sym = try DynamicRuntime.resolveFirstSymbol(
            candidates: ["__nonexistent_future_symbol_v99", "strlen"], feature: "C strlen")
        XCTAssertNotNil(sym)

        XCTAssertThrowsError(
            try DynamicRuntime.resolveFirstSymbol(
                candidates: ["__missing_sym_a", "__missing_sym_b"], feature: "missing feature"))
    }
}
