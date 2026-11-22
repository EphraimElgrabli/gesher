import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// Uses Apple's SyncedDataManager to mutate its Coherence CRDT. Never reads or writes
/// preference/database bytes. Runtime values cross the private Swift ABI with their
/// actual metadata, rather than a guessed struct layout. Calls are serialized.
final class WeatherFavoritesStore {
    private let handle: UnsafeMutableRawPointer
    private let provider: AnyObject
    private let manager: AnyObject
    private let dataType: Any.Type
    private let locationType: Any.Type
    private static let lock = NSRecursiveLock()

    init(storageDirectory: URL? = nil) throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/WeatherCore.framework/WeatherCore", RTLD_NOW)
        else {
            throw PlatformError.frameworkLoadFailed(["WeatherCore"])
        }
        self.handle = handle
        func symbol(_ candidates: [String], feature: String) throws -> UnsafeMutableRawPointer {
            try DynamicRuntime.resolveFirstSymbol(in: handle, candidates: candidates, feature: feature)
        }
        guard let providerClass = NSClassFromString("WeatherCore.SyncedDataContextProvider"),
            let managerClass = NSClassFromString("WeatherCore.SyncedDataManager"),
            let dataType = _typeByName("11WeatherCore10SyncedDataV"),
            let locationType = _typeByName("11WeatherCore8LocationV"),
            let providerType = _typeByName("11WeatherCore29SyncedDataContextProviderType_p")
        else { throw PlatformError.missingClass("WeatherCore favorites runtime types") }
        self.dataType = dataType
        self.locationType = locationType
        let providerInit = try symbol(Self.providerInitSymbols, feature: "WeatherCore.SyncedDataContextProvider.init")
        let managerInit = try symbol(Self.managerInitSymbols, feature: "WeatherCore.SyncedDataManager.init")
        let emptyInit = try symbol(Self.emptyDataSymbols, feature: "WeatherCore.SyncedData.init")
        // Validate every required symbol before a native constructor or mutation.
        _ = try symbol(Self.readSymbols, feature: "WeatherCore.SyncedDataManager.getSyncedData")
        _ = try symbol(Self.addSymbols, feature: "WeatherCore.SyncedDataManager.addLocation")
        _ = try symbol(Self.removeSymbols, feature: "WeatherCore.SyncedDataManager.removeLocation")
        let directoryPointer = UnsafeMutablePointer<URL?>.allocate(capacity: 1)
        directoryPointer.initialize(to: storageDirectory)
        defer { directoryPointer.deallocate() }  // native initializer consumes this URL? copy
        guard
            let rawProvider = UnsafeMutableRawPointer(
                bitPattern: ObjCCallSwiftMethodValue(
                    providerInit, unsafeBitCast(providerClass, to: UnsafeMutableRawPointer.self),
                    UInt(bitPattern: directoryPointer), 0, nil))
        else { throw PlatformError.storeInitializationFailed("Cannot initialize the native favorites context.") }
        let provider = Unmanaged<AnyObject>.fromOpaque(rawProvider).takeRetainedValue()
        self.provider = provider
        func empty<T>(_ type: T.Type) -> Any {
            let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { pointer.deallocate() }
            _ = ObjCCallSwiftMethodValue(emptyInit, nil, 0, 0, pointer)
            return pointer.move()
        }
        let defaultData = _openExistential(dataType, do: empty)
        func build<P>(_ type: P.Type) throws -> AnyObject {
            guard let nativeProvider = provider as? P else {
                throw PlatformError.storeInitializationFailed("Native favorites provider protocol mismatch.")
            }
            func withData<D>(_ type: D.Type) throws -> AnyObject {
                guard let data = defaultData as? D else {
                    throw PlatformError.storeInitializationFailed("Native favorites value metadata mismatch.")
                }
                // Allocating initializers consume their existential/value arguments.
                // Transfer independent owned copies; the initializer releases or stores them.
                let providerPointer = UnsafeMutablePointer<P>.allocate(capacity: 1)
                providerPointer.initialize(to: nativeProvider)
                let dataPointer = UnsafeMutablePointer<D>.allocate(capacity: 1)
                dataPointer.initialize(to: data)
                defer { providerPointer.deallocate(); dataPointer.deallocate() }
                guard
                    let raw = UnsafeMutableRawPointer(
                        bitPattern: ObjCCallSwiftMethodValue(
                            managerInit, unsafeBitCast(managerClass, to: UnsafeMutableRawPointer.self),
                            UInt(bitPattern: providerPointer), UInt(bitPattern: dataPointer), nil))
                else {
                    throw PlatformError.storeInitializationFailed(
                        "Cannot initialize the native favorites manager.")
                }
                return Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
            }
            return try _openExistential(dataType, do: withData)
        }
        self.manager = try _openExistential(providerType, do: build)
    }

    /// Multi-generation symbol candidate lists (newest macOS first) so updates remain backward-compatible.
    private static let providerInitSymbols = [
        "$s11WeatherCore25SyncedDataContextProviderC14dataStorageURL012useTransientE0AC10Foundation0I0VSg_SbtcfC"
    ]
    private static let managerInitSymbols = [
        "$s11WeatherCore17SyncedDataManagerC06syncedD15ContextProvider07defaultcD0AcA0cdgH4Type_p_AA0cD0VtcfC"
    ]
    private static let emptyDataSymbols = [
        "$s11WeatherCore10SyncedDataVACycfC"
    ]
    private static let readSymbols = [
        "$s11WeatherCore17SyncedDataManagerC03getcD0AA0cD0VSgyF"
    ]
    private static let addSymbols = [
        "$s11WeatherCore17SyncedDataManagerC11addLocationyAA0cD0VAA0G0VF"
    ]
    private static let removeSymbols = [
        "$s11WeatherCore17SyncedDataManagerC14removeLocation2byAA0cD0VSS_tF"
    ]

    private func function(_ candidates: [String], feature: String) throws -> UnsafeMutableRawPointer {
        try DynamicRuntime.resolveFirstSymbol(in: handle, candidates: candidates, feature: feature)
    }

    func all() throws -> [WeatherSavedLocationSnapshot] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let readFunction = try function(Self.readSymbols, feature: "WeatherCore favorites read")
        func read<T>(_ type: T.Type) -> Any? {
            var data: T? = nil
            withUnsafeMutablePointer(to: &data) { pointer in
                _ = ObjCCallSwiftMethodValue(readFunction, Unmanaged.passUnretained(manager).toOpaque(), 0, 0, pointer)
            }
            return data
        }
        guard let data = _openExistential(dataType, do: read) else {
            // A missing native result cannot masquerade as empty if persisted data exists.
            let urls = Mirror(reflecting: provider).children.compactMap { $0.value as? URL }
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty, !existing.isEmpty else { return [] }
            // macOS protects the Weather group container: without Full Disk Access (or the
            // "access data from other apps" consent) the native store reads nothing.
            if existing.contains(where: { !Self.canRead($0) }) {
                throw AgentError(
                    code: "permission_denied",
                    message: "Saved Weather locations are protected and this process cannot read them.",
                    hint:
                        "Give weather-cli (or the app that launches it) Full Disk Access in System Settings > "
                        + "Privacy & Security, restart that app, and retry. Pass a place name or 'lat,lon' meanwhile.")
            }
            throw PlatformError.fetchFailed(
                "Native favorites data could not be decoded. Existing data was not changed.")
        }
        guard let collection = Mirror(reflecting: data).children.first(where: { $0.label == "savedLocations" })?.value,
            let locations = collection as? any Sequence
        else { throw PlatformError.fetchFailed("Native favorites collection metadata changed.") }
        var results: [WeatherSavedLocationSnapshot] = []
        for pair in locations {
            guard
                let native = Mirror(reflecting: pair).children.first(where: {
                    String(describing: type(of: $0.value)) == "SyncedLocation"
                })?.value,
                let encodable = native as? any Encodable,
                let dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(encodable))
                    as? [String: Any],
                let id = dictionary["id"] as? String, let name = dictionary["name"] as? String,
                let coordinate = dictionary["coordinate"] as? [String: Any],
                let latitude = coordinate["latitude"] as? Double, let longitude = coordinate["longitude"] as? Double,
                latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude)
            else {
                throw PlatformError.fetchFailed(
                    "Native favorite entry is malformed; no entry was silently dropped.")
            }
            results.append(
                WeatherSavedLocationSnapshot(
                    id: id, name: name, preciseName: dictionary["preciseName"] as? String,
                    latitude: latitude, longitude: longitude, timeZone: dictionary["timeZoneIdentifier"] as? String))
        }
        return results
    }

    /// True when the file (or, for a directory, its listing and every file in it) can be opened.
    static func canRead(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return true }
        guard isDirectory.boolValue else { return (try? FileHandle(forReadingFrom: url))?.closeFile() != nil }
        guard let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        else { return false }
        return children.allSatisfy(canRead)
    }

    func add(_ location: WeatherSavedLocationSnapshot) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let decoderType = locationType as? any Decodable.Type else {
            throw PlatformError.fetchFailed("Native Location decoder is unavailable.")
        }
        guard let zone = location.timeZone, let identifier = TimeZone(identifier: zone)?.identifier else {
            throw PlatformError.invalidArgument("A favorite requires a valid IANA timezone; UTC is not inferred.")
        }
        let fields: [String: Any] = [
            "id": location.id, "name": location.name, "timeZone": ["identifier": identifier],
            "coordinate": ["latitude": location.latitude, "longitude": location.longitude],
        ]
        let native = try JSONDecoder().decode(decoderType, from: JSONSerialization.data(withJSONObject: fields))
        let addFunction = try function(Self.addSymbols, feature: "WeatherCore favorites add")
        func input<L>(_ type: L.Type) throws {
            guard let value = native as? L else {
                throw PlatformError.fetchFailed("Native Location metadata mismatch.")
            }
            func output<D>(_ type: D.Type) {
                let pointer = UnsafeMutablePointer<D>.allocate(capacity: 1)
                defer { pointer.deinitialize(count: 1); pointer.deallocate() }
                let locationPointer = UnsafeMutablePointer<L>.allocate(capacity: 1)
                locationPointer.initialize(to: value)
                defer { locationPointer.deallocate() }  // native method consumes this copy
                _ = ObjCCallSwiftMethodValue(
                    addFunction, Unmanaged.passUnretained(manager).toOpaque(), UInt(bitPattern: locationPointer), 0,
                    pointer)
            }
            _openExistential(dataType, do: output)
        }
        try _openExistential(locationType, do: input)
    }

    func remove(id: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let removeFunction = try function(Self.removeSymbols, feature: "WeatherCore favorites remove")
        let stringPointer = UnsafeMutablePointer<String>.allocate(capacity: 1)
        stringPointer.initialize(to: id)
        defer { stringPointer.deallocate() }  // native method consumes this String
        let words = UnsafeRawPointer(stringPointer).load(as: (UInt, UInt).self)
        func output<D>(_ type: D.Type) {
            let pointer = UnsafeMutablePointer<D>.allocate(capacity: 1)
            defer { pointer.deinitialize(count: 1); pointer.deallocate() }
            _ = ObjCCallSwiftMethodValue(
                removeFunction, Unmanaged.passUnretained(manager).toOpaque(), words.0, words.1, pointer)
        }
        _openExistential(dataType, do: output)
    }
}
