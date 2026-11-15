import Foundation
import XCTest
@testable import GesherPlatform

private final class PermissionFixture: PermissionBackend, @unchecked Sendable {
    var status: TCCStatus
    var requests = 0
    var recordsDenial = true
    var result: PermissionRequestResult
    init(_ status: TCCStatus, result: PermissionRequestResult = .granted) { self.status = status; self.result = result }
    func preflight(service: TCCService) -> TCCStatus { status }
    func request(service: TCCService, timeoutSeconds: Double) -> PermissionRequestResult {
        requests += 1
        if result == .granted { status = .authorized }
        if result == .denied && recordsDenial { status = .denied }
        return result
    }
}

final class PermissionCoordinatorTests: XCTestCase {
    func testFirstUseRequestsAndAcceptsUserDecision() throws {
        let backend = PermissionFixture(.notDetermined)
        try PermissionCoordinator(backend: backend).ensureAuthorized(service: .calendar)
        XCTAssertEqual(backend.requests, 1)
        XCTAssertEqual(backend.status, .authorized)
    }
    func testAlreadyAuthorizedAndInspectionDoNotPrompt() throws {
        let backend = PermissionFixture(.authorized)
        try PermissionCoordinator(backend: backend).ensureAuthorized(service: .calendar)
        XCTAssertEqual(backend.requests, 0)
        backend.status = .notDetermined
        let snapshot = PermissionCoordinator(backend: backend).inspect(service: .calendar)
        XCTAssertFalse(snapshot.requestAttempted)
        XCTAssertEqual(backend.requests, 0)
    }
    func testDeniedPermissionIsNotRepeatedlyPrompted() {
        let backend = PermissionFixture(.denied)
        XCTAssertThrowsError(try PermissionCoordinator(backend: backend).ensureAuthorized(service: .contacts))
        XCTAssertEqual(backend.requests, 0)
    }
    func testTimeoutDoesNotBecomeDenialOrMutation() {
        let backend = PermissionFixture(.notDetermined, result: .timedOut)
        XCTAssertThrowsError(try PermissionCoordinator(backend: backend).ensureAuthorized(service: .reminders)) {
            error in
            XCTAssertEqual((error as? CLIErrorCodeProviding)?.code, "permission_request_pending")
        }
        XCTAssertEqual(backend.status, .notDetermined)
    }
    func testHostBlockedRequestIsNotReportedAsUserDenial() {
        let backend = PermissionFixture(.notDetermined, result: .denied)
        backend.recordsDenial = false
        let coordinator = PermissionCoordinator(backend: backend)
        XCTAssertEqual(coordinator.inspect(service: .contacts, request: true).requestResult, .blocked)
        XCTAssertThrowsError(try coordinator.ensureAuthorized(service: .contacts)) { error in
            XCTAssertEqual((error as? CLIErrorCodeProviding)?.code, "private_backend_unavailable")
        }
    }
    func testFullDiskAccessCannotBeRequestedByDialog() {
        let backend = PermissionFixture(.notDetermined)
        let snapshot = PermissionCoordinator(backend: backend).inspect(service: .fullDiskAccess, request: true)
        XCTAssertEqual(backend.requests, 0)
        XCTAssertEqual(snapshot.requestMethod, "system_settings_only")
        XCTAssertFalse(snapshot.requestAttempted)
    }
    func testWriteOnlyCalendarAccessAsksForFullAccessAndExplainsSettings() {
        let backend = PermissionFixture(.writeOnly, result: .denied)
        backend.recordsDenial = false
        let snapshot = PermissionCoordinator(backend: backend).inspect(service: .calendar, request: true)
        XCTAssertEqual(backend.requests, 1)
        XCTAssertEqual(snapshot.permission, "write_only")
        XCTAssertTrue(snapshot.recovery.contains("Full Access"))
        XCTAssertThrowsError(try PermissionCoordinator(backend: backend).ensureAuthorized(service: .calendar))
    }
}

final class ResponsibleProcessTests: XCTestCase {
    func testDisclaimsOnlyWhenTheHostLacksTheGrant() {
        XCTAssertTrue(ResponsibleProcess.shouldDisclaim(service: .contacts, environment: [:]) { _ in false })
        // A host that already holds the grant (e.g. a terminal with Full Disk Access) keeps it.
        XCTAssertFalse(ResponsibleProcess.shouldDisclaim(service: .fullDiskAccess, environment: [:]) { _ in true })
        // Apps without a privacy service never re-execute.
        XCTAssertFalse(ResponsibleProcess.shouldDisclaim(service: nil, environment: [:]) { _ in false })
    }
    func testChildAndOptOutNeverReexecute() {
        XCTAssertFalse(
            ResponsibleProcess.shouldDisclaim(
                service: .calendar, environment: [ResponsibleProcess.markerVariable: "1"]
            ) { _ in false })
        XCTAssertFalse(
            ResponsibleProcess.shouldDisclaim(
                service: .calendar, environment: [ResponsibleProcess.optOutVariable: "0"]
            ) { _ in false })
    }
}
