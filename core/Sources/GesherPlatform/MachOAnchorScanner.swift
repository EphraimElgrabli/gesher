import Foundation
import MachO

/// In-memory arm64 Mach-O structural anchor scanner for cross-version resilience.
///
/// When macOS updates a system binary and its Mach-O `LC_UUID` changes, fixed offsets become stale
/// even though the underlying functions, log strings and ObjC wrappers remain identical. This scanner
/// locates internal functions directly in the loaded `__TEXT` segment by matching unique string
/// references (`ADRP`+`ADD`) and walking back to the arm64e `pacibsp` function prologue. Every lookup
/// strictly requires a single unambiguous match; 0 or multiple matches return `nil` so callers fail
/// cleanly rather than guessing.
public final class MachOAnchorScanner: @unchecked Sendable {
    private let baseAddress: UInt
    private let textStartOffset: Int
    private let textByteCount: Int
    private let cstringStartOffset: Int
    private let cstringByteCount: Int

    /// arm64e `pacibsp` instruction encoding.
    private static let pacibspInstruction: UInt32 = 0xd503_237f

    public init?(imageHeader: UnsafeRawPointer) {
        let header = imageHeader.load(as: mach_header_64.self)
        guard header.magic == MH_MAGIC_64 else { return nil }
        baseAddress = UInt(bitPattern: imageHeader)

        var textStart: Int?
        var textSize: Int?
        var cstrStart: Int?
        var cstrSize: Int?

        var cursor = imageHeader.advanced(by: MemoryLayout<mach_header_64>.size)
        let end = cursor.advanced(by: Int(header.sizeofcmds))
        for _ in 0..<header.ncmds {
            guard cursor.advanced(by: MemoryLayout<load_command>.size) <= end else { break }
            let cmd = cursor.load(as: load_command.self)
            guard cmd.cmdsize >= UInt32(MemoryLayout<load_command>.size),
                cursor.advanced(by: Int(cmd.cmdsize)) <= end
            else { break }
            if cmd.cmd == LC_SEGMENT_64 {
                let seg = cursor.load(as: segment_command_64.self)
                let segName = Self.nameString(seg.segname)
                if segName == "__TEXT" {
                    var sectCursor = cursor.advanced(by: MemoryLayout<segment_command_64>.size)
                    for _ in 0..<seg.nsects {
                        let sect = sectCursor.load(as: section_64.self)
                        let sectName = Self.nameString(sect.sectname)
                        if sectName == "__text" {
                            textStart = Int(sect.offset)
                            textSize = Int(sect.size)
                        } else if sectName == "__cstring" {
                            cstrStart = Int(sect.offset)
                            cstrSize = Int(sect.size)
                        }
                        sectCursor = sectCursor.advanced(by: MemoryLayout<section_64>.size)
                    }
                }
            }
            cursor = cursor.advanced(by: Int(cmd.cmdsize))
        }

        guard let ts = textStart, let tsz = textSize, let cs = cstrStart, let csz = cstrSize,
            tsz > 0, csz > 0
        else { return nil }
        textStartOffset = ts
        textByteCount = tsz
        cstringStartOffset = cs
        cstringByteCount = csz
    }

    private static func nameString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    /// Finds the exact offset from `imageHeader` of a C string in `__TEXT,__cstring`, or nil if not unique.
    public func findUniqueCStringOffset(_ needle: String) -> UInt? {
        let needleBytes = Array(needle.utf8)
        guard !needleBytes.isEmpty, needleBytes.count <= cstringByteCount else { return nil }
        let basePtr = UnsafeRawPointer(bitPattern: baseAddress)!.advanced(by: cstringStartOffset)
            .assumingMemoryBound(to: UInt8.self)
        let buffer = UnsafeBufferPointer(start: basePtr, count: cstringByteCount)
        let first = needleBytes[0]
        var found: UInt?
        let limit = cstringByteCount - needleBytes.count
        var i = 0
        while i <= limit {
            if buffer[i] == first && (i == 0 || buffer[i - 1] == 0) {
                var matched = true
                for j in 1..<needleBytes.count {
                    if buffer[i + j] != needleBytes[j] {
                        matched = false
                        break
                    }
                }
                if matched && (i + needleBytes.count == cstringByteCount || buffer[i + needleBytes.count] == 0) {
                    if found != nil { return nil }
                    found = UInt(cstringStartOffset + i)
                }
            }
            i += 1
        }
        return found
    }

