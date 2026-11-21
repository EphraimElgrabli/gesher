import GesherPlatform
import Foundation
import ObjCRuntimeSupport

/// What a stored Coherence blob holds. Each case names Freeform's own Swift model type for that
/// column, so the blob is decoded by Coherence into the very value Freeform reads.
public enum FreeformRecord: Hashable, Sendable {
    /// `boards.data`: `CRLBoardCRDTData` (title, root container, creation and activity times).
    case board
    /// `folders.data`: `CRLFolderCRDTData`.
    case folder
    /// `board_items.common_data` (id, parent, geometry, lock). Shape-like items carry a path too.
    case itemCommon(FreeformItemKind)
    /// `board_items.specific_data` for the item's kind.
    case itemSpecific(FreeformItemKind)

    /// The mangled name of Freeform's Swift type for this record.
    var typeName: String {
        func named(_ name: String) -> String { "\(name.count)\(name)V" }
        switch self {
        case .board: return "8Freeform" + named("CRLBoardCRDTData")
        case .folder: return "8Freeform" + named("CRLFolderCRDTData")
        case .itemCommon(let kind):
            let affinity = kind.isShapeLike ? "CRLShapeItemParentAffinity" : "CRLBoardItemParentAffinity"
            return "8Freeform" + named("CRLBoardItemCommonAbstractCRDTData") + "yAA" + named(affinity) + "G"
        case .itemSpecific(let kind): return "8Freeform" + named(kind.specificTypeName)
        }
    }
}

/// Freeform's board item kinds. The stored `item_type` is the case's position in Freeform's
/// `CRLBoardItemType` plus 2; CloudKit records are named `BoardItem_<item_type>`.
public enum FreeformItemKind: Int, Sendable, CaseIterable {
    case group = 2, shape, connector, image, movie, file, link, model3D, drawing, drawingStroke, sticky, table, surface

    var isShapeLike: Bool { [.shape, .connector, .drawingStroke, .sticky].contains(self) }

    var specificTypeName: String {
        switch self {
        case .group, .drawing, .table, .surface: return "CRLContainerItemCRDTData"
        case .shape: return "CRLWPShapeItemCRDTData"
        case .connector: return "CRLConnectionLineCRDTData"
        case .image: return "CRLImageItemCRDTData"
        case .movie: return "CRLMovieItemCRDTData"
        case .file: return "CRLFileItemCRDTData"
        case .link: return "CRLURLItemCRDTData"
        case .model3D: return "CRLUSDZItemCRDTData"
        case .drawingStroke: return "CRLFreehandDrawingShapeCRDTData"
        case .sticky: return "CRLWPStickyNoteItemCRDTData"
        }
    }
}

/// Decodes stored blobs into reflectable values. The live implementation is `FreeformModelRuntime`;
/// tests inject plain Swift values with the same field names.
public protocol FreeformRecordDecoding: Sendable {
    func decode(_ record: FreeformRecord, _ data: Data) -> Reflected?
}

/// Loads Freeform's model types (from the app executable) and Coherence, and decodes blobs with
/// Coherence's exported `CRDT.init(serializedData:)` into Freeform's own types. Nothing is called
/// by address: the initializer and protocol descriptor are exported Coherence symbols, the type
/// metadata comes from the Swift runtime's name lookup, the conformance from
/// `swift_conformsToProtocol`. Decoded values are only read (Swift reflection), never written.
public final class FreeformModelRuntime: FreeformRecordDecoding, @unchecked Sendable {
    public static let appPath = "/System/Applications/Freeform.app"
    private static let coherencePath = "/System/Library/PrivateFrameworks/Coherence.framework/Coherence"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var shared: FreeformModelRuntime?

    private let initializer: UnsafeMutableRawPointer
    private let protocolDescriptor: UnsafeRawPointer
    private let conformsToProtocol: @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?
    private var types: [FreeformRecord: (metadata: Any.Type, witness: UnsafeRawPointer)?] = [:]
    private let typesLock = NSLock()
    /// Load address of the loaded Freeform executable image.
    public let imageBase: UInt
    /// Mach-O LC_UUID of the loaded Freeform executable image, used to strictly gate private ABI calls.
    public let imageUUID: String?

    /// The process-wide runtime; loads Freeform and Coherence once.
    public static func load() throws -> FreeformModelRuntime {
        lock.lock()
        defer { lock.unlock() }
        if let shared { return shared }
        let runtime = try FreeformModelRuntime()
        shared = runtime
        return runtime
    }

