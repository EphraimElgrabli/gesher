import Foundation
import GesherPlatform
import XCTest

final class UpdateCheckerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "QA-gesher-updater-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testSemVerParsingAndComparison() {
        XCTAssertEqual(SemVer(parsing: "v1.2.0"), SemVer(parsing: "1.2.0"))
        XCTAssertEqual(SemVer(parsing: "1.2.0+build.5"), SemVer(parsing: "1.2.0"))
        XCTAssertTrue(SemVer(parsing: "1.1.9")! < SemVer(parsing: "1.2.0")!)
        XCTAssertTrue(SemVer(parsing: "1.2.0")! < SemVer(parsing: "1.10.0")!)
        XCTAssertTrue(SemVer(parsing: "1.2.0-beta.1")! < SemVer(parsing: "1.2.0")!)
        XCTAssertFalse(SemVer(parsing: "1.2.0")! < SemVer(parsing: "1.2.0")!)
        XCTAssertNil(SemVer(parsing: "1.2"))
        XCTAssertNil(SemVer(parsing: "not-a-version"))
    }

    func testExtractVersionFromGitHubReleaseURL() {
        XCTAssertEqual(
            UpdateChecker.extractVersion(
                fromReleaseURL: "https://github.com/EphraimElgrabli/gesher/releases/tag/v1.3.0"),
            "1.3.0")
        XCTAssertEqual(
            UpdateChecker.extractVersion(
                fromReleaseURL: "https://github.com/EphraimElgrabli/gesher/releases/tag/1.4.2-rc.1?foo=1"),
            "1.4.2-rc.1")
        XCTAssertNil(UpdateChecker.extractVersion(fromReleaseURL: "https://github.com/EphraimElgrabli/gesher/releases"))
    }

    func testCacheWriteReadStalenessAndRefresh() throws {
        let cacheURL = tempDir.appendingPathComponent("update-check.json")
        let configURL = tempDir.appendingPathComponent("config.json")
        let env = ["GESHER_CONFIG": configURL.path]

        let checker = UpdateChecker(
            cacheURL: cacheURL,
            checkInterval: 3600,
            environment: env,
            configLoader: { UserConfig.load(environment: env) },
            fetcher: { ("1.3.0", "https://github.com/EphraimElgrabli/gesher/releases/tag/v1.3.0") })

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(checker.isCacheStale(now: t0))

        let status = checker.refreshNow(installed: "1.2.0", now: t0)
        XCTAssertEqual(status.latest, "1.3.0")
        XCTAssertTrue(status.updateAvailable)
        XCTAssertTrue(status.shouldNotify)
        XCTAssertFalse(checker.isCacheStale(now: t0.addingTimeInterval(600)))
        XCTAssertTrue(checker.isCacheStale(now: t0.addingTimeInterval(3601)))

        // Installed matches latest -> no update available.
        let current = checker.cachedStatus(installed: "1.3.0", now: t0)
        XCTAssertFalse(current.updateAvailable)
        XCTAssertFalse(current.shouldNotify)
    }

    func testPolicySkippedVersionAndConfigPreservation() throws {
        let cacheURL = tempDir.appendingPathComponent("update-check.json")
        let configURL = tempDir.appendingPathComponent("config.json")
        let env = ["GESHER_CONFIG": configURL.path]

        try UserConfig.setValues(["location": "Haifa"], inSection: "weather", environment: env)
        try UserConfig.setValues(["mode": "ask", "skippedVersion": "1.3.0"], inSection: "updates", environment: env)

        let loaded = UserConfig.load(environment: env)
        XCTAssertEqual(loaded.value("weather", "location"), "Haifa")
        XCTAssertEqual(loaded.value("updates", "mode"), "ask")
        XCTAssertEqual(loaded.value("updates", "skippedVersion"), "1.3.0")

        let checker = UpdateChecker(
            cacheURL: cacheURL,
            environment: env,
            configLoader: { UserConfig.load(environment: env) },
            fetcher: { ("1.3.0", "https://github.com/EphraimElgrabli/gesher/releases/tag/v1.3.0") })
        let skippedStatus = checker.refreshNow(installed: "1.2.0")
        XCTAssertTrue(skippedStatus.updateAvailable)
        XCTAssertTrue(skippedStatus.skipped)
        XCTAssertFalse(skippedStatus.shouldNotify)

        // Newer release 1.4.0 supersedes skipped 1.3.0.
        let checker14 = UpdateChecker(
            cacheURL: cacheURL,
            environment: env,
            configLoader: { UserConfig.load(environment: env) },
            fetcher: { ("1.4.0", "https://github.com/EphraimElgrabli/gesher/releases/tag/v1.4.0") })
        let newerStatus = checker14.refreshNow(installed: "1.2.0")
        XCTAssertTrue(newerStatus.shouldNotify)

        // Setting mode to never suppresses notifications.
        try UserConfig.setValues(["mode": "never"], inSection: "updates", environment: env)
        let neverStatus = checker14.cachedStatus(installed: "1.2.0")
        XCTAssertEqual(neverStatus.policy, .never)
        XCTAssertFalse(neverStatus.shouldNotify)
    }

    func testEnvironmentDisableFlags() {
        XCTAssertTrue(UpdateChecker(environment: ["GESHER_NO_UPDATE_CHECK": "1"]).isDisabledByEnvironment)
        XCTAssertTrue(UpdateChecker(environment: ["CI": "true"]).isDisabledByEnvironment)
        XCTAssertFalse(UpdateChecker(environment: [:]).isDisabledByEnvironment)
    }
}
