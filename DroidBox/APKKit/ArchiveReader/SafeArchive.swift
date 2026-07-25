import Foundation

struct ArchiveEntryInfo: Sendable { let path: String; let compressed: UInt64; let uncompressed: UInt64; let directory: Bool }

struct SafeArchive: Sendable {
    let url: URL
    let entries: [ArchiveEntryInfo]
    init(url: URL, maxExpandedBytes: UInt64 = 16 * 1024 * 1024 * 1024, maxRatio: UInt64 = 20) throws {
        var error: NSError?; guard let native = DBZipArchive.entries(at: url, error: &error) else { throw DroidBoxError.invalidArchive }
        var seen=Set<String>(), totalCompressed:UInt64=0,totalExpanded:UInt64=0, mapped:[ArchiveEntryInfo]=[]
        for item in native {
            let path=item.path.replacingOccurrences(of:"\\",with:"/")
            guard Self.isSafe(path) else { throw DroidBoxError.unsafeArchiveEntry(path) }
            let key=path.lowercased(); guard seen.insert(key).inserted else { throw DroidBoxError.duplicateEntry(path) }
            totalCompressed += item.compressedSize; totalExpanded += item.uncompressedSize
            guard totalExpanded <= maxExpandedBytes else { throw DroidBoxError.excessiveExpansion }
            mapped.append(.init(path:path,compressed:item.compressedSize,uncompressed:item.uncompressedSize,directory:item.directory))
        }
        if totalCompressed > 0 && totalExpanded / max(totalCompressed,1) > maxRatio { throw DroidBoxError.excessiveExpansion }
        entries=mapped
    }
    func data(path: String, maximum: Int) throws -> Data {
        var error:NSError?; guard let data=DBZipArchive.data(forEntry:path,at:url,maximumSize:maximum,error:&error) else { throw error ?? DroidBoxError.invalidArchive as NSError }; return data
    }
    func extract(prefix: String, to root: URL, maximumPerFile: Int = 512*1024*1024) throws {
        for item in entries where !item.directory && item.path.hasPrefix(prefix) {
            let relative=String(item.path.dropFirst(prefix.count)); guard !relative.isEmpty else{continue}
            let destination=root.appending(path:relative).standardizedFileURL
            guard destination.path.hasPrefix(root.standardizedFileURL.path+"/") else{throw DroidBoxError.unsafeArchiveEntry(item.path)}
            var error:NSError?; guard DBZipArchive.extractEntry(item.path,at:url,to:destination,maximumSize:maximumPerFile,error:&error) else { throw error ?? DroidBoxError.invalidArchive as NSError }
        }
    }
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty,!path.hasPrefix("/"),!path.hasPrefix("\\"),!path.contains(":") else{return false}
        var depth=0;for part in path.split(separator:"/",omittingEmptySubsequences:false){if part==".."{depth-=1}else if part != "." && !part.isEmpty{depth+=1};if depth<0{return false}};return true
    }
}