    private init() throws {
        guard FileManager.default.fileExists(atPath: Self.appPath + "/Contents/MacOS/Freeform") else {
            throw PlatformError.frameworkLoadFailed([Self.appPath])
        }
        guard let coherence = dlopen(Self.coherencePath, RTLD_NOW) else {
            throw PlatformError.frameworkLoadFailed([Self.coherencePath])
        }
        // Freeform links its bundled TS* frameworks by @rpath; loading them by path first lets the
        // executable resolve them. The ObjC runtime warns about one duplicate class while loading.
        try Self.quietly { try Self.loadFreeformExecutable() }
        guard let initializer = dlsym(coherence, "$s9Coherence4CRDTPAAE14serializedDatax10Foundation0D0V_tKcfC"),
            let descriptor = dlsym(coherence, "$s9Coherence4CRDTMp"),
            let conforms = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_conformsToProtocol")
        else {
            throw PlatformError.unsupportedPrivateAPI(
                selector: "Coherence.CRDT.init(serializedData:)",
                reason: "This macOS version's Coherence framework does not export the CRDT decoder.")
        }
        self.initializer = initializer
        protocolDescriptor = UnsafeRawPointer(descriptor)
        conformsToProtocol = unsafeBitCast(
            conforms, to: (@convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?).self)
        var info = Dl_info()
        if let boardClass = NSClassFromString("Freeform.CRLBoard"),
            dladdr(unsafeBitCast(boardClass, to: UnsafeRawPointer.self), &info) != 0,
            let basePointer = info.dli_fbase
        {
            imageBase = UInt(bitPattern: basePointer)
            imageUUID = ObjCMachOImageUUIDString(basePointer)
        } else {
            imageBase = 0
            imageUUID = nil
        }
    }

    private static func loadFreeformExecutable() throws {
        let frameworks = appPath + "/Contents/Frameworks"
        var pending = ((try? FileManager.default.contentsOfDirectory(atPath: frameworks)) ?? [])
            .filter { $0.hasSuffix(".framework") }
        for _ in 0..<4 where !pending.isEmpty {
            pending = pending.filter { name in
                dlopen("\(frameworks)/\(name)/\((name as NSString).deletingPathExtension)", RTLD_NOW) == nil
            }
        }
        guard dlopen(appPath + "/Contents/MacOS/Freeform", RTLD_NOW) != nil else {
            throw PlatformError.frameworkLoadFailed([appPath + "/Contents/MacOS/Freeform"])
        }
    }

    /// Runs `body` with stderr silenced (the duplicate-class notice is not the caller's concern).
    private static func quietly(_ body: () throws -> Void) throws {
        fflush(stderr)
        let saved = dup(STDERR_FILENO)
        let null = open("/dev/null", O_WRONLY)
        if saved >= 0, null >= 0 { dup2(null, STDERR_FILENO) }
        defer {
            if saved >= 0 {
                dup2(saved, STDERR_FILENO)
                close(saved)
            }
            if null >= 0 { close(null) }
        }
        try body()
    }

    /// Whether every record type resolves to a Freeform type conforming to `Coherence.CRDT`.
    public func missingTypes() -> [String] {
        var records: [FreeformRecord] = [.board, .folder]
        for kind in FreeformItemKind.allCases { records += [.itemCommon(kind), .itemSpecific(kind)] }
        return records.filter { resolve($0) == nil }.map(\.typeName)
    }

    private func resolve(_ record: FreeformRecord) -> (metadata: Any.Type, witness: UnsafeRawPointer)? {
        typesLock.lock()
        defer { typesLock.unlock() }
        if let cached = types[record] { return cached }
        var resolved: (Any.Type, UnsafeRawPointer)?
        if let type = _typeByName(record.typeName),
            let witness = conformsToProtocol(unsafeBitCast(type, to: UnsafeRawPointer.self), protocolDescriptor)
        {
            resolved = (type, witness)
        }
        types[record] = .some(resolved)
        return resolved
    }

    public func decode(_ record: FreeformRecord, _ data: Data) -> Reflected? {
        guard data.count > 8, data.starts(with: Array("crdt".utf8)), let (type, witness) = resolve(record) else {
            return nil
        }
        func decodeAs<T>(_: T.Type) -> Any? {
            let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { result.deallocate() }
            // The initializer consumes its Data argument: hand it its own retained copy.
            let argument = UnsafeMutablePointer<Data>.allocate(capacity: 1)
            argument.initialize(to: data)
            defer { argument.deallocate() }
            let words = UnsafeRawPointer(argument).load(as: (UInt, UInt).self)
            var error: UnsafeMutableRawPointer?
            ObjCCallSwiftThrowingGenericInit(
                initializer, words.0, words.1, unsafeBitCast(type, to: UnsafeRawPointer.self), witness, result,
                &error)
            guard error == nil else { return nil }
            return result.move()
        }
        return _openExistential(type, do: decodeAs).map(Reflected.init)
    }
}

