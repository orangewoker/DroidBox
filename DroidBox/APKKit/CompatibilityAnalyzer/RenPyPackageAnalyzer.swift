import Foundation

struct RenPyPackageProfile: Sendable, Equatable {
    static let bundledRuntimeVersion = "8.4.1"
    static let bundledPythonBytecodeTag = "312"

    let gamePrefix: String
    let usesAndroidAssetEscaping: Bool
    let pythonBytecodeTag: String?
    let hasPrivateRuntimeArchive: Bool
    let hasCommonAssets: Bool
    let gameBytes: UInt64

    var isSupportedByBundledRuntime: Bool {
        pythonBytecodeTag == Self.bundledPythonBytecodeTag
    }
}

enum RenPyPackageAnalyzer {
    static func analyze(entries: [ArchiveEntryInfo]) -> RenPyPackageProfile? {
        let paths = entries.map(\.path)
        let escaped = paths.contains { $0.hasPrefix("assets/x-game/") }
        let plain = paths.contains { $0.hasPrefix("assets/game/") }
        guard escaped || plain else { return nil }

        let prefix = escaped ? "assets/x-game/" : "assets/game/"
        let bytecodeTag = paths.lazy.compactMap { path -> String? in
            let name = path.lowercased()
            guard
                name.hasSuffix(".rpyb"),
                let marker = name.range(of: "bytecode-", options: .backwards)
            else { return nil }

            let suffixEnd = name.index(name.endIndex, offsetBy: -5)
            guard marker.upperBound < suffixEnd else { return nil }
            let tag = String(name[marker.upperBound..<suffixEnd])
            return !tag.isEmpty && tag.allSatisfy(\.isNumber) ? tag : nil
        }.first

        return RenPyPackageProfile(
            gamePrefix: prefix,
            usesAndroidAssetEscaping: escaped,
            pythonBytecodeTag: bytecodeTag,
            hasPrivateRuntimeArchive: paths.contains("assets/private.mp3"),
            hasCommonAssets: paths.contains {
                $0.hasPrefix(escaped ? "assets/x-renpy/x-common/" : "assets/renpy/common/")
            },
            gameBytes: entries.lazy
                .filter { !$0.directory && $0.path.hasPrefix(prefix) }
                .reduce(0) { $0 + $1.uncompressed }
        )
    }
}