    /// Finds all `__text` offsets whose `ADRP`+`ADD` sequence references `targetOffset`.
    public func findADRPAddXrefs(to targetOffset: UInt) -> [UInt] {
        let targetAddr = baseAddress + targetOffset
        let targetPage = targetAddr & ~0xFFF
        let targetPageOff = targetAddr & 0xFFF

        let insnPtr = UnsafeRawPointer(bitPattern: baseAddress)!.advanced(by: textStartOffset)
            .assumingMemoryBound(to: UInt32.self)
        let count = textByteCount / 4
        var results: [UInt] = []
        for i in 0..<(count - 1) {
            let w = insnPtr[i]
            guard (w & 0x9F00_0000) == 0x9000_0000 else { continue }
            let pc = baseAddress + UInt(textStartOffset + i * 4)
            let immlo = Int64((w >> 29) & 3)
            let immhi = Int64((w >> 5) & 0x7FFFF)
            var imm = (immhi << 2) | immlo
            if (imm & (1 << 20)) != 0 { imm -= (1 << 21) }
            let page = UInt(bitPattern: Int(bitPattern: pc & ~0xFFF) + Int(imm << 12))
            guard page == targetPage else { continue }
            let rd = w & 31
            let lookahead = min(i + 6, count)
            for j in (i + 1)..<lookahead {
                let w2 = insnPtr[j]
                if (w2 & 0xFFC0_0000) == 0x9100_0000, ((w2 >> 5) & 31) == rd {
                    let imm12 = UInt((w2 >> 10) & 0xFFF)
                    if imm12 == targetPageOff {
                        results.append(UInt(textStartOffset + i * 4))
                    }
                    break
                }
            }
        }
        return results
    }

    /// Walks backward from an instruction offset in `__text` to the nearest `pacibsp` prologue.
    public func findEnclosingFunctionStart(from offset: UInt, maxScanBytes: Int = 65536) -> UInt? {
        let relative = Int(offset) - textStartOffset
        guard relative >= 0, relative < textByteCount else { return nil }
        let insnPtr = UnsafeRawPointer(bitPattern: baseAddress)!.advanced(by: textStartOffset)
            .assumingMemoryBound(to: UInt32.self)
        let startIndex = relative / 4
        let minIndex = max(0, startIndex - maxScanBytes / 4)
        var idx = startIndex
        while idx >= minIndex {
            if insnPtr[idx] == Self.pacibspInstruction {
                return UInt(textStartOffset + idx * 4)
            }
            idx -= 1
        }
        return nil
    }

    /// Resolves a function's start offset from a unique C-string literal referenced inside it.
    public func findFunctionByUniqueString(_ literal: String) -> UInt? {
        guard let strOffset = findUniqueCStringOffset(literal) else { return nil }
        let xrefs = findADRPAddXrefs(to: strOffset)
        guard xrefs.count == 1 else { return nil }
        return findEnclosingFunctionStart(from: xrefs[0])
    }

    /// Scans forward from a function offset for direct `BL` targets inside `__text`.
    public func findDirectBranchTargets(from startOffset: UInt, maxInstructions: Int = 128) -> [UInt] {
        let relative = Int(startOffset) - textStartOffset
        guard relative >= 0, relative < textByteCount else { return [] }
        let insnPtr = UnsafeRawPointer(bitPattern: baseAddress)!.advanced(by: textStartOffset)
            .assumingMemoryBound(to: UInt32.self)
        let count = textByteCount / 4
        let startIndex = relative / 4
        let endIndex = min(count, startIndex + maxInstructions)
        var targets: [UInt] = []
        for idx in startIndex..<endIndex {
            let w = insnPtr[idx]
            if idx > startIndex && w == Self.pacibspInstruction { break }
            if (w & 0xFC00_0000) == 0x9400_0000 {
                var imm26 = Int64(w & 0x03FF_FFFF)
                if (imm26 & (1 << 25)) != 0 { imm26 -= (1 << 26) }
                let pcOffset = Int64(textStartOffset + idx * 4)
                let target = pcOffset + (imm26 << 2)
                if target >= Int64(textStartOffset) && target < Int64(textStartOffset + textByteCount) {
                    targets.append(UInt(target))
                }
            }
        }
        return targets
    }
}