/// Read-only navigation through a decoded value by field name, using Swift reflection.
///
/// Path components match stored property names with or without their leading underscore.
/// Coherence wrappers are looked through: optionals, registers (`CRRegister`, `CRMaxRegister`:
/// `ref` → `_value`), `CRExtensible.known(x)` and `superData`-style nesting stays explicit.
public struct Reflected: @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = Reflected.unwrap(value) }

    public subscript(_ path: String) -> Reflected? {
        var current: Reflected? = self
        for component in path.split(separator: ".") {
            current = current?.child(String(component))
        }
        return current
    }

    /// The first path that resolves.
    public func first(_ paths: String...) -> Reflected? {
        for path in paths { if let found = self[path] { return found } }
        return nil
    }

    private func child(_ name: String) -> Reflected? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            for child in current.children where child.label == name || child.label == "_" + name {
                return Reflected.present(child.value)
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    /// Nil for an absent optional or an unset register.
    private static func present(_ value: Any) -> Reflected? {
        let unwrapped = unwrap(value)
        let mirror = Mirror(reflecting: unwrapped)
        if mirror.displayStyle == .optional && mirror.children.isEmpty { return nil }
        if isRegister(unwrapped) { return nil }
        return Reflected(unwrapped)
    }

    private static func isRegister(_ value: Any) -> Bool {
        let name = String(describing: type(of: value))
        return name.hasPrefix("CRRegister<") || name.hasPrefix("CRMaxRegister<")
    }

    private static func unwrap(_ value: Any) -> Any {
        var current = value
        for _ in 0..<8 {
            let mirror = Mirror(reflecting: current)
            if mirror.displayStyle == .optional {
                guard let some = mirror.children.first else { return current }
                current = some.value
                continue
            }
            let name = String(describing: type(of: current))
            if name.hasPrefix("CRRegister<") || name.hasPrefix("CRMaxRegister<") || name.hasPrefix("CRRegisterRef<")
                || name.hasPrefix("CRMaxRegisterRef<")
            {
                var found: Any?
                var search: Mirror? = mirror
                while let level = search, found == nil {
                    found =
                        level.children.first { $0.label == "_value" || $0.label == "value" || $0.label == "ref" }?
                        .value
                    search = level.superclassMirror
                }
                guard let next = found else { return current }
                current = next
                continue
            }
            if name.hasPrefix("CRExtensible<"), mirror.displayStyle == .enum, let known = mirror.children.first,
                known.label == "known"
            {
                current = known.value
                continue
            }
            return current
        }
        return current
    }

    public var string: String? { value as? String }
    public var double: Double? {
        switch value {
        case let number as Double: return number
        case let number as Float: return Double(number)
        case let number as CGFloat: return Double(number)
        case let number as Int: return Double(number)
        default: return nil
        }
    }
    public var bool: Bool? { value as? Bool }
    public var uuid: UUID? { value as? UUID }
    public var url: URL? { value as? URL }

    /// Elements of a Coherence collection (ordered set, sequence, array).
    public var elements: [Reflected] {
        if value is String || value is Data { return [] }
        guard let sequence = value as? any Sequence else { return [] }
        var result: [Reflected] = []
        for element in sequence { result.append(Reflected(element)) }
        return result
    }

    /// Plain text of a `CRAttributedString` (or a plain string).
    public var text: String? {
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        if let attributed = value as? AttributedString { return String(attributed.characters) }
        // CRAttributedString → stringRef → topotext (an ObjC CRTTMergeableString).
        if let topotext = self["stringRef.topotext"]?.value as? NSObject,
            topotext.responds(to: NSSelectorFromString("attributedString")),
            let attributed = topotext.value(forKey: "attributedString") as? NSAttributedString
        {
            return attributed.string
        }
        return nil
    }

    /// The case name of an enum value (`CRExtensible.known` already unwrapped).
    public var caseName: String? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .enum else { return nil }
        if let label = mirror.children.first?.label { return label }
        return String(describing: value)
    }
}
