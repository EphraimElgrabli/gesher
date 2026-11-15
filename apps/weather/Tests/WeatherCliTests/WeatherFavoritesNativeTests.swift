import GesherPlatform
import Foundation
import XCTest
@testable import WeatherCore

final class WeatherFavoritesNativeTests: XCTestCase {
    func testPrivateFavoritesPersistAcrossContextsAndPreserveOtherEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first: WeatherFavoritesStore
        do { first = try WeatherFavoritesStore(storageDirectory: directory) } catch let error as PlatformError {
            if ["missing_class", "unsupported_private_api", "framework_load_failed"].contains(error.code) {
                throw XCTSkip("This OS lacks the tested native favorites ABI: \(error.code)")
            }
            throw error
        }
        XCTAssertTrue(try first.all().isEmpty)
        let a = WeatherSavedLocationSnapshot(
            id: UUID().uuidString, name: "בדיקה ראשונה", latitude: 31.78, longitude: 35.21, timeZone: "Asia/Jerusalem")
        let b = WeatherSavedLocationSnapshot(
            id: UUID().uuidString, name: "בדיקה שנייה", latitude: 32.08, longitude: 34.8, timeZone: "Asia/Jerusalem")
        try first.add(a)
        try WeatherFavoritesStore(storageDirectory: directory).add(b)
        let loaded = try WeatherFavoritesStore(storageDirectory: directory).all()
        XCTAssertEqual(loaded.map(\.id), [a.id, b.id])
        XCTAssertEqual(loaded.first?.name, a.name)
        XCTAssertEqual(loaded.first?.latitude ?? 0, a.latitude, accuracy: 0.000001)
        XCTAssertEqual(loaded.first?.timeZone, a.timeZone)
        try WeatherFavoritesStore(storageDirectory: directory).remove(id: a.id)
        XCTAssertEqual(try WeatherFavoritesStore(storageDirectory: directory).all().map(\.id), [b.id])
        try WeatherFavoritesStore(storageDirectory: directory).remove(id: b.id)
        XCTAssertTrue(try WeatherFavoritesStore(storageDirectory: directory).all().isEmpty)
    }
}
