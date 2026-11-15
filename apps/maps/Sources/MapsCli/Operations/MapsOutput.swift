import GesherKit
import GesherPlatform
import Foundation
import MapsCore

/// Agent-facing output models: user fields only, rounded, local times, absent values omitted.

private func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
private func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

struct PlacesOutput: Encodable, Sendable {
    let places: [PlaceSummary]
}

struct PlaceSummary: Encodable, Sendable {
    let id: String?
    let name: String
    let address: String?
    let category: String?
    let latitude: Double
    let longitude: Double
    /// Straight-line distance from the search center, when one was given.
    let distanceKm: Double?

    init(_ place: MapPlaceSnapshot, from center: MapCoordinateSnapshot?) {
        id = place.id
        name = place.name
        address = place.formattedAddress
        category = place.category
        latitude = round4(place.coordinate.latitude)
        longitude = round4(place.coordinate.longitude)
        distanceKm = center.map { round1(place.coordinate.distance(to: $0) / 1000) }
    }
}

struct PlaceDetail: Encodable, Sendable {
    struct Rating: Encodable, Sendable {
        let percent: Int
        let count: Int
    }

    struct Day: Encodable, Sendable {
        let day: String
        /// "09:00–18:00", several ranges joined by ", ", or "closed".
        let hours: String
    }

    let id: String?
    let name: String
    let address: String?
    let category: String?
    let phone: String?
    let website: String?
    let latitude: Double
    let longitude: Double
    let timeZone: String?
    let openNow: Bool?
    let hours: [Day]?
    let rating: Rating?

    init(_ place: MapPlaceSnapshot, now: Date = Date()) {
        id = place.id
        name = place.name
        address = place.formattedAddress
        category = place.category
        phone = place.phoneNumber
        website = place.url
        latitude = round4(place.coordinate.latitude)
        longitude = round4(place.coordinate.longitude)
        timeZone = place.timeZone
        rating = place.ratingPercent.flatMap { percent in
            place.ratingCount.map { Rating(percent: Int(percent.rounded()), count: $0) }
        }
        guard let days = place.hours else {
            hours = nil
            openNow = nil
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let names = calendar.weekdaySymbols
        hours = days.map { day in
            Day(
                day: names[day.weekday - 1],
                hours: day.intervals.isEmpty ? "closed" : day.intervals.map(Self.range).joined(separator: ", "))
        }
        openNow = place.timeZone.flatMap(TimeZone.init(identifier:)).map { Self.isOpen(days, at: now, in: $0) }
    }

    static func range(_ interval: ClosedRange<Double>) -> String {
        if interval.lowerBound <= 0, interval.upperBound >= 86_400 { return "open 24 hours" }
        func clock(_ seconds: Double) -> String {
            if seconds == 86_400 { return "24:00" }
            let minutes = Int(seconds / 60) % (24 * 60)
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        return clock(interval.lowerBound) + "–" + clock(interval.upperBound)
    }

    /// Open at `date` in the place's zone, including a previous day's range that runs past midnight.
    static func isOpen(_ days: [MapDailyHoursSnapshot], at date: Date, in zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let weekday = calendar.component(.weekday, from: date)
        let seconds = date.timeIntervalSince(calendar.startOfDay(for: date))
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return days.contains { day in
            (day.weekday == weekday && day.intervals.contains { $0.contains(seconds) })
                || (day.weekday == yesterday && day.intervals.contains { $0.contains(seconds + 86_400) })
        }
    }
}

struct RouteOutput: Encodable, Sendable {
    struct Step: Encodable, Sendable {
        let instruction: String?
        let road: String?
        let meters: Int
    }

    let from: PlaceSummary
    let to: PlaceSummary
    let mode: TravelMode
    let distanceKm: Double?
    let durationMin: Int
    let departAt: String
    let arriveAt: String
    let steps: [Step]?

    init(_ route: MapRouteSnapshot, mode: TravelMode, timepoint: MapTimepoint?, steps includeSteps: Bool) {
        from = PlaceSummary(route.origin, from: nil)
        to = PlaceSummary(route.destination, from: nil)
        self.mode = mode
        distanceKm = route.distanceMeters.map { round1($0 / 1000) }
        durationMin = Int((route.durationSeconds / 60).rounded())
        // Scheduled times (transit) win; otherwise derive them from the requested timepoint.
        let depart: Date
        let arrive: Date
        if let departure = route.departure, let arrival = route.arrival {
            (depart, arrive) = (departure, arrival)
        } else if let timepoint, timepoint.kind == .arriveBy {
            (depart, arrive) = (timepoint.date.addingTimeInterval(-route.durationSeconds), timepoint.date)
        } else {
            let start = timepoint?.date ?? Date()
            (depart, arrive) = (start, start.addingTimeInterval(route.durationSeconds))
        }
        let originZone = route.origin.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let destinationZone = route.destination.timeZone.flatMap(TimeZone.init(identifier:)) ?? originZone
        departAt = DateOutput.iso(depart, timeZone: originZone)
        arriveAt = DateOutput.iso(arrive, timeZone: destinationZone)
        let routeSteps = route.steps.map {
            Step(instruction: $0.instruction, road: $0.roadName, meters: Int($0.distanceMeters.rounded()))
        }
        steps = includeSteps && !routeSteps.isEmpty ? routeSteps : nil
    }

    var eta: Eta {
        Eta(mode: mode, distanceKm: distanceKm, durationMin: durationMin, departAt: departAt, arriveAt: arriveAt)
    }
}

struct Eta: Encodable, Sendable {
    let mode: TravelMode
    let distanceKm: Double?
    let durationMin: Int
    let departAt: String
    let arriveAt: String
}

struct EtaOutput: Encodable, Sendable, PartialFailureReporting {
    let from: PlaceSummary
    let to: PlaceSummary
    let results: BatchResult<Eta>

    var succeeded: Int { results.succeeded }
    var failed: Int { results.failed }

    enum CodingKeys: String, CodingKey { case from, to, results, succeeded, failed }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(results.results, forKey: .results)
        try container.encode(succeeded, forKey: .succeeded)
        try container.encode(failed, forKey: .failed)
    }
}
