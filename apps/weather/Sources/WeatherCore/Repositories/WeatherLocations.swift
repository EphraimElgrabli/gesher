import GesherPlatform
import Foundation

extension WeatherReadRepository {
    /// The exact coordinates the caller gave, with the name, country and time zone of the place
    /// reverse geocoding found there.
    static func described(_ point: WeatherSavedLocationSnapshot, by found: WeatherSavedLocationSnapshot?)
        -> WeatherSavedLocationSnapshot
    {
        guard let found else { return point }
        let name = found.name.trimmingCharacters(in: .whitespaces).isEmpty ? point.name : found.name
        return WeatherSavedLocationSnapshot(
            id: point.id, identifierAvailability: point.identifierAvailability, name: name, preciseName: name,
            country: found.country, latitude: point.latitude, longitude: point.longitude,
            timeZone: found.timeZone)
    }

    public func fetchSavedLocations() throws -> [WeatherSavedLocationSnapshot] {
        try WeatherFavoritesStore().all()
    }

    /// Resolves a place selector to a location:
    /// 1. `"lat,lon"` coordinates;
    /// 2. a saved Weather location, by id or name (case/diacritic-insensitive, exact);
    /// 3. otherwise the top native geocoding result for the text.
    /// Without a selector: `fallback` (the configured default place), else the first saved location.
    public func resolvePlace(_ selector: String?, fallback: String? = nil) throws -> WeatherSavedLocationSnapshot {
        let text = (selector ?? fallback)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            let hint = "Pass a place name or 'lat,lon', or set weather.location in ~/.config/gesher/config.json."
            let saved: [WeatherSavedLocationSnapshot]
            do {
                saved = try fetchSavedLocations()
            } catch let error as AgentError where error.code == "permission_denied" {
                throw error
            } catch {
                throw AgentError(
                    code: "invalid_argument",
                    message:
                        "No place given and saved Weather locations could not be read: \(error.localizedDescription)",
                    hint: hint)
            }
            guard let first = saved.first else {
                throw AgentError(
                    code: "invalid_argument", message: "No place given and no saved Weather locations.", hint: hint)
            }
            return first
        }
        if let coordinates = try Self.coordinates(text) {
            let point = WeatherSavedLocationSnapshot(
                id: String(format: "LocationID:%.4f:%.4f", coordinates.latitude, coordinates.longitude),
                identifierAvailability: "derived_coordinates_not_favorite_id",
                name: String(format: "%.4f, %.4f", coordinates.latitude, coordinates.longitude),
                latitude: coordinates.latitude, longitude: coordinates.longitude)
            guard describeCoordinates else { return point }
            // Times are shown in the place's zone, so look it up; without an answer the point is
            // kept as given (times then use the user's zone).
            let found = try? runtime.reverseGeocodePlace(latitude: point.latitude, longitude: point.longitude)
            return Self.described(point, by: found)
        }
        // Saved locations carry the user's own names and time zones; prefer them when one matches.
        if let saved = try? fetchSavedLocations() {
            do {
                return try EntityResolver.resolve(
                    text, in: saved, type: "saved location", id: \.id, name: \.name, detail: \.country,
                    policy: .exactName)
            } catch let error as AgentError where error.code == "ambiguous" {
                throw error
            } catch {}
        }
        return try runtime.geocodeQuery(text)
    }

    /// Parses `"32.08,34.78"` (also with a space or a semicolon). Nil when the text is not coordinates.
    public static func coordinates(_ text: String) throws -> (latitude: Double, longitude: Double)? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " })
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return nil }
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
            throw AgentError.invalid(
                "Coordinates out of range: \(text).", hint: "Use 'latitude,longitude' with -90…90 and -180…180.")
        }
        return (latitude, longitude)
    }
}
