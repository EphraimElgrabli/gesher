import Foundation

/// The filters of a custom smart list, in the terms the Reminders app shows. Converts to and from
/// ReminderKit's `filterData` JSON (serialization v2, as written by the app since 2022):
///
/// ```
/// {"operation":"and|or","hashtags":{"any":""}|{"untagged":""}|{"hashtags":{"include":[],"exclude":[],"operation":"and|or"}},
///  "date":{"any":""}|{"noDate":""}|{"today":<includePastDue>}|{"onDate":"dd-MM-yyyy"}|{"beforeDate":…}|{"afterDate":…}
///        |{"dateRange":["dd-MM-yyyy","dd-MM-yyyy"]}|{"relativeRange":["inNext|inPast","3","day|week|month|year|hour"]}
///        |{"relativeRange":{"direction":…,"magnitude":"3","units":…,"includePastDue":true}},
///  "time":{"any|noTime|morning|afternoon|evening|night":""}, "priorities":["low","medium","high","none"],
///  "flagged":true, "location":{"any":""}|{"noLocation":""}|{"vehicle":"connected|disconnected"},
///  "lists":{"include":[<list UUID>],"exclude":[<list UUID>]}}
/// ```
/// Legacy v1 data (`{"hashtags":{"hashtags":[…]}}`, `"relativeRange":[…]`) is read too. Writes always
/// use v2, so the smart list's `minimumSupportedVersion` must be `nativeVersion`.
public struct SmartListFilter: Codable, Sendable, Equatable {
    /// "all" (every filter must match) or "any".
    public var match: String?
    public var tags: [String]?
    public var excludeTags: [String]?
    /// "all" or "any" of `tags`.
    public var tagsMatch: String?
    /// true: tasks with any tag; false: tasks without tags.
    public var tagged: Bool?
    /// any, none, today, "on DAY", "before DAY", "after DAY", "between DAY and DAY", "next N units", "past N units".
    public var date: String?
    public var includeOverdue: Bool?
    /// any, none, morning, afternoon, evening, night.
    public var time: String?
    /// low, medium, high, none.
    public var priorities: [String]?
    public var flagged: Bool?
    /// any, none, car-connected, car-disconnected.
    public var location: String?
    /// List ids (REMCDList:UUID).
    public var lists: [String]?
    public var excludeLists: [String]?
    /// Native filter keys this version does not understand, as raw JSON (kept on update).
    public var other: [String: String]?

    public init(
        match: String? = nil, tags: [String]? = nil, excludeTags: [String]? = nil, tagsMatch: String? = nil,
        tagged: Bool? = nil, date: String? = nil, includeOverdue: Bool? = nil, time: String? = nil,
        priorities: [String]? = nil, flagged: Bool? = nil, location: String? = nil, lists: [String]? = nil,
        excludeLists: [String]? = nil, other: [String: String]? = nil
    ) {
        self.match = match
        self.tags = tags
        self.excludeTags = excludeTags
        self.tagsMatch = tagsMatch
        self.tagged = tagged
        self.date = date
        self.includeOverdue = includeOverdue
        self.time = time
        self.priorities = priorities
        self.flagged = flagged
        self.location = location
        self.lists = lists
        self.excludeLists = excludeLists
        self.other = other
    }

    public var isEmpty: Bool {
        tags == nil && excludeTags == nil && tagged == nil && date == nil && time == nil && priorities == nil
            && flagged == nil && location == nil && lists == nil && excludeLists == nil && (other ?? [:]).isEmpty
    }

    static let timeValues = [
        "any": "any", "none": "noTime", "morning": "morning", "afternoon": "afternoon",
        "evening": "evening", "night": "night",
    ]
    static let locationValues = [
        "any": ["any": ""], "none": ["noLocation": ""],
        "car-connected": ["vehicle": "connected"], "car-disconnected": ["vehicle": "disconnected"],
    ]
    static let units = ["hour", "day", "week", "month", "year"]
    /// The filter serialization version the app writes (v2), as a smart list's minimumSupportedVersion.
    public static let nativeVersion = 20_220_430

    private static let nativeDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func isoDay(fromNative text: String) -> String? {
        nativeDay.date(from: text).map { isoDay.string(from: $0) }
    }

    static func nativeDay(fromISO text: String) throws -> String {
        guard let date = isoDay.date(from: text) else {
            throw ReminderCLIError.invalidArgument("Smart list dates must be days such as 2026-11-05, not '\(text)'.")
        }
        return nativeDay.string(from: date)
    }

