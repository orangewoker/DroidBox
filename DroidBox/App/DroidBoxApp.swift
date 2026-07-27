import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// SDL owns UIApplication's entry point so the same process can hand control to the
/// official Ren'Py iOS runtime. Until a game is launched, this host presents DroidBox's
/// SwiftUI library in a normal UIWindow.
@MainActor
final class DroidBoxFrontendHost: NSObject, UIDocumentPickerDelegate {
    static let shared = DroidBoxFrontendHost()

    private var window: UIWindow?
    private var environment: AppEnvironment?
    private var launchSignal: DispatchSemaphore?
    private weak var activeDocumentPicker: UIDocumentPickerViewController?

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

    /// SwiftUI's fileImporter is presented through SDL's manually hosted scene and
    /// did not reliably deliver its completion callback on device. Present UIKit's
    /// picker directly, retain its delegate here, open files in place (no silent
    /// 3 GB copy), and start importing only after the picker has dismissed.
    func presentGameImporter() {
        guard let environment else { return }
        guard !environment.importer.isImporting else {
            environment.importer.reportNotice(
                title: "正在导入",
                message: "请等待当前任务完成。"
            )
            return
        }
        guard activeDocumentPicker == nil else { return }
        guard var presenter = window?.rootViewController else {
            environment.importer.reportNotice(
                title: "无法打开文件选择器",
                message: "找不到当前显示窗口。可以改用 DroidBox 的 Import 目录导入。"
            )
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let apk = UTType(filenameExtension: "apk") ?? .data
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [apk, .zip, .archive, .data],
            asCopy: false
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        activeDocumentPicker = picker
        presenter.present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        activeDocumentPicker = nil
        guard let url = urls.first else {
            environment?.importer.reportPickerCancelled()
            return
        }
        controller.dismiss(animated: true) { [weak self] in
            Task { @MainActor in
                self?.environment?.importer.start(url: url)
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        activeDocumentPicker = nil
        environment?.importer.reportPickerCancelled()
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
@MainActor
@_cdecl("DroidBoxFrontendMain")
func DroidBoxFrontendMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32 {
    let signal = DispatchSemaphore(value: 0)
    DroidBoxFrontendHost.shared.start(signal: signal)

    // SDL 2 invokes its iOS main function from `postFinishLaunch` on the UIKit
    // main thread. Blocking that thread on the semaphore leaves the app black.
    // Run the main RunLoop until the SwiftUI player signals the Ren'Py handoff.
    while signal.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: 0.01)
        )
    }
    return 0
}
