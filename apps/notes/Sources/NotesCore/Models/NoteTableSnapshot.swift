import Foundation

public struct NoteTableSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let cells: [[String]]
}
