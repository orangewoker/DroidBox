import Foundation
import CoreFoundation
import Observation
import UIKit

enum ImportStage: String, CaseIterable, Sendable {
    case copying = "复制文件"
    case security = "安全检查"
    case parsing = "解析游戏文件"
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
    private(set) var currentFileName = ""
    private(set) var completedFileCount = 0
    private(set) var totalFileCount = 0
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

    func reportPickerCancelled() {
        notice = ImportNotice(title: "已取消导入", message: "没有选择文件。")
    }

    func reportNotice(title: String, message: String) {
        notice = ImportNotice(title: title, message: message)
    }

    func start(url: URL, securityAccessAlreadyActive: Bool = false) {
        startBatch(
            urls: [url],
            deleteSourcesAfterSuccess: false,
            securityAccessForFirstURL: securityAccessAlreadyActive
        )
    }

    /// The right-top “+” uses the same path as Documents/Import: copy the picked
    /// file into Import first, then parse and extract that application-owned copy.
    func startPickedURL(_ url: URL, securityAccessAlreadyActive: Bool) {
        guard begin(total: 1) else {
            if securityAccessAlreadyActive { url.stopAccessingSecurityScopedResource() }
            return
        }
        let paths = library.paths
        let maximumBytes = maximumFileSize
        currentFileName = url.lastPathComponent

        task = Task {
            defer { isImporting = false }
            do {
                let local = try await Self.stagePickedFile(
                    url,
                    importDirectory: paths.importDirectory,
                    maximumFileSize: maximumBytes,
                    securityAccessAlreadyActive: securityAccessAlreadyActive
                ) { [weak self] value in
                    self?.set(.copying, value * 0.20)
                }
                let result = await runBatch(
                    [.init(url: local, deleteAfterSuccess: true, securityAccessAlreadyActive: false)],
                    initialProgress: 0.20
                )
                if Task.isCancelled { finishCancelled() }
                else { finish(result) }
            } catch is CancellationError {
                finishCancelled()
            } catch {
                finishFailure(error.localizedDescription)
            }
        }
    }

    /// Imports every supported file currently in Documents/Import. A file is
    /// deleted only after its game data and metadata are safely committed.
    func startImportDirectory(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard begin(total: urls.count) else { return }
        let items = urls.map {
            ImportWorkItem(
                url: $0,
                deleteAfterSuccess: true,
                securityAccessAlreadyActive: false
            )
        }
        task = Task {
            defer { isImporting = false }
            let result = await runBatch(items)
            if Task.isCancelled { finishCancelled() }
            else { finish(result) }
        }
    }

    private struct ImportWorkItem: Sendable {
        let url: URL
        let deleteAfterSuccess: Bool
        let securityAccessAlreadyActive: Bool
    }

    private struct BatchResult {
        var games: [GameRecord] = []
        var failures: [(file: String, message: String)] = []
    }

    private func startBatch(
        urls: [URL],
        deleteSourcesAfterSuccess: Bool,
        securityAccessForFirstURL: Bool
    ) {
        guard begin(total: urls.count) else {
            if securityAccessForFirstURL, let first = urls.first {
                first.stopAccessingSecurityScopedResource()
            }
            return
        }
        let items = urls.enumerated().map { index, url in
            ImportWorkItem(
                url: url,
                deleteAfterSuccess: deleteSourcesAfterSuccess,
                securityAccessAlreadyActive: index == 0 && securityAccessForFirstURL
            )
        }
        task = Task {
            defer { isImporting = false }
            let result = await runBatch(items)
            if Task.isCancelled { finishCancelled() }
            else { finish(result) }
        }
    }

    private func begin(total: Int) -> Bool {
        guard !isImporting else {
            notice = ImportNotice(title: "正在导入", message: "请等待当前导入任务完成。")
            return false
        }
        isImporting = true
        errorMessage = nil
        notice = nil
        stage = .copying
        progress = 0
        currentFileName = ""
        completedFileCount = 0
        totalFileCount = total
        return true
    }

