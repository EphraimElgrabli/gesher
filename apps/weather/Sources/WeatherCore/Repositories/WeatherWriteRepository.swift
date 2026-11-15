import GesherPlatform
import Foundation

public final class WeatherWriteRepository: @unchecked Sendable {
    private let readRepository: WeatherReadRepository
    private let makeStore: () throws -> WeatherFavoritesStore

    public convenience init(runtime: WeatherRuntime, readRepository: WeatherReadRepository) {
        self.init(readRepository: readRepository, makeStore: { try WeatherFavoritesStore() })
    }

    init(readRepository: WeatherReadRepository, makeStore: @escaping () throws -> WeatherFavoritesStore) {
        self.readRepository = readRepository
        self.makeStore = makeStore
    }

    /// Saves a place as a Weather favorite and verifies it through a fresh native context.
    /// Adding the same name at the same point again returns the existing favorite.
    public func addLocation(place: String, name: String? = nil, timeZone: String? = nil) throws
        -> WeatherSavedLocationSnapshot
    {
        guard !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalid("The place to add is empty.")
        }
        let resolved = try readRepository.resolvePlace(place)
        guard let resolvedTimeZone = timeZone ?? resolved.timeZone, TimeZone(identifier: resolvedTimeZone) != nil
        else {
            throw AgentError.invalid(
                "No time zone is known for \(resolved.name).",
                hint: "Pass timeZone with an IANA identifier, e.g. Asia/Jerusalem.")
        }
        let store = try makeStore()
        let before = try store.all()
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? resolved.name
        guard !title.isEmpty else { throw AgentError.invalid("Favorite name must not be empty.") }
        if let existing = before.first(where: {
            $0.name == title && abs($0.latitude - resolved.latitude) < 0.000001
                && abs($0.longitude - resolved.longitude) < 0.000001
        }) {
            return existing
        }
        let favorite = WeatherSavedLocationSnapshot(
            id: UUID().uuidString, name: title, preciseName: resolved.preciseName, country: resolved.country,
            latitude: resolved.latitude, longitude: resolved.longitude, timeZone: resolvedTimeZone)
        try store.add(favorite)
        let after = try MutationVerification.readback(type: "location", id: favorite.id) { try makeStore().all() }
        guard let saved = after.first(where: { $0.id == favorite.id }), saved.name == favorite.name,
            abs(saved.latitude - favorite.latitude) < 0.000001, abs(saved.longitude - favorite.longitude) < 0.000001,
            Set(before.map(\.id)).isSubset(of: Set(after.map(\.id)))
        else {
            throw PlatformError.mutationUnverified(
                type: "location", id: favorite.id,
                reason: "Favorite \(favorite.id) did not round-trip. List saved locations before retrying.")
        }
        return saved
    }

    /// Removes one favorite selected by id or exact name, verifying absence and that every other
    /// favorite survived.
    @discardableResult
    public func removeLocation(idOrName: String) throws -> WeatherSavedLocationSnapshot {
        let trimmed = idOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlatformError.invalidArgument("Location identifier or name cannot be empty.")
        }
        let store = try makeStore()
        let before = try store.all()
        let favorite = try EntityResolver.resolve(
            trimmed, in: before, type: "saved location", id: \.id, name: \.name, detail: \.country,
            policy: .exactName)
        try store.remove(id: favorite.id)
        let after = try MutationVerification.readback(type: "location", id: favorite.id) { try makeStore().all() }
        guard !after.contains(where: { $0.id == favorite.id }),
            Set(before.filter { $0.id != favorite.id }.map(\.id)).isSubset(of: Set(after.map(\.id)))
        else {
            throw PlatformError.mutationUnverified(
                type: "location", id: favorite.id,
                reason: "Favorite \(favorite.id) removal did not round-trip. List saved locations before retrying.")
        }
        return favorite
    }
}
