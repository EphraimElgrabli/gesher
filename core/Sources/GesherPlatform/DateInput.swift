import Foundation

/// A parsed date expression. `hasTime` is false for day-only input ("today", "2026-11-05"),
/// so callers can decide between all-day semantics and a default time.
public struct ResolvedDate: Equatable, Sendable {
    public let date: Date
    public let hasTime: Bool
    public let timeZone: TimeZone

    /// ISO 8601 with the offset of `timeZone`, e.g. `2026-11-05T09:00:00+02:00`, or `2026-11-05` for day-only input.
    public var iso: String {
        hasTime ? DateOutput.iso(date, timeZone: timeZone) : DateOutput.day(date, timeZone: timeZone)
    }
}

/// Natural date input shared by every operation. Accepted forms (English and Hebrew day words):
///
/// - `now`, `today`, `tonight` (20:00), `tomorrow`, `yesterday`, `היום`, `מחר`, `אתמול`
/// - weekdays: `monday`, `next friday` (always the next future occurrence)
/// - relative: `in 2 hours`, `in 3 days`, `+30m`, `+2h`, `+1d`, `+1w`, `in 2 months`
/// - past: `7 days ago`, `2 weeks ago`, `3 months ago` (that day), `2 hours ago`, `-1d`, `last friday`
/// - any of the above followed by a time: `tomorrow 9:00`, `friday 18:30`, `today 9am`, `9pm`
/// - ISO: `2026-11-05`, `2026-11-05 14:00`, `2026-11-05T14:00`, `2026-11-05T14:00:00+02:00`, `...Z`
///
/// Times without an explicit offset are interpreted in `timeZone` (the user's by default).
public struct DateInput: Sendable {
    public let timeZone: TimeZone
    public let now: Date

