import GesherPlatform

/// The cells a table should hold after an insert, computed before Notes is touched so the write
/// can be checked against it.
public enum NoteTableEdit {
    public static let maxRows = 100
    public static let maxColumns = 20

    /// `index` is 0-based; nil appends. `values` fill the new row or column from its start; the
    /// rest stays empty.
    public static func inserting(_ axis: NoteTableAxis, at index: Int?, values: [String], into cells: [[String]])
        throws -> [[String]]
    {
        let rows = cells.count
        let columns = cells.first?.count ?? 0
        guard rows > 0, columns > 0, cells.allSatisfy({ $0.count == columns }) else {
            throw PlatformError.invalidArgument("The table is empty or not rectangular.")
        }
        let length = axis == .row ? columns : rows
        let count = axis == .row ? rows : columns
        let position = index ?? count
        guard position >= 0, position <= count else {
            throw PlatformError.invalidArgument(
                "Position \(position + 1) is outside the table (1 to \(count + 1)).")
        }
        guard values.count <= length else {
            throw PlatformError.invalidArgument(
                "The new \(axis.rawValue) has \(length) cells; \(values.count) values were given.")
        }
        guard axis == .row ? rows < maxRows : columns < maxColumns else {
            throw PlatformError.invalidArgument(
                "Notes tables are limited to \(maxRows) rows and \(maxColumns) columns.")
        }
        let line = values + Array(repeating: "", count: length - values.count)
        var result = cells
        switch axis {
        case .row: result.insert(line, at: position)
        case .column: for row in result.indices { result[row].insert(line[row], at: position) }
        }
        return result
    }
}
