import Foundation

/// Semantic version (`major.minor.patch[-prerelease]`) for comparing Gesher releases.
public struct SemVer: Comparable, Sendable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(parsing raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        let buildSplit = trimmed.split(separator: "+", maxSplits: 1)
        let withoutBuild = String(buildSplit[0])
        let preSplit = withoutBuild.split(separator: "-", maxSplits: 1)
        let coreParts = preSplit[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
            let major = Int(coreParts[0]), major >= 0,
            let minor = Int(coreParts[1]), minor >= 0,
            let patch = Int(coreParts[2]), patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        if preSplit.count == 2 {
            let pre = String(preSplit[1])
            guard !pre.isEmpty else { return nil }
            self.prerelease = pre
        } else {
            self.prerelease = nil
        }
    }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (_?, nil): return true
        case (nil, _?): return false
        case (let a?, let b?): return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

/// User-controlled update behavior stored in `~/.config/gesher/config.json` under `updates.mode`.
public enum UpdatePolicy: String, Sendable, CaseIterable {
    case ask
    case always
    case never

    public static func parse(_ raw: String?) -> UpdatePolicy {
        guard let raw else { return .ask }
        return UpdatePolicy(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .ask
    }
}

/// Cached result of checking GitHub for the latest Gesher release.
public struct UpdateCheckCache: Codable, Sendable, Equatable {
    public let checkedAt: Date
    public let latestVersion: String
    public let releaseURL: String

    public init(checkedAt: Date, latestVersion: String, releaseURL: String) {
        self.checkedAt = checkedAt
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
    }
}

/// Current update status combining installed version, cached/fetched latest version and user policy.
public struct UpdateStatus: Sendable, Equatable {
    public let installed: String
    public let latest: String?
    public let updateAvailable: Bool
    public let skipped: Bool
    public let policy: UpdatePolicy
    public let releaseURL: String?
    public let checkedAt: Date?

    public var shouldNotify: Bool {
        updateAvailable && !skipped && policy != .never
    }
}

/// Checks GitHub Releases for newer Gesher versions with local TTL caching so CLI and MCP runs
/// stay fast and never block on network I/O during normal commands.
public final class UpdateChecker: @unchecked Sendable {
    public static let defaultRepo = "EphraimElgrabli/gesher"
    public static let defaultCheckInterval: TimeInterval = 6 * 3600

    public typealias LatestReleaseFetcher = @Sendable () -> (version: String, releaseURL: String)?

    public let repo: String
    public let cacheURL: URL
    public let checkInterval: TimeInterval
    private let configLoader: () -> UserConfig
    private let environment: [String: String]
    private let fetcher: LatestReleaseFetcher

    public init(
        repo: String = UpdateChecker.defaultRepo,
        cacheURL: URL? = nil,
        checkInterval: TimeInterval? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configLoader: @escaping () -> UserConfig = { UserConfig.load() },
        fetcher: LatestReleaseFetcher? = nil
    ) {
        self.repo = repo
        self.environment = environment
        self.configLoader = configLoader
        if let cacheURL {
            self.cacheURL = cacheURL
        } else if let custom = environment["GESHER_UPDATE_CACHE"], !custom.isEmpty {
            self.cacheURL = URL(fileURLWithPath: custom)
        } else {
            self.cacheURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/gesher/update-check.json")
        }
        let configuredHours = configLoader().value("updates", "checkIntervalHours").flatMap(Double.init)
        self.checkInterval =
            checkInterval
            ?? configuredHours.flatMap { $0 > 0 ? $0 * 3600 : nil }
            ?? Self.defaultCheckInterval
        self.fetcher = fetcher ?? { Self.fetchLatestFromGitHub(repo: repo) }
    }

    public var isDisabledByEnvironment: Bool {
        if let flag = environment["GESHER_NO_UPDATE_CHECK"]?.lowercased(), ["1", "true", "yes"].contains(flag) {
            return true
        }
        if let ci = environment["CI"]?.lowercased(), ["1", "true", "yes"].contains(ci) {
            return true
        }
        return false
    }

    public func readCache() -> UpdateCheckCache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UpdateCheckCache.self, from: data)
    }

    public func writeCache(_ cache: UpdateCheckCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        try? PrivateStorage.createDirectory(cacheURL.deletingLastPathComponent())
        try? PrivateStorage.write(data, to: cacheURL)
    }

    /// Evaluates update status from the local cache without doing network I/O.
    public func cachedStatus(installed: String, now: Date = Date()) -> UpdateStatus {
        let config = configLoader()
        let policy = UpdatePolicy.parse(config.value("updates", "mode"))
        let skippedVersion = config.value("updates", "skippedVersion")
        let cache = readCache()
        let latest = cache?.latestVersion
        let available = Self.isNewer(latest: latest, than: installed)
        let skipped = available && latest != nil && skippedVersion == latest
        return UpdateStatus(
            installed: installed, latest: latest, updateAvailable: available, skipped: skipped, policy: policy,
            releaseURL: cache?.releaseURL, checkedAt: cache?.checkedAt)
    }

    /// Whether the cache is missing or older than `checkInterval`.
    public func isCacheStale(now: Date = Date()) -> Bool {
        guard let cache = readCache() else { return true }
        return now.timeIntervalSince(cache.checkedAt) >= checkInterval
    }

    /// Checks GitHub synchronously (used by explicit `--check` or background refresh) and updates the cache.
    @discardableResult
    public func refreshNow(installed: String, now: Date = Date()) -> UpdateStatus {
        if let fetched = fetcher() {
            writeCache(
                UpdateCheckCache(
                    checkedAt: now, latestVersion: fetched.version, releaseURL: fetched.releaseURL))
        }
        return cachedStatus(installed: installed, now: now)
    }

    /// Triggers a non-blocking background refresh when the cache is stale and checks are enabled.
    public func refreshInBackgroundIfStale(now: Date = Date()) {
        guard !isDisabledByEnvironment else { return }
        let policy = UpdatePolicy.parse(configLoader().value("updates", "mode"))
        guard policy != .never, isCacheStale(now: now) else { return }
        let fetcher = self.fetcher
        let cacheURL = self.cacheURL
        DispatchQueue.global(qos: .utility).async {
            guard let fetched = fetcher() else { return }
            let cache = UpdateCheckCache(
                checkedAt: Date(), latestVersion: fetched.version, releaseURL: fetched.releaseURL)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(cache) {
                try? PrivateStorage.createDirectory(cacheURL.deletingLastPathComponent())
                try? PrivateStorage.write(data, to: cacheURL)
            }
        }
    }

    public static func isNewer(latest: String?, than installed: String) -> Bool {
        guard let latest,
            let latestSemVer = SemVer(parsing: latest),
            let installedSemVer = SemVer(parsing: installed)
        else { return false }
        return installedSemVer < latestSemVer
    }

    /// Resolves `https://github.com/<repo>/releases/latest` redirect without consuming GitHub API rate limits.
    public static func fetchLatestFromGitHub(repo: String = defaultRepo, timeout: TimeInterval = 3) -> (
        version: String, releaseURL: String
    )? {
        guard let url = URL(string: "https://github.com/\(repo)/releases/latest") else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Gesher-Updater", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var resolvedURL: URL?
        let task = session.dataTask(with: request) { _, response, _ in
            resolvedURL = response?.url
            sem.signal()
        }
        task.resume()
        guard sem.wait(timeout: .now() + timeout + 0.5) == .success,
            let finalURL = resolvedURL,
            let version = extractVersion(fromReleaseURL: finalURL.absoluteString)
        else { return nil }
        return (version: version, releaseURL: finalURL.absoluteString)
    }

    public static func extractVersion(fromReleaseURL urlString: String) -> String? {
        guard let range = urlString.range(of: "/releases/tag/") else { return nil }
        var tag = String(urlString[range.upperBound...])
        if let query = tag.firstIndex(of: "?") { tag = String(tag[..<query]) }
        if let hash = tag.firstIndex(of: "#") { tag = String(tag[..<hash]) }
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        return SemVer(parsing: tag)?.description
    }
}
