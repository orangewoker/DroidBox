import Foundation

struct ArchiveEntryInfo: Sendable {
    let path: String
    let compressed: UInt64
    let uncompressed: UInt64
    let localHeaderOffset: UInt64
    let crc32: UInt32
    let compressionMethod: UInt16
    let directory: Bool
}

struct SafeArchive: Sendable {
    let url: URL
    let entries: [ArchiveEntryInfo]
    init(url: URL, maxExpandedBytes: UInt64 = 16 * 1024 * 1024 * 1024, maxRatio: UInt64 = 20) throws {
        self.url = url
        let native = try DBZipArchive.entries(at: url)
        var seen=Set<String>(), totalCompressed:UInt64=0,totalExpanded:UInt64=0, mapped:[ArchiveEntryInfo]=[]
        for item in native {
            let path=item.path.replacingOccurrences(of:"\\",with:"/")
            guard Self.isSafe(path) else { throw DroidBoxError.unsafeArchiveEntry(path) }
            // ZIP entry names are case-sensitive. Android packages may legitimately
            // contain resources such as res/Ms.png and res/mS.png. Reject only an
            // exact duplicate here; extraction separately protects case-insensitive
            // destination filesystems from overwriting two entries onto one path.
            guard seen.insert(path).inserted else { throw DroidBoxError.duplicateEntry(path) }
            totalCompressed += item.compressedSize; totalExpanded += item.uncompressedSize
            guard totalExpanded <= maxExpandedBytes else { throw DroidBoxError.excessiveExpansion }
            mapped.append(.init(
                path: path,
                compressed: item.compressedSize,
                uncompressed: item.uncompressedSize,
                localHeaderOffset: item.localHeaderOffset,
                crc32: item.crc32,
                compressionMethod: item.compressionMethod,
                directory: item.directory
            ))
        }
        if totalCompressed > 0 && totalExpanded / max(totalCompressed,1) > maxRatio { throw DroidBoxError.excessiveExpansion }
        entries=mapped
    }
    func data(path: String, maximum: Int) throws -> Data {
        guard let item = entries.first(where: { $0.path == path }) else {
            throw DroidBoxError.invalidArchive
        }
        return try DBZipArchive.data(
            localHeaderOffset: item.localHeaderOffset,
            compressedSize: item.compressed,
            uncompressedSize: item.uncompressed,
            method: item.compressionMethod,
            crc32: item.crc32,
            url: url,
            maximumSize: UInt(maximum)
        )
    }
    func extract(
        prefix: String,
        to root: URL,
        maximumPerFile: Int = 512 * 1024 * 1024,
        stripRenPyAssetEscaping: Bool = false
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var extractedDestinations = Set<String>()
        for item in entries where !item.directory && item.path.hasPrefix(prefix) {
            try Task.checkCancellation()
            var relative = String(item.path.dropFirst(prefix.count))
            if stripRenPyAssetEscaping {
                relative = Self.unescapeRenPyAssetPath(relative)
            }
            guard !relative.isEmpty else{continue}
            let destination=root.appending(path:relative).standardizedFileURL
            guard destination.path.hasPrefix(root.standardizedFileURL.path+"/") else{throw DroidBoxError.unsafeArchiveEntry(item.path)}
            let destinationKey = destination.path.precomposedStringWithCanonicalMapping.lowercased()
            guard extractedDestinations.insert(destinationKey).inserted else {
                throw DroidBoxError.duplicateEntry(item.path)
            }
            try DBZipArchive.extract(
                localHeaderOffset: item.localHeaderOffset,
                compressedSize: item.compressed,
                uncompressedSize: item.uncompressed,
                method: item.compressionMethod,
                crc32: item.crc32,
                fileHandle: handle,
                destination: destination,
                maximumSize: UInt(maximumPerFile)
            )
        }
    }
    static func unescapeRenPyAssetPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                component.hasPrefix("x-") ? String(component.dropFirst(2)) : String(component)
            }
            .joined(separator: "/")
    }
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty,!path.hasPrefix("/"),!path.hasPrefix("\\"),!path.contains(":") else{return false}
        var depth=0;for part in path.split(separator:"/",omittingEmptySubsequences:false){if part==".."{depth-=1}else if part != "." && !part.isEmpty{depth+=1};if depth<0{return false}};return true
    }
}
