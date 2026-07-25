import Foundation

struct AndroidResourceVariant: Sendable, Equatable {
    enum Value: Sendable, Equatable { case string(String), reference(UInt32), integer(UInt32) }
    let value: Value
    let density: Int
    let language: String?
}

struct AndroidResourceTable: Sendable {
    private let values: [UInt32: [AndroidResourceVariant]]

    init(values: [UInt32: [AndroidResourceVariant]]) { self.values = values }

    func string(for resourceID: UInt32, locale: String = "zh") -> String? {
        resolve(resourceID: resourceID, locale: locale, visited: [])
    }

    func filePath(for resourceID: UInt32, preferredDensity: Int = 480) -> String? {
        guard let variants = values[resourceID] else { return nil }
        let candidates = variants.compactMap { variant -> (String, Int)? in
            guard case .string(let value) = variant.value, value.hasPrefix("res/") else { return nil }
            return (value, variant.density)
        }
        return candidates.min { abs($0.1 - preferredDensity) < abs($1.1 - preferredDensity) }?.0
    }

    private func resolve(resourceID: UInt32, locale: String, visited: Set<UInt32>) -> String? {
        guard !visited.contains(resourceID), let variants = values[resourceID] else { return nil }
        let preferred = variants.sorted { score($0, locale: locale) > score($1, locale: locale) }
        var nextVisited = visited; nextVisited.insert(resourceID)
        for variant in preferred {
            switch variant.value {
            case .string(let value): return value
            case .reference(let next): if let value = resolve(resourceID: next, locale: locale, visited: nextVisited) { return value }
            case .integer: continue
            }
        }
        return nil
    }

    private func score(_ variant: AndroidResourceVariant, locale: String) -> Int {
        if variant.language == locale { return 3 }
        if variant.language == nil { return 2 }
        return 1
    }
}

enum ResourceTableParser {
    private static let tableType: UInt16 = 0x0002
    private static let stringPoolType: UInt16 = 0x0001
    private static let packageType: UInt16 = 0x0200
    private static let typeChunk: UInt16 = 0x0201

    static func parse(_ data: Data) throws -> AndroidResourceTable {
        let reader = ResourceReader(data: data)
        guard reader.u16(0) == tableType else { throw DroidBoxError.invalidArchive }
        let tableSize = Int(reader.u32(4)), headerSize = Int(reader.u16(2))
        guard headerSize >= 12, tableSize <= data.count else { throw DroidBoxError.invalidArchive }

        var globalStrings: [String] = []
        var packages: [(offset: Int, size: Int)] = []
        var offset = headerSize
        while offset + 8 <= tableSize {
            let type = reader.u16(offset), size = Int(reader.u32(offset + 4))
            guard size >= 8, offset + size <= tableSize else { throw DroidBoxError.invalidArchive }
            if type == stringPoolType && globalStrings.isEmpty { globalStrings = try parseStringPool(reader, offset: offset) }
            if type == packageType { packages.append((offset, size)) }
            offset += size
        }

        var result: [UInt32: [AndroidResourceVariant]] = [:]
        for package in packages { try parsePackage(reader, package: package, globalStrings: globalStrings, result: &result) }
        return AndroidResourceTable(values: result)
    }

    private static func parsePackage(
        _ reader: ResourceReader,
        package: (offset: Int, size: Int),
        globalStrings: [String],
        result: inout [UInt32: [AndroidResourceVariant]]
    ) throws {
        let base = package.offset, headerSize = Int(reader.u16(base + 2)), packageID = reader.u32(base + 8)
        guard headerSize >= 288, headerSize <= package.size else { throw DroidBoxError.invalidArchive }
        var offset = base + headerSize, end = base + package.size
        while offset + 8 <= end {
            let type = reader.u16(offset), size = Int(reader.u32(offset + 4))
            guard size >= 8, offset + size <= end else { throw DroidBoxError.invalidArchive }
            if type == typeChunk { try parseTypeChunk(reader, offset: offset, packageID: packageID, globalStrings: globalStrings, result: &result) }
            offset += size
        }
    }