    // MARK: - Native JSON → filter

    /// Reads native `filterData`. Unknown keys are kept in `other` rather than dropped.
    public init(native data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReminderCLIError.fetchFailed("Smart list filter data is not a JSON object.")
        }
        self.init()
        var other: [String: String] = [:]
        func keep(_ key: String) {
            if let value = object[key],
                let raw = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
            {
                other[key] = String(data: raw, encoding: .utf8)
            }
        }
        for key in object.keys.sorted() {
            let value = object[key]
            switch key {
            case "operation":
                match = (value as? String) == "or" ? "any" : "all"
            case "flagged":
                guard let flag = value as? Bool else { keep(key); continue }
                flagged = flag
            case "priorities":
                guard let values = value as? [String] else { keep(key); continue }
                priorities = values
            case "time":
                guard let dictionary = value as? [String: Any], let native = dictionary.keys.first,
                    let name = Self.timeValues.first(where: { $0.value == native })?.key
                else { keep(key); continue }
                time = name
            case "location":
                guard let dictionary = value as? [String: String],
                    let name = Self.locationValues.first(where: { $0.value == dictionary })?.key
                else { keep(key); continue }
                location = name
            case "lists":
                guard let dictionary = value as? [String: Any] else { keep(key); continue }
                let include = (dictionary["include"] as? [String]) ?? []
                let exclude = (dictionary["exclude"] as? [String]) ?? []
                lists = include.isEmpty ? nil : include.map { "REMCDList:\($0)" }
                excludeLists = exclude.isEmpty ? nil : exclude.map { "REMCDList:\($0)" }
            case "hashtags":
                guard let dictionary = value as? [String: Any] else { keep(key); continue }
                if dictionary["any"] != nil {
                    tagged = true
                } else if dictionary["untagged"] != nil {
                    tagged = false
                } else if let legacy = dictionary["hashtags"] as? [String] {
                    tags = legacy
                    tagsMatch = "any"
                } else if let labels = dictionary["hashtags"] as? [String: Any] {
                    let include = (labels["include"] as? [String]) ?? []
                    let exclude = (labels["exclude"] as? [String]) ?? []
                    tags = include.isEmpty ? nil : include
                    excludeTags = exclude.isEmpty ? nil : exclude
                    tagsMatch = (labels["operation"] as? String) == "or" ? "any" : "all"
                } else {
                    keep(key)
                }
            case "date":
                guard let dictionary = value as? [String: Any], let parsed = Self.dateText(dictionary) else {
                    keep(key)
                    continue
                }
                date = parsed.text
                includeOverdue = parsed.includeOverdue
            default:
                keep(key)
            }
        }
        self.other = other.isEmpty ? nil : other
    }

    private static func dateText(_ dictionary: [String: Any]) -> (text: String, includeOverdue: Bool?)? {
        guard dictionary.count == 1, let (kind, value) = dictionary.first else { return nil }
        switch kind {
        case "any": return ("any", nil)
        case "noDate": return ("none", nil)
        case "today": return ("today", (value as? Bool) ?? false)
        case "onDate", "beforeDate", "afterDate":
            guard let text = value as? String, let day = isoDay(fromNative: text) else { return nil }
            let word = ["onDate": "on", "beforeDate": "before", "afterDate": "after"][kind]!
            return ("\(word) \(day)", nil)
        case "dateRange":
            guard let pair = value as? [String], pair.count == 2, let from = isoDay(fromNative: pair[0]),
                let to = isoDay(fromNative: pair[1])
            else { return nil }
            return ("between \(from) and \(to)", nil)
        case "relativeRange":
            var direction: String?
            var magnitude: String?
            var unit: String?
            var overdue = false
            if let parts = value as? [String], parts.count == 3 {
                (direction, magnitude, unit) = (parts[0], parts[1], parts[2])
            } else if let range = value as? [String: Any] {
                direction = range["direction"] as? String
                magnitude = (range["magnitude"] as? String) ?? (range["magnitude"] as? NSNumber)?.stringValue
                unit = range["units"] as? String
                overdue = (range["includePastDue"] as? Bool) ?? false
            }
            guard let direction, let magnitude, let unit, ["inNext", "inPast"].contains(direction) else { return nil }
            let count = Int(magnitude) ?? 0
            return ("\(direction == "inNext" ? "next" : "past") \(magnitude) \(unit)\(count == 1 ? "" : "s")", overdue)
        default: return nil
        }
    }

    // MARK: - Filter → native JSON

    /// The native `filterData` for this filter. Ids in `lists` must be list ids (REMCDList:UUID).
    public func nativeData() throws -> Data {
        var object: [String: Any] = ["operation": match == "any" ? "or" : "and"]
        if let match, !["all", "any"].contains(match) {
            throw ReminderCLIError.invalidArgument("filter.match must be 'all' or 'any'.")
        }
        if let tagged {
            guard tags == nil, excludeTags == nil else {
                throw ReminderCLIError.invalidArgument("Use either filter.tagged or filter.tags/excludeTags.")
            }
            object["hashtags"] = tagged ? ["any": ""] : ["untagged": ""]
        } else if tags != nil || excludeTags != nil {
            if let tagsMatch, !["all", "any"].contains(tagsMatch) {
                throw ReminderCLIError.invalidArgument("filter.tagsMatch must be 'all' or 'any'.")
            }
            let clean: ([String]?) -> [String] = { values in
                (values ?? []).map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }
            }
            object["hashtags"] = [
                "hashtags": [
                    "include": clean(tags), "exclude": clean(excludeTags),
                    "operation": tagsMatch == "any" ? "or" : "and",
                ]
            ]
        }
        if let date { object["date"] = try Self.nativeDate(date, includeOverdue: includeOverdue ?? false) }
        if let time {
            guard let native = Self.timeValues[time.lowercased()] else {
                throw ReminderCLIError.invalidArgument(
                    "filter.time must be one of: " + Self.timeValues.keys.sorted().joined(separator: ", ") + ".")
            }
            object["time"] = [native: ""]
        }
        if let priorities {
            let allowed = ["low", "medium", "high", "none"]
            guard priorities.allSatisfy(allowed.contains) else {
                throw ReminderCLIError.invalidArgument("filter.priorities takes low, medium, high and none.")
            }
            object["priorities"] = priorities
        }
        if let flagged {
            guard flagged else {
                throw ReminderCLIError.invalidArgument(
                    "Smart lists can only require flagged tasks; omit flagged instead of false.")
            }
            object["flagged"] = true
        }
        if let location {
            guard let native = Self.locationValues[location.lowercased()] else {
                throw ReminderCLIError.invalidArgument(
                    "filter.location must be one of: " + Self.locationValues.keys.sorted().joined(separator: ", ")
                        + ".")
            }
            object["location"] = native
        }
        if lists != nil || excludeLists != nil {
            func uuids(_ ids: [String]?) throws -> [String] {
                try (ids ?? []).map { id in
                    guard let uuid = id.split(separator: ":").last.map(String.init), UUID(uuidString: uuid) != nil
                    else { throw ReminderCLIError.invalidArgument("'\(id)' is not a list id.") }
                    return uuid
                }
            }
            object["lists"] = ["include": try uuids(lists), "exclude": try uuids(excludeLists)]
        }
        for (key, raw) in other ?? [:] where object[key] == nil {
            object[key] = try JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)
        }
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    static func nativeDate(_ text: String, includeOverdue: Bool) throws -> [String: Any] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        func invalid() -> ReminderCLIError {
            .invalidArgument(
                "Unrecognized smart list date '\(text)'. Use any, none, today, 'on 2026-11-05', 'before …', "
                    + "'after …', 'between 2026-11-01 and 2026-11-30', 'next 3 days' or 'past 2 weeks'.")
        }
        switch words.first {
        case "any" where words.count == 1: return ["any": ""]
        case "none" where words.count == 1: return ["noDate": ""]
        case "today" where words.count == 1: return ["today": includeOverdue]
        case "on" where words.count == 2: return ["onDate": try nativeDay(fromISO: words[1])]
        case "before" where words.count == 2: return ["beforeDate": try nativeDay(fromISO: words[1])]
        case "after" where words.count == 2: return ["afterDate": try nativeDay(fromISO: words[1])]
        case "between" where words.count == 4 && words[2] == "and":
            return ["dateRange": [try nativeDay(fromISO: words[1]), try nativeDay(fromISO: words[3])]]
        case "next", "past":
            guard words.count == 3, let count = Int(words[1]), count > 0 else { throw invalid() }
            let unit = words[2].hasSuffix("s") ? String(words[2].dropLast()) : words[2]
            guard units.contains(unit) else { throw invalid() }
            let direction = words[0] == "next" ? "inNext" : "inPast"
            return [
                "relativeRange": [
                    "direction": direction, "magnitude": String(count), "units": unit,
                    "includePastDue": includeOverdue,
                ]
            ]
        default: throw invalid()
        }
    }
}
