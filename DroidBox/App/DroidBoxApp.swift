import SwiftUI
import UIKit

/// SDL owns UIApplication's entry point so the same process can hand control to the
/// official Ren'Py iOS runtime. Until a game is launched, this host presents DroidBox's
/// SwiftUI library in a normal UIWindow.
@MainActor
final class DroidBoxFrontendHost {
    static let shared = DroidBoxFrontendHost()

    private var window: UIWindow?
    private var environment: AppEnvironment?
    private var launchSignal: DispatchSemaphore?

    var renPyRuntimeAvailable: Bool {
        Bundle.main.url(forResource: "main", withExtension: "py", subdirectory: "base") != nil
    }

    func start(signal: DispatchSemaphore) {
        launchSignal = signal
        let environment = AppEnvironment()
        self.environment = environment

        let root = RootView()
            .environment(environment)
            .onOpenURL { environment.open($0) }
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .systemBackground

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    @discardableResult
    func launchRenPy(_ game: GameRecord) -> Bool {
        guard renPyRuntimeAvailable,
              FileManager.default.fileExists(atPath: game.installedContentPath),
              let signal = launchSignal else {
            return false
        }

        setenv("RENPY_SEARCHPATH", game.installedContentPath, 1)
        setenv("RENPY_PATH_TO_SAVES", game.dataPath, 1)
        setenv("DROIDBOX_GAME_ID", game.id.uuidString, 1)
        UIApplication.shared.isIdleTimerDisabled = true

        window?.isHidden = true
        window = nil
        environment = nil
        launchSignal = nil
        signal.signal()
        return true
    }
}

/// Called by `DBRenPyMain.m` on SDL's application thread. SDL keeps UIKit's event loop
/// alive while this thread waits for the user to choose a Ren'Py game.
@_cdecl("DroidBoxFrontendMain")
func DroidBoxFrontendMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32 {
    let signal = DispatchSemaphore(value: 0)
    Task { @MainActor in
        DroidBoxFrontendHost.shared.start(signal: signal)
    }
    signal.wait()
    return 0
}
