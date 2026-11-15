import GesherPlatform
import Foundation

/// A GeoServices directions failure for one transport mode. It does not establish that the mode
/// is unsupported everywhere, and nothing about the route may be estimated from it.
struct NativeDirectionsError: CLIErrorCodeProviding, LocalizedError {
    let native: NSError
    let transportType: String
    var code: String { "route_service_error" }
    var details: [String: String] {
        native.userInfo["DirectionsError"].map { ["reason": Self.reason(String(describing: $0))] } ?? [:]
    }
    var errorDescription: String? {
        let mode = ["automobile": "driving", "bicycle": "cycling"][transportType] ?? transportType
        return "Apple Maps returned no \(mode) route: \(native.localizedDescription)"
    }

    /// The service's user-facing text ("Title: ...", "Content: ...") and problem type, without
    /// object addresses.
    static func reason(_ description: String) -> String {
        var problem: String?
        var title: String?
        var content: String?
        for line in description.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("problemType = ") {
                problem = text.dropFirst("problemType = ".count).trimmingCharacters(
                    in: CharacterSet(charactersIn: "\";"))
            } else if text.hasPrefix("Title:") {
                title = text.dropFirst("Title:".count).trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("Content:") {
                content = text.dropFirst("Content:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        let parts = [problem, title, content].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? description : parts.joined(separator: ": ")
    }
}
