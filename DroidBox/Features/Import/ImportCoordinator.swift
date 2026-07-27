import Foundation
import Observation
import UIKit

enum ImportStage: String, CaseIterable, Sendable {
    case copying = "复制文件"
    case security = "安全检查"
    case parsing = "解析 APK"
    case icon = "提取图标"
    case engine = "检测引擎"
    case compatibility = "分析兼容性"
    case runtime = "准备 Runtime"
    case finished = "完成"
}

@MainActor @Observable
final class ImportCoordinator {
    private(set) var stage: ImportStage = .copying
    private(set) var progress: Double = 0
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    let library: GameLibrary
    let settings: AppSettings
    var maximumFileSize: UInt64 { settings.maximumFileSizeBytes }

    init(library: GameLibrary, settings: AppSettings) {
        self.library = library
        self.settings = settings
    }

    func cancel() {
        task?.cancel()
    }

    func start(url: URL) {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        let paths = library.paths
        let maximumBytes = maximumFileSize

        task = Task {
            do {
                let game = try await Self.importFile(
                    url,
                    paths: paths,
                    maximumFileSize: maximumBytes
                ) { [weak self] stage, progress in
                    self?.set(stage, progress)
                }
                try library.add(game)
                stage = .finished
                progress = 1
            } catch is CancellationError {
                errorMessage = DroidBoxError.importCancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }

    /// Runs on the generic executor so enumerating and extracting a multi-gigabyte APK
    /// cannot freeze SwiftUI's main actor.
    private nonisolated static func importFile(
        _ source: URL,
        paths: AppPaths,
        maximumFileSize: UInt64,
        progress update: @escaping @MainActor @Sendable (ImportStage, Double) -> Void
    ) async throws -> GameRecord {
        let access = source.startAccessingSecurityScopedResource()
        defer {
            if access { source.stopAccessingSecurityScopedResource() }
        }

        try Task.checkCancellation()
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        guard UInt64(values.fileSize ?? 0) <= maximumFileSize else {
            throw DroidBoxError.fileTooLarge
        }

        let id = UUID()
        let root = paths.game(id)
        let sourceDirectory = root.appending(path: "source")
        let content = root.appending(path: "content")
        let dataDirectory = root.appending(path: "saves")

        do {
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

            await update(.security, 0.12)
            let archive = try SafeArchive(url: source)
            let archivePaths = archive.entries.map(\.path)

            await update(.parsing, 0.25)
            let manifest: ManifestInfo
            if let item = archive.entries.first(where: { $0.path == "AndroidManifest.xml" }) {
                manifest = try BinaryXMLParser.parse(
                    archive.data(path: item.path, maximum: 16 * 1024 * 1024)
                )
            } else {
                manifest = ManifestInfo()
            }

            await update(.icon, 0.40)
            var resolvedTitle = manifest.label
            var extractedIconPath: String?
            if let resourcesEntry = archive.entries.first(where: { $0.path == "resources.arsc" }),
               let tableData = try? archive.data(
                   path: resourcesEntry.path,
                   maximum: 256 * 1024 * 1024
               ),
               let table = try? ResourceTableParser.parse(tableData) {
                if let labelID = manifest.labelResourceID {
                    resolvedTitle = table.string(for: labelID) ?? resolvedTitle
                }
                if let iconID = manifest.iconResourceID,
                   let archivePath = table.filePath(for: iconID),
                   let imageData = try? archive.data(
                       path: archivePath,
                       maximum: 64 * 1024 * 1024
                   ),
                   let png = UIImage(data: imageData)?.pngData() {
                    let destination = root.appending(path: "icon.png")
                    try png.write(to: destination, options: .atomic)
                    extractedIconPath = destination.path
                }
            }

            let abi = ABIAnalyzer.analyze(paths: archivePaths)
            await update(.engine, 0.55)
            let detected = EngineDetector.detect(paths: archivePaths)
            await update(.compatibility, 0.70)
            let report = CompatibilityAnalyzer.analyze(
                engine: detected,
                abi: abi,
                manifest: manifest,
                entries: archive.entries
            )

            let mode: RuntimeMode
            switch detected.engine {
            case .rpgMakerMV, .rpgMakerMZ:
                mode = .web
            case .renpy7, .renpy8:
                mode = .renpy
            default:
                mode = report.level == .unsupported ? .unavailable : .androidVM
            }

            var originalFilePath = source.path
            var runtimeProfileID = "default"
            switch mode {
            case .web:
                try requireStorage(for: archive.entries, prefix: "assets/www/", at: root)
                try archive.extract(prefix: "assets/www/", to: content)

            case .renpy:
                guard let profile = RenPyPackageAnalyzer.analyze(entries: archive.entries),
                      profile.isSupportedByBundledRuntime,
                      report.level != .unsupported else {
                    throw DroidBoxError.engineRuntimeMismatch
                }
                try requireStorage(for: archive.entries, prefix: profile.gamePrefix, at: root)
                try archive.extract(
                    prefix: profile.gamePrefix,
                    to: content,
                    stripRenPyAssetEscaping: profile.usesAndroidAssetEscaping
                )
                let bytecode = content.appending(
                    path: "cache/bytecode-\(RenPyPackageProfile.bundledPythonBytecodeTag).rpyb"
                )
                guard FileManager.default.fileExists(atPath: bytecode.path) else {
                    throw DroidBoxError.runtimeCorrupted
                }
                // The native fast path needs only the extracted game data. Keeping the
                // Android package would almost double storage for a 3 GB visual novel.
                originalFilePath = ""
                runtimeProfileID = RenPyPackageProfile.bundledRuntimeVersion

            case .androidVM:
                await update(.copying, 0.78)
                let local = sourceDirectory.appending(path: source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: local)
                originalFilePath = local.path

            case .automatic, .unavailable:
                break
            }

            await update(.runtime, 0.90)
            try Task.checkCancellation()
            let title = (resolvedTitle?.hasPrefix("@") == false ? resolvedTitle : nil)
                ?? source.deletingPathExtension().lastPathComponent
            let game = GameRecord(
                id: id,
                title: title,
                packageName: manifest.packageName,
                versionName: manifest.versionName,
                versionCode: manifest.versionCode,
                sourceType: source.pathExtension.lowercased() == "apk" ? .apk : .zip,
                engine: detected.engine,
                runtimeMode: mode,
                abiList: abi,
                iconPath: extractedIconPath,
                coverPath: nil,
                originalFilePath: originalFilePath,
                installedContentPath: content.path,
                dataPath: dataDirectory.path,
                runtimeProfileID: runtimeProfileID,
                orientation: manifest.orientation,
                compatibility: report,
                controllerProfile: .init(),
                createdAt: Date(),
                lastPlayedAt: nil,
                totalPlayTime: 0
            )
            let metadata = try JSONEncoder().encode(game)
            try metadata.write(to: root.appending(path: "metadata.json"), options: .atomic)
            return game
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func set(_ stage: ImportStage, _ progress: Double) {
        self.stage = stage
        self.progress = progress
    }

    private nonisolated static func requireStorage(
        for entries: [ArchiveEntryInfo],
        prefix: String,
        at destination: URL
    ) throws {
        let required = entries.lazy
            .filter { !$0.directory && $0.path.hasPrefix(prefix) }
            .reduce(UInt64(0)) { $0 + $1.uncompressed }
        let values = try destination.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        if let available = values.volumeAvailableCapacityForImportantUsage,
           UInt64(max(available, 0)) < required + 512 * 1024 * 1024 {
            throw DroidBoxError.insufficientStorage
        }
    }
}
