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
    case extracting = "解压游戏数据"
    case runtime = "准备 Runtime"
    case finished = "完成"
}

struct ImportNotice: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor @Observable
final class ImportCoordinator {
    private(set) var stage: ImportStage = .copying
    private(set) var progress: Double = 0
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    private(set) var notice: ImportNotice?
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

    func clearError() {
        errorMessage = nil
    }

    func clearNotice() {
        notice = nil
        errorMessage = nil
    }

    func reportPickerFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue {
            notice = ImportNotice(title: "已取消导入", message: "没有选择文件。")
        } else {
            let message = "系统文件选择器返回错误：\(error.localizedDescription)"
            errorMessage = message
            notice = ImportNotice(title: "无法读取所选文件", message: message)
        }
    }

    func start(url: URL) {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        notice = nil
        stage = .copying
        progress = 0.02
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
                if game.runtimeMode == .unavailable {
                    let detail = game.compatibility.issues.first?.detail
                        ?? game.compatibility.summary
                    notice = ImportNotice(
                        title: "已识别，但当前不能启动",
                        message: "\(game.title) 已加入游戏库。\(detail)"
                    )
                } else if game.runtimeMode == .androidVM {
                    notice = ImportNotice(
                        title: "APK 已导入",
                        message: "\(game.title) 已加入游戏库；普通 Android APK 仍需要 QEMU Core 与 Android Runtime 才能启动。"
                    )
                } else {
                    notice = ImportNotice(
                        title: "导入完成",
                        message: "\(game.title) 已加入游戏库，可以打开详情页启动。"
                    )
                }
            } catch is CancellationError {
                errorMessage = DroidBoxError.importCancelled.localizedDescription
                notice = ImportNotice(title: "导入已取消", message: errorMessage ?? "")
            } catch {
                errorMessage = error.localizedDescription
                notice = ImportNotice(title: "导入失败", message: errorMessage ?? "未知错误")
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
            let extractionProgress: @Sendable (Int, Int) -> Void = { completed, total in
                let ratio = total > 0 ? Double(completed) / Double(total) : 1
                Task { @MainActor in
                    update(.extracting, 0.72 + ratio * 0.16)
                }
            }
            switch mode {
            case .web:
                try requireStorage(for: archive.entries, prefix: "assets/www/", at: root)
                try archive.extract(prefix: "assets/www/", to: content, progress: extractionProgress)

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
                    stripRenPyAssetEscaping: profile.usesAndroidAssetEscaping,
                    progress: extractionProgress
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

            case .unavailable where detected.engine == .kirikiri:
                try requireStorage(for: archive.entries, prefix: "", at: root)
                try archive.extract(prefix: "", to: content, progress: extractionProgress)
                let local = sourceDirectory.appending(path: source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: local)
                originalFilePath = local.path
                runtimeProfileID = "kirikiroid2-1.3.9"

            case .androidVM, .unavailable:
                await update(.copying, 0.78)
                let local = sourceDirectory.appending(path: source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: local)
                originalFilePath = local.path

            case .automatic:
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