    public init(timeZone: TimeZone = .current, now: Date = Date()) {
        self.timeZone = timeZone
        self.now = now
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public func parse(_ text: String) throws -> ResolvedDate {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = parseISO(input) { return iso }
        let lowered = input.lowercased()
        var tokens = lowered.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { throw invalid(text) }

        if tokens == ["now"] || tokens == ["עכשיו"] {
            return ResolvedDate(date: now, hasTime: true, timeZone: timeZone)
        }
        if let relative = try parseRelative(tokens) { return relative }

        // Trailing time ("9:00", "9am", "18:30", "9 pm").
        var time: (hour: Int, minute: Int)?
        if tokens.count >= 2, ["am", "pm"].contains(tokens.last!), let parsed = parseTime(tokens.suffix(2).joined()) {
            time = parsed
            tokens.removeLast(2)
        } else if let last = tokens.last, let parsed = parseTime(last) {
            time = parsed
            tokens.removeLast()
        }
        if tokens.first == "at" { tokens.removeFirst() }
        if tokens.last == "at" { tokens.removeLast() }

        let today = calendar.startOfDay(for: now)
        var day: Date
        switch tokens.joined(separator: " ") {
        case "" where time != nil:
            // A bare time means its next occurrence.
            day = today
            if let time, let candidate = at(day, time), candidate <= now {
                day = calendar.date(byAdding: .day, value: 1, to: today)!
            }
        case "today", "היום": day = today
        case "tonight", "הערב":
            day = today
            if time == nil { time = (20, 0) }
        case "tomorrow", "מחר": day = calendar.date(byAdding: .day, value: 1, to: today)!
        case "yesterday", "אתמול": day = calendar.date(byAdding: .day, value: -1, to: today)!
        case let phrase where phrase.hasPrefix("last "):
            guard let weekday = weekday(String(phrase.dropFirst(5))) else { throw invalid(text) }
            day = previousWeekday(weekday, before: today)
        case let phrase:
            guard let weekday = weekday(phrase) else { throw invalid(text) }
            day = nextWeekday(weekday, after: today)
        }
        if let time {
            guard let date = at(day, time) else { throw invalid(text) }
            return ResolvedDate(date: date, hasTime: true, timeZone: timeZone)
        }
        return ResolvedDate(date: day, hasTime: false, timeZone: timeZone)
    }

    private func invalid(_ text: String) -> AgentError {
        AgentError.invalid(
            "Unrecognized date '\(text)'.",
            hint:
                "Use today, tomorrow 9:00, friday 18:30, in 2 hours, +1d, 7 days ago, last monday, 2026-11-05 or "
                + "2026-11-05T14:00.")
    }

    private func at(_ day: Date, _ time: (hour: Int, minute: Int)) -> Date? {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }

    private func parseRelative(_ tokens: [String]) throws -> ResolvedDate? {
        var amount: Int?
        var unit: String?
        var past = false
        if tokens.count == 3, tokens[0] == "in" {
            amount = Int(tokens[1])
            unit = tokens[2]
        } else if tokens.count == 3, tokens[2] == "ago" {
            amount = Int(tokens[0])
            unit = tokens[1]
            past = true
        } else if tokens.count == 2, tokens[1] == "ago", let digits = Optional(tokens[0].prefix { $0.isNumber }),
            !digits.isEmpty
        {
            amount = Int(digits)
            unit = String(tokens[0].dropFirst(digits.count))
            past = true
        } else if tokens.count == 1, let sign = tokens[0].first, sign == "+" || sign == "-" {
            let body = tokens[0].dropFirst()
            let digits = body.prefix { $0.isNumber }
            amount = Int(digits).map { sign == "-" ? -$0 : $0 }
            unit = String(body.dropFirst(digits.count))
        } else {
            return nil
        }
        guard var amount, let unit else { return nil }
        if past { amount = -amount }
        let component: Calendar.Component
        switch unit {
        case "m", "min", "mins", "minute", "minutes": component = .minute
        case "h", "hr", "hrs", "hour", "hours": component = .hour
        case "d", "day", "days": component = .day
        case "w", "week", "weeks": component = .weekOfYear
        case "mo", "month", "months": component = .month
        case "y", "yr", "year", "years": component = .year
        default: return nil
        }
        // "7 days ago" names a day (like "yesterday"); "2 hours ago" names an instant.
        if past, ![.minute, .hour].contains(component) {
            guard let date = calendar.date(byAdding: component, value: amount, to: calendar.startOfDay(for: now))
            else { return nil }
            return ResolvedDate(date: date, hasTime: false, timeZone: timeZone)
        }
        guard let date = calendar.date(byAdding: component, value: amount, to: now) else { return nil }
        return ResolvedDate(date: date, hasTime: true, timeZone: timeZone)
    }

    private func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
        var text = token
        var offset = 0
        if text.hasSuffix("am") || text.hasSuffix("pm") {
            offset = text.hasSuffix("pm") ? 12 : 0
            text.removeLast(2)
            let parts = text.split(separator: ":")
            guard (1...2).contains(parts.count), let hour = Int(parts[0]), (1...12).contains(hour) else { return nil }
            let minute = parts.count == 2 ? Int(parts[1]) : 0
            guard let minute, (0...59).contains(minute) else { return nil }
            return ((hour % 12) + offset, minute)
        }
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    private func weekday(_ phrase: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let word = phrase.hasPrefix("next ") ? String(phrase.dropFirst(5)) : phrase
        if let index = names.firstIndex(where: { $0 == word || ($0.hasPrefix(word) && word.count >= 3) }) {
            return index + 1
        }
        return nil
    }

    private func previousWeekday(_ weekday: Int, before day: Date) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(after: day, matching: components, matchingPolicy: .nextTime, direction: .backward)
            ?? day
    }

    private func nextWeekday(_ weekday: Int, after day: Date) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(after: day, matching: components, matchingPolicy: .nextTime) ?? day
    }

    private func parseISO(_ input: String) -> ResolvedDate? {
        guard input.first?.isNumber == true, input.count >= 10 else { return nil }
        let withOffset = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds],
        ] {
            withOffset.formatOptions = options
            if let date = withOffset.date(from: input) {
                return ResolvedDate(date: date, hasTime: true, timeZone: timeZone)
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        for (format, hasTime) in [
            ("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm:ss", true),
            ("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false),
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: input) {
                return ResolvedDate(date: date, hasTime: hasTime, timeZone: timeZone)
            }
        }
        return nil
    }
}

/// Output formatting for dates: ISO 8601 with an explicit offset, never fractional seconds.
public enum DateOutput {
    public static func iso(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// Parses ISO 8601 strings produced by native adapters (with or without fractional seconds).
    public static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
