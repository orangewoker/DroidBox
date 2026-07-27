import Foundation
import Observation
import UIKit

@MainActor @Observable
final class AppEnvironment {
    let paths: AppPaths
    let library: GameLibrary
    let importer: ImportCoordinator
    let runtimeManager: RuntimeManager
    let diagnostics: DiagnosticsService
    let settings: AppSettings
    var selectedGame: GameRecord?
    var presentedPlayer: GameRecord?

    init() {
        do {
            let paths=try AppPaths();self.paths=paths;let library=GameLibrary(paths:paths);self.library=library
            let settings=AppSettings();self.settings=settings
            importer=ImportCoordinator(library:library,settings:settings);runtimeManager=RuntimeManager(paths:paths);diagnostics=DiagnosticsService(runtimeManager:runtimeManager)
            Task { await AppLogger.shared.configure(paths:paths);await AppLogger.shared.log(.default, "DroidBox started") }
        } catch { fatalError("Cannot initialize DroidBox storage: \(error)") }
    }
    func open(_ url: URL) {
        if url.scheme == "droidbox", let raw=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="url"})?.value, let file=URL(string:raw) { importer.start(url:file) }
        else if ["apk","zip","jar"].contains(url.pathExtension.lowercased()) {
            let securityAccess = url.startAccessingSecurityScopedResource()
            importer.start(url: url, securityAccessAlreadyActive: securityAccess)
        }
    }

    func scanImportDirectory(silentIfEmpty: Bool = false) {
        guard !importer.isImporting else {
            if !silentIfEmpty {
                importer.reportNotice(title: "正在导入", message: "请等待当前任务完成。")
            }
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: paths.importDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ))?
        .filter { ["apk", "zip", "jar"].contains($0.pathExtension.lowercased()) }
        .sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        } ?? []

        guard !files.isEmpty else {
            if !silentIfEmpty {
                importer.reportNotice(
                    title: "Import 目录为空",
                    message: "请把 APK、ZIP 或 JAR 放入“文件 → 我的 iPhone → DroidBox → Import”，然后再次扫描。"
                )
            }
            return
        }
        importer.startImportDirectory(files)
    }

    func openImportDirectoryInFiles() {
        guard let url = URL(string: "shareddocuments://") else { return }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.importer.reportNotice(
                    title: "无法打开“文件”",
                    message: "请手动进入“文件 → 我的 iPhone → DroidBox → Import”。"
                )
            }
        }
    }
}
