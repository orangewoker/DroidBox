import Foundation
import Observation

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
        else if ["apk","zip"].contains(url.pathExtension.lowercased()) { importer.start(url:url) }
    }
}
