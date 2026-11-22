import Foundation

/// Structured macOS generation info used for cross-version runtime compatibility and diagnostics.
public struct OSGeneration: Sendable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static var current: OSGeneration {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return OSGeneration(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion)
    }

    public var description: String {
        patch > 0 ? "macOS \(major).\(minor).\(patch)" : "macOS \(major).\(minor)"
    }

    public func isAtLeast(_ major: Int, minor: Int = 0) -> Bool {
        if self.major != major { return self.major > major }
        return self.minor >= minor
    }
}

/// Reports how a private runtime bridge resolved its entry points on the current macOS generation.
public enum ABIResolutionMode: String, Sendable, Equatable {
    case verifiedBuild = "verified_build"
    case structuralAnchors = "structural_anchors"
    case namedSelectors = "named_selectors"
}

extension DynamicRuntime {
    /// Resolves the first available Objective-C class across macOS generations (newest candidate first).
    public func resolveFirstClass(_ candidates: [String]) throws -> AnyClass {
        for name in candidates {
            if let cls = NSClassFromString(name) { return cls }
        }
        throw PlatformError.missingClass(candidates.joined(separator: " | "))
    }

    /// Resolves the first supported selector on an object across macOS generations.
    public func resolveFirstSelector(on object: AnyObject, candidates: [String]) throws -> Selector {
        for name in candidates {
            let selector = NSSelectorFromString(name)
            if object.responds(to: selector) { return selector }
        }
        throw PlatformError.missingSelector(
            className: String(describing: type(of: object)),
            selector: candidates.joined(separator: " | "))
    }

    /// Resolves the first exported C/Swift symbol across macOS generations from a dlopen handle (or RTLD_DEFAULT).
    public static func resolveFirstSymbol(
        in handle: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: -2),
        candidates: [String],
        feature: String
    ) throws -> UnsafeMutableRawPointer {
        for symbol in candidates {
            if let address = dlsym(handle, symbol) { return address }
        }
        throw PlatformError.unsupportedPrivateAPI(
            selector: candidates.first ?? feature,
            reason: "None of the expected \(feature) symbols exist on \(OSGeneration.current).")
    }
}