    private func runBatch(
        _ items: [ImportWorkItem],
        initialProgress: Double = 0
    ) async -> BatchResult {
        var result = BatchResult()
        let availableProgress = 1 - initialProgress
        let itemSpan = availableProgress / Double(max(items.count, 1))

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            currentFileName = item.url.lastPathComponent
            completedFileCount = index
            do {
                let game = try await Self.importFile(
                    item.url,
                    paths: library.paths,
                    maximumFileSize: maximumFileSize,
                    securityAccessAlreadyActive: item.securityAccessAlreadyActive
                ) { [weak self] stage, localProgress in
                    let overall = initialProgress
                        + (Double(index) + localProgress) * itemSpan
                    self?.set(stage, overall)
                }
                try library.add(game)
                if item.deleteAfterSuccess {
                    try? FileManager.default.removeItem(at: item.url)
                }
                result.games.append(game)
                completedFileCount = index + 1
            } catch is CancellationError {
                break
            } catch {
                result.failures.append((item.url.lastPathComponent, error.localizedDescription))
            }
        }
        return result
    }

    private func finish(_ result: BatchResult) {
        stage = .finished
        progress = 1
        if result.failures.isEmpty {
            let names = result.games.map(\.title).joined(separator: "、")
            notice = ImportNotice(
                title: "导入完成（\(result.games.count) 个）",
                message: names.isEmpty
                    ? "没有找到可导入的游戏。"
                    : "\(names) 已加入游戏库；Import 中的原文件已自动删除。"
            )
        } else if result.games.isEmpty {
            let details = result.failures
                .map { "\($0.file)：\($0.message)" }
                .joined(separator: "\n")
            finishFailure(details)
        } else {
            let details = result.failures.map(\.file).joined(separator: "、")
            notice = ImportNotice(
                title: "已导入 \(result.games.count) 个，失败 \(result.failures.count) 个",
                message: "失败文件仍保留在 Import：\(details)"
            )
        }
    }

    private func finishCancelled() {
        errorMessage = DroidBoxError.importCancelled.localizedDescription
        notice = ImportNotice(title: "导入已取消", message: errorMessage ?? "")
    }

    private func finishFailure(_ message: String) {
        errorMessage = message
        notice = ImportNotice(title: "导入失败", message: message)
    }


    private nonisolated static func stagePickedFile(
        _ source: URL,
        importDirectory: URL,
        maximumFileSize: UInt64,
        securityAccessAlreadyActive: Bool,
        progress update: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        let access = securityAccessAlreadyActive || source.startAccessingSecurityScopedResource()
        defer {
            if access { source.stopAccessingSecurityScopedResource() }
        }

        let standardizedImport = importDirectory.standardizedFileURL
        if source.deletingLastPathComponent().standardizedFileURL == standardizedImport {
            await update(1)
            return source
        }

        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let totalBytes = UInt64(values.fileSize ?? 0)
        guard totalBytes <= maximumFileSize else { throw DroidBoxError.fileTooLarge }

        let extensionName = source.pathExtension.lowercased()
        guard ["apk", "zip", "jar"].contains(extensionName) else {
            throw DroidBoxError.unsupported("仅支持 APK、ZIP 和 JAR 游戏文件。")
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        var destination = importDirectory.appending(path: source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = importDirectory.appending(
                path: "\(baseName)-\(UUID().uuidString.prefix(8)).\(extensionName)"
            )
        }
        let temporary = importDirectory.appending(path: ".incoming-\(UUID().uuidString)")

        do {
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: temporary)
            defer {
                try? input.close()
                try? output.close()
            }
            var copied: UInt64 = 0
            while let chunk = try input.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
                copied += UInt64(chunk.count)
                await update(totalBytes > 0 ? min(1, Double(copied) / Double(totalBytes)) : 0.5)
            }
            try output.synchronize()
            try FileManager.default.moveItem(at: temporary, to: destination)
            await update(1)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Runs on the generic executor so enumerating and extracting a multi-gigabyte APK
    /// cannot freeze SwiftUI's main actor.
    private nonisolated static func importFile(
        _ source: URL,
        paths: AppPaths,
        maximumFileSize: UInt64,
        securityAccessAlreadyActive: Bool,
        progress update: @escaping @MainActor @Sendable (ImportStage, Double) -> Void
    ) async throws -> GameRecord {
        let access = securityAccessAlreadyActive || source.startAccessingSecurityScopedResource()
        defer {
            if access { source.stopAccessingSecurityScopedResource() }
        }

        try Task.checkCancellation()
        guard ["apk", "zip", "jar"].contains(source.pathExtension.lowercased()) else {
            throw DroidBoxError.unsupported("仅支持 APK、ZIP 和 JAR 游戏文件。")
        }
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        guard UInt64(values.fileSize ?? 0) <= maximumFileSize else {
            throw DroidBoxError.fileTooLarge
        }

        if source.pathExtension.lowercased() == "jar" {
            return try await importJAR(source, paths: paths, progress: update)
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

            case .androidVM, .unavailable:
                await update(.copying, 0.78)
                let local = sourceDirectory.appending(path: source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: local)
                originalFilePath = local.path

            case .automatic, .j2me:
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
                j2meScreenWidth: nil,
                j2meScreenHeight: nil,
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

    private nonisolated static func importJAR(
        _ source: URL,
        paths: AppPaths,
        progress update: @escaping @MainActor @Sendable (ImportStage, Double) -> Void
    ) async throws -> GameRecord {
        let id = UUID()
        let root = paths.game(id)
        let sourceDirectory = root.appending(path: "source")
        let dataDirectory = root.appending(path: "saves")
        let content = root.appending(path: "content")

        do {
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            await update(.security, 0.15)

            let archive = try SafeArchive(
                url: source,
                maxExpandedBytes: 512 * 1024 * 1024,
                maxRatio: 100
            )
            guard let manifestEntry = archive.entries.first(where: {
                $0.path.caseInsensitiveCompare("META-INF/MANIFEST.MF") == .orderedSame
            }) else {
                throw DroidBoxError.unsupported("这个 JAR 缺少 META-INF/MANIFEST.MF，不是有效的 Java ME 游戏。")
            }

            await update(.parsing, 0.35)
            let manifestData = try archive.data(path: manifestEntry.path, maximum: 2 * 1024 * 1024)
            let manifest = parseJARManifest(manifestData)
            guard manifest["MIDlet-1"] != nil || manifest["MIDlet-Name"] != nil else {
                throw DroidBoxError.unsupported("没有检测到 MIDlet 信息；当前仅支持 J2ME/MIDP 游戏 JAR。")
            }

            let local = sourceDirectory.appending(path: "game.jar")
            try copyCoordinatedFile(from: source, to: local)

            await update(.icon, 0.55)
            var iconPath: String?
            if let declared = jarIconPath(manifest),
               let entry = archive.entries.first(where: {
                   $0.path.caseInsensitiveCompare(declared) == .orderedSame
               }),
               let image = UIImage(data: try archive.data(path: entry.path, maximum: 16 * 1024 * 1024)),
               let png = image.pngData() {
                let destination = root.appending(path: "icon.png")
                try png.write(to: destination, options: .atomic)
                iconPath = destination.path
            }

            await update(.engine, 0.70)
            let title = jarTitle(manifest)
                ?? source.deletingPathExtension().lastPathComponent
            let screen = jarScreenSize(manifest, fileName: source.lastPathComponent)
            let report = CompatibilityReport(
                level: .excellent,
                engineConfidence: 1,
                summary: "可使用内置 J2ME 运行时启动",
                issues: []
            )
            let game = GameRecord(
                id: id,
                title: title,
                packageName: manifest["MIDlet-Vendor"],
                versionName: manifest["MIDlet-Version"],
                versionCode: nil,
                sourceType: .jar,
                engine: .j2me,
                runtimeMode: .j2me,
                abiList: [.javaOnly],
                iconPath: iconPath,
                coverPath: nil,
                originalFilePath: local.path,
                installedContentPath: content.path,
                dataPath: dataDirectory.path,
                runtimeProfileID: "j2mejs",
                orientation: screen.width > screen.height ? .landscape : .portrait,
                compatibility: report,
                controllerProfile: .init(),
                j2meScreenWidth: screen.width,
                j2meScreenHeight: screen.height,
                createdAt: Date(),
                lastPlayedAt: nil,
                totalPlayTime: 0
            )
            await update(.runtime, 0.92)
            let metadata = try JSONEncoder().encode(game)
            try metadata.write(to: root.appending(path: "metadata.json"), options: .atomic)
            return game
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private nonisolated static func copyCoordinatedFile(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) {
            do { try FileManager.default.copyItem(at: $0, to: destination) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private nonisolated static func parseJARManifest(_ data: Data) -> [String: String] {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let content = [String.Encoding.utf8, gb18030, .windowsCP1252, .isoLatin1]
            .lazy.compactMap { String(data: data, encoding: $0) }.first ?? ""
        var values: [String: String] = [:]
        var key: String?
        var value = ""
        func flush() {
            if let key { values[key] = value }
        }
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                value += line.dropFirst()
                continue
            }
            flush()
            guard let colon = line.firstIndex(of: ":") else {
                key = nil
                value = ""
                continue
            }
            key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        flush()
        return values
    }

    private nonisolated static func jarTitle(_ manifest: [String: String]) -> String? {
        let declared = manifest["MIDlet-1"]?
            .split(separator: ",", omittingEmptySubsequences: false)
            .first.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return declared?.isEmpty == false ? declared : manifest["MIDlet-Name"]
    }

    private nonisolated static func jarIconPath(_ manifest: [String: String]) -> String? {
        var path: String?
        if let declaration = manifest["MIDlet-1"] {
            let fields = declaration.split(separator: ",", omittingEmptySubsequences: false)
            if fields.count > 1 { path = String(fields[1]).trimmingCharacters(in: .whitespaces) }
        }
        path = path?.isEmpty == false ? path : manifest["MIDlet-Icon"]
        return path.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
    }

    private nonisolated static func jarScreenSize(
        _ manifest: [String: String],
        fileName: String
    ) -> (width: Int, height: Int) {
        let values = [
            manifest["Nokia-MIDlet-Canvas-Size"],
            manifest["MIDlet-ScreenSize"],
            manifest["Nokia-MIDlet-Original-Display-Size"],
            manifest["MIDlet-Display-Size"],
            fileName
        ].compactMap { $0 }
        let expression = try? NSRegularExpression(
            pattern: #"(?<!\d)(\d{2,4})\s*[xX,*]\s*(\d{2,4})(?!\d)"#
        )
        for value in values {
            guard let expression,
                  let match = expression.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..., in: value)
                  ),
                  let widthRange = Range(match.range(at: 1), in: value),
                  let heightRange = Range(match.range(at: 2), in: value),
                  let width = Int(value[widthRange]),
                  let height = Int(value[heightRange]) else { continue }
            return (width, height)
        }
        return (240, 320)
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
