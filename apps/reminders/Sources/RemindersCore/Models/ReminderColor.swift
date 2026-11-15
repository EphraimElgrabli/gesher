import Foundation

public struct ReminderColor: Sendable {
    public let hex: String

    public init(_ input: String) throws {
        var digits = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard [3, 6, 8].contains(digits.utf8.count),
            digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else {
            throw ReminderCLIError.invalidArgument(
                "Color must be RGB, RRGGBB, or RRGGBBAA hexadecimal, optionally prefixed with # (for example #AF52DE). Color names are not supported."
            )
        }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        hex = "#" + digits.uppercased()
    }
}