    private static func parseTypeChunk(
        _ reader: ResourceReader,
        offset: Int,
        packageID: UInt32,
        globalStrings: [String],
        result: inout [UInt32: [AndroidResourceVariant]]
    ) throws {
        let headerSize = Int(reader.u16(offset + 2)), chunkSize = Int(reader.u32(offset + 4))
        let typeID = UInt32(reader.u8(offset + 8)), flags = reader.u8(offset + 9)
        let entryCount = Int(reader.u32(offset + 12)), entriesStart = Int(reader.u32(offset + 16))
        guard typeID != 0, headerSize >= 20, entriesStart >= headerSize, entriesStart <= chunkSize, entryCount < 1_000_000 else { throw DroidBoxError.invalidArchive }
        guard flags & 0x01 == 0 else { return } // Sparse tables are uncommon in game labels/icons; skip safely.
        let density = headerSize >= 36 ? Int(reader.u16(offset + 34)) : 0
        let language = headerSize >= 30 ? decodeLanguage(reader.u8(offset + 28), reader.u8(offset + 29)) : nil

        for index in 0..<entryCount {
            let rawOffset: UInt32
            if flags & 0x02 != 0 {
                let compact = reader.u16(offset + headerSize + index * 2)
                rawOffset = compact == UInt16.max ? UInt32.max : UInt32(compact) * 4
            } else {
                rawOffset = reader.u32(offset + headerSize + index * 4)
            }
            guard rawOffset != UInt32.max else { continue }
            let entry = offset + entriesStart + Int(rawOffset)
            guard entry + 8 <= offset + chunkSize else { throw DroidBoxError.invalidArchive }
            let entrySize = Int(reader.u16(entry)), entryFlags = reader.u16(entry + 2)
            guard entrySize >= 8 else { throw DroidBoxError.invalidArchive }
            if entryFlags & 0x0001 != 0 { continue }
            let valueOffset = entry + entrySize
            guard valueOffset + 8 <= offset + chunkSize, reader.u16(valueOffset) >= 8 else { throw DroidBoxError.invalidArchive }
            let dataType = reader.u8(valueOffset + 3), raw = reader.u32(valueOffset + 4)
            let value: AndroidResourceVariant.Value
            switch dataType {
            case 0x01: value = .reference(raw)
            case 0x03:
                guard Int(raw) < globalStrings.count else { continue }
                value = .string(globalStrings[Int(raw)])
            default: value = .integer(raw)
            }
            let resourceID = (packageID << 24) | (typeID << 16) | UInt32(index)
            result[resourceID, default: []].append(.init(value: value, density: density, language: language))
        }
    }

    private static func parseStringPool(_ reader: ResourceReader, offset: Int) throws -> [String] {
        let headerSize = Int(reader.u16(offset + 2)), chunkSize = Int(reader.u32(offset + 4))
        let count = Int(reader.u32(offset + 8)), styleCount = Int(reader.u32(offset + 12))
        let flags = reader.u32(offset + 16), stringsStart = Int(reader.u32(offset + 20))
        guard headerSize >= 28, count < 1_000_000, styleCount < 1_000_000, stringsStart < chunkSize else { throw DroidBoxError.invalidArchive }
        return (0..<count).map { index in
            let stringOffset = Int(reader.u32(offset + headerSize + index * 4))
            let position = offset + stringsStart + stringOffset
            return flags & 0x100 != 0 ? reader.utf8(position) : reader.utf16(position)
        }
    }

    private static func decodeLanguage(_ first: UInt8, _ second: UInt8) -> String? {
        guard first != 0, second != 0 else { return nil }
        if first & 0x80 == 0 { return String(bytes: [first, second], encoding: .ascii) }
        let a = UInt8(0x61 + (second & 0x1f)), b = UInt8(0x61 + ((second & 0xe0) >> 5) + ((first & 0x03) << 3)), c = UInt8(0x61 + ((first & 0x7c) >> 2))
        return String(bytes: [a, b, c], encoding: .ascii)
    }
}

private struct ResourceReader {
    let data: Data
    func u8(_ offset: Int) -> UInt8 { offset >= 0 && offset < data.count ? data[offset] : 0 }
    func u16(_ offset: Int) -> UInt16 { UInt16(u8(offset)) | UInt16(u8(offset + 1)) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    func utf8(_ offset: Int) -> String {
        var cursor = offset; _ = length8(&cursor); let byteCount = length8(&cursor)
        guard byteCount >= 0, cursor + byteCount <= data.count else { return "" }
        return String(data: data[cursor..<cursor + byteCount], encoding: .utf8) ?? ""
    }
    func utf16(_ offset: Int) -> String {
        var cursor = offset; let count = length16(&cursor)
        guard count >= 0, cursor + count * 2 <= data.count else { return "" }
        return String(data: data[cursor..<cursor + count * 2], encoding: .utf16LittleEndian) ?? ""
    }
    private func length8(_ cursor: inout Int) -> Int { let first = Int(u8(cursor)); cursor += 1; if first & 0x80 != 0 { let second = Int(u8(cursor)); cursor += 1; return ((first & 0x7f) << 8) | second }; return first }
    private func length16(_ cursor: inout Int) -> Int { let first = Int(u16(cursor)); cursor += 2; if first & 0x8000 != 0 { let second = Int(u16(cursor)); cursor += 2; return ((first & 0x7fff) << 16) | second }; return first }
}

