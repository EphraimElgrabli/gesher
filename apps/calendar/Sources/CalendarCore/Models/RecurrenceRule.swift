import GesherPlatform
import Foundation

/// A recurrence rule, convertible to and from RFC 5545 RRULE text and the CalendarDatabase
/// native form (`frequencyRaw` 1–4 plus a `specifier` such as `D=0MO,+2TU;M=15;O=3;S=-1`).
public struct RecurrenceRule: Codable, Sendable, Equatable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly

        public var nativeRaw: Int { Self.allCases.firstIndex(of: self)! + 1 }
        public init?(nativeRaw: Int) {
            guard (1...4).contains(nativeRaw) else { return nil }
            self = Self.allCases[nativeRaw - 1]
        }
    }

    /// A weekday, optionally with an ordinal: `MO` (every Monday), `2TU` (second Tuesday), `-1FR` (last Friday).
    public struct Day: Codable, Sendable, Equatable {
        public static let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        public let weekday: Int  // 1 = Sunday ... 7 = Saturday
        public let ordinal: Int  // 0 = every

        public init(weekday: Int, ordinal: Int = 0) {
            self.weekday = weekday
            self.ordinal = ordinal
        }

        public var rrule: String { (ordinal == 0 ? "" : String(ordinal)) + Self.codes[weekday - 1] }
        var native: String {
            (ordinal == 0 ? "0" : (ordinal > 0 ? "+" : "") + String(ordinal)) + Self.codes[weekday - 1]
        }

        /// Parses `MO`, `mon`, `monday`, `2TU`, `+2TU`, `-1FR`.
        public static func parse(_ text: String) -> Day? {
            let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
            let sign = trimmed.prefix { "+-0123456789".contains($0) }
            let name = String(trimmed.dropFirst(sign.count))
            let names = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
            guard name.count >= 2,
                let index = codes.firstIndex(of: String(name.prefix(2))),
                name.count == 2 || names[index].hasPrefix(name)
            else { return nil }
            let ordinal = sign.isEmpty ? 0 : Int(sign.replacingOccurrences(of: "+", with: ""))
            guard let ordinal, (-53...53).contains(ordinal) else { return nil }
            return Day(weekday: index + 1, ordinal: ordinal)
        }
    }

    public var frequency: Frequency
    public var interval: Int
    public var days: [Day]
    public var monthDays: [Int]
    public var months: [Int]
    public var setPositions: [Int]
    public var count: Int?
    public var until: Date?

    public init(
        frequency: Frequency, interval: Int = 1, days: [Day] = [], monthDays: [Int] = [], months: [Int] = [],
        setPositions: [Int] = [], count: Int? = nil, until: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.days = days
        self.monthDays = monthDays
        self.months = months
        self.setPositions = setPositions
        self.count = count
        self.until = until
    }

    // MARK: Native form

    public var specifier: String? {
        var parts: [String] = []
        if !days.isEmpty { parts.append("D=" + days.map(\.native).joined(separator: ",")) }
        if !monthDays.isEmpty { parts.append("M=" + monthDays.map(String.init).joined(separator: ",")) }
        if !months.isEmpty { parts.append("O=" + months.map(String.init).joined(separator: ",")) }
        if !setPositions.isEmpty { parts.append("S=" + setPositions.map(String.init).joined(separator: ",")) }
        return parts.isEmpty ? nil : parts.joined(separator: ";")
    }

    public init?(nativeFrequency: Int, interval: Int, specifier: String?, count: Int?, until: Date?) {
        guard let frequency = Frequency(nativeRaw: nativeFrequency) else { return nil }
        self.init(frequency: frequency, interval: max(1, interval), count: (count ?? 0) > 0 ? count : nil, until: until)
        for part in (specifier ?? "").split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let values = pieces[1].split(separator: ",").map(String.init)
            switch pieces[0] {
            case "D": days = values.compactMap(Day.parse)
            case "M": monthDays = values.compactMap { Int($0) }
            case "O": months = values.compactMap { Int($0) }
            case "S": setPositions = values.compactMap { Int($0) }
            default: continue
            }
        }
    }

    // MARK: RRULE text

    public var rrule: String {
        var parts = ["FREQ=" + frequency.rawValue.uppercased()]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if !days.isEmpty { parts.append("BYDAY=" + days.map(\.rrule).joined(separator: ",")) }
        if !monthDays.isEmpty { parts.append("BYMONTHDAY=" + monthDays.map(String.init).joined(separator: ",")) }
        if !months.isEmpty { parts.append("BYMONTH=" + months.map(String.init).joined(separator: ",")) }
        if !setPositions.isEmpty { parts.append("BYSETPOS=" + setPositions.map(String.init).joined(separator: ",")) }
        if let count { parts.append("COUNT=\(count)") }
        if let until {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            parts.append("UNTIL=" + formatter.string(from: until))
        }
        return parts.joined(separator: ";")
    }

    /// Parses a keyword (`daily`, `weekly`, `monthly`, `yearly`, `weekdays`) or an RRULE
    /// (`FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2;COUNT=5`, optional `RRULE:` prefix).
    public static func parse(_ text: String, dateInput: DateInput = DateInput()) throws -> RecurrenceRule {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if let frequency = Frequency(rawValue: lowered) { return RecurrenceRule(frequency: frequency) }
        if lowered == "weekdays" {
            return RecurrenceRule(frequency: .weekly, days: (2...6).map { Day(weekday: $0) })
        }
        let body = trimmed.uppercased().hasPrefix("RRULE:") ? String(trimmed.dropFirst(6)) : trimmed
        var fields: [String: String] = [:]
        for part in body.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { throw invalid(text) }
            fields[pieces[0].uppercased()] = pieces[1]
        }
        guard let frequency = fields["FREQ"].flatMap({ Frequency(rawValue: $0.lowercased()) }) else {
            throw invalid(text)
        }
        func ints(_ key: String, _ range: ClosedRange<Int>) throws -> [Int] {
            guard let value = fields[key] else { return [] }
            return try value.split(separator: ",").map {
                guard let number = Int($0), range.contains(number), number != 0 else { throw invalid(text) }
                return number
            }
        }
        var rule = RecurrenceRule(frequency: frequency)
        if let interval = fields["INTERVAL"] {
            guard let value = Int(interval), (1...999).contains(value) else { throw invalid(text) }
            rule.interval = value
        }
        if let days = fields["BYDAY"] {
            rule.days = try days.split(separator: ",").map {
                guard let day = Day.parse(String($0)) else { throw invalid(text) }
                return day
            }
        }
        rule.monthDays = try ints("BYMONTHDAY", -31...31)
        rule.months = try ints("BYMONTH", 1...12)
        rule.setPositions = try ints("BYSETPOS", -366...366)
        if let count = fields["COUNT"] {
            guard let value = Int(count), value > 0 else { throw invalid(text) }
            rule.count = value
        }
        if let until = fields["UNTIL"] {
            rule.until = try parseUntil(until, dateInput: dateInput)
        }
        try rule.validate()
        return rule
    }

    public func validate() throws {
        guard (1...999).contains(interval) else {
            throw AgentError.invalid("Repeat interval must be between 1 and 999.")
        }
        if count != nil && until != nil {
            throw AgentError.invalid("A repeat ends after a count or on a date, not both.")
        }
        if let count, count < 1 { throw AgentError.invalid("Repeat count must be at least 1.") }
        if frequency == .daily || frequency == .weekly, days.contains(where: { $0.ordinal != 0 }) {
            throw AgentError.invalid(
                "Ordinal weekdays like 2TU apply to monthly or yearly repeats.",
                hint: "Use plain days (MO,WE) for weekly repeats.")
        }
    }

    private static func parseUntil(_ text: String, dateInput: DateInput) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (format, zone) in [
            ("yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC")!), ("yyyyMMdd'T'HHmmss", dateInput.timeZone),
            ("yyyyMMdd", dateInput.timeZone),
        ] {
            formatter.dateFormat = format
            formatter.timeZone = zone
            if let date = formatter.date(from: text) {
                // A day-only UNTIL includes that whole day.
                return format == "yyyyMMdd" ? date.addingTimeInterval(86400 - 1) : date
            }
        }
        let resolved = try dateInput.parse(text)
        return resolved.hasTime ? resolved.date : resolved.date.addingTimeInterval(86400 - 1)
    }

    private static func invalid(_ text: String) -> AgentError {
        AgentError.invalid(
            "Unrecognized repeat rule '\(text)'.",
            hint:
                "Use daily, weekly, monthly, yearly, weekdays, or an RRULE such as FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2;COUNT=5."
        )
    }
}
