import Foundation
import Observation
import SwiftUI
import UIKit
import WebKit

enum J2MEButton: String, CaseIterable, Identifiable {
    case up, down, left, right, fire
    case num0, num1, num2, num3, num4, num5, num6, num7, num8, num9
    case star, pound, softkeyLeft, softkeyRight, menu

    var id: String { rawValue }
    var title: String {
        switch self {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .fire: "OK"
        case .num0: "0"
        case .num1: "1"
        case .num2: "2"
        case .num3: "3"
        case .num4: "4"
        case .num5: "5"
        case .num6: "6"
        case .num7: "7"
        case .num8: "8"
        case .num9: "9"
        case .star: "*"
        case .pound: "#"
        case .softkeyLeft: "L"
        case .softkeyRight: "R"
        case .menu: "MENU"
        }
    }
    var keyCode: String {
        switch self {
        case .up: "ArrowUp"
        case .down: "ArrowDown"
        case .left: "ArrowLeft"
        case .right: "ArrowRight"
        case .fire: "Enter"
        case .num0: "Digit0"
        case .num1: "Digit1"
        case .num2: "Digit2"
        case .num3: "Digit3"
        case .num4: "Digit4"
        case .num5: "Digit5"
        case .num6: "Digit6"
        case .num7: "Digit7"
        case .num8: "Digit8"
        case .num9: "Digit9"
        case .star: "KeyE"
        case .pound: "KeyR"
        case .softkeyLeft: "F1"
        case .softkeyRight: "F2"
        case .menu: "F1"
        }
    }
}

@MainActor @Observable
final class J2MEPlayerController {
    @ObservationIgnored private weak var emulator: J2MEEmulatorView?
    private(set) var ready = false
    private(set) var errorMessage: String?
    private(set) var isMuted = false
    private(set) var speedMultiplier = 1
    private(set) var hasQuickSnapshot = false
    private(set) var isSnapshotBusy = false
    var isModifierPresented = false

    func attach(_ emulator: J2MEEmulatorView) {
        self.emulator = emulator
        emulator.onReady = { [weak self] in
            self?.ready = true
            self?.errorMessage = nil
        }
        emulator.onError = { [weak self] in self?.errorMessage = $0 }
    }

    func press(_ button: J2MEButton, pressed: Bool) {
        emulator?.press(button, pressed: pressed)
    }
    func apply(resolution: PlayerResolution, stretch: Bool) {
        emulator?.apply(resolution: resolution, stretch: stretch)
    }
    func pause() { emulator?.pause() }
    func resume() { emulator?.resume() }
    func save() { emulator?.save() }

    func toggleMute() {
        isMuted.toggle()
        emulator?.setMuted(isMuted)
    }

    func cycleSpeed() {
        switch speedMultiplier {
        case 1: speedMultiplier = 2
        case 2: speedMultiplier = 4
        case 4: speedMultiplier = 5
        default: speedMultiplier = 1
        }
        emulator?.setSpeed(Double(speedMultiplier))
    }

    func captureQuickSnapshot() async -> Bool {
        guard let emulator, ready, !isSnapshotBusy else {
            return false
        }
        isSnapshotBusy = true
        let success = await emulator.captureQuickSnapshot()
        if success { hasQuickSnapshot = true }
        isSnapshotBusy = false
        return success
    }

    func restoreQuickSnapshot() async -> Bool {
        guard let emulator, hasQuickSnapshot, !isSnapshotBusy else { return false }
        isSnapshotBusy = true
        let success = await emulator.restoreQuickSnapshot()
        isSnapshotBusy = false
        return success
    }

    func toggleModifier() {
        guard ready else { return }
        isModifierPresented.toggle()
    }

    func modifierFirstScan(
        type: ModifierValueType,
        value: Double
    ) async throws -> ModifierScanPage {
        guard let emulator else { throw DataModifierError.runtimeUnavailable }
        return try await emulator.modifierFirstScan(type: type, value: value)
    }

    func modifierRefine(
        filter: ModifierFilter,
        value: Double
    ) async throws -> ModifierScanPage {
        guard let emulator else { throw DataModifierError.runtimeUnavailable }
        return try await emulator.modifierRefine(filter: filter, value: value)
    }

    func modifierRefresh() async throws -> ModifierScanPage {
        guard let emulator else { throw DataModifierError.runtimeUnavailable }
        return try await emulator.modifierRefresh()
    }

    func modifierWrite(
        candidate: ModifierCandidate,
        value: Double,
        freeze: Bool
    ) async throws -> ModifierScanPage {
        guard let emulator else { throw DataModifierError.runtimeUnavailable }
        return try await emulator.modifierWrite(
            candidate: candidate,
            value: value,
            freeze: freeze
        )
    }

    func modifierReset() async throws {
        guard let emulator else { throw DataModifierError.runtimeUnavailable }
        try await emulator.modifierReset()
    }
}

struct J2MEPlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = J2MEPlayerController()
    let game: GameRecord
    let onSettings: () -> Void
    let onExit: () -> Void

    var body: some View {
        ManicJ2MESkinView(
            game: game,
            controller: controller,
            resolution: environment.settings.playerResolution,
            stretch: environment.settings.stretchGameDisplay,
            onSettings: onSettings,
            onExit: onExit
        )
        .overlay {
            if !controller.ready {
                VStack(spacing: 14) {
                    if let error = controller.errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error).multilineTextAlignment(.center)
                    } else {
                        ProgressView().tint(.white)
                        Text("正在启动 Java ME…")
                    }
                }
                .foregroundStyle(.white)
                .padding(22)
                .background(.black.opacity(0.85), in: .rect(cornerRadius: 18))
                .padding(28)
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active: controller.resume()
            case .inactive: controller.pause()
            case .background: controller.save()
            @unknown default: break
            }
        }
        .onDisappear { controller.save() }
    }
}

struct J2MEWebView: UIViewRepresentable {
    let game: GameRecord
    let controller: J2MEPlayerController
    let resolution: PlayerResolution
    let stretch: Bool
    let onExit: () -> Void

    func makeUIView(context: Context) -> J2MEEmulatorView {
        let view = J2MEEmulatorView(game: game)
        view.onExit = onExit
        controller.attach(view)
        view.apply(resolution: resolution, stretch: stretch)
        return view
    }

    func updateUIView(_ uiView: J2MEEmulatorView, context: Context) {
        uiView.onExit = onExit
        uiView.apply(resolution: resolution, stretch: stretch)
    }
}

private struct J2MEKeypad: View {
    let onButton: (J2MEButton, Bool) -> Void
    private let keypad: [[J2MEButton]] = [
        [.num1, .num2, .num3],
        [.num4, .num5, .num6],
        [.num7, .num8, .num9],
        [.star, .num0, .pound]
    ]

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 6) {
                HStack {
                    key(.softkeyLeft, size: 44)
                    Spacer()
                    key(.softkeyRight, size: 44)
                }
                key(.up)
                HStack(spacing: 2) {
                    key(.left)
                    key(.fire)
                    key(.right)
                }
                key(.down)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 5) {
                ForEach(keypad.indices, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(keypad[row]) { key($0, size: 42) }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func key(_ button: J2MEButton, size: CGFloat = 48) -> some View {
        J2MEKey(button: button, size: size) { onButton(button, $0) }
    }
}

private struct J2MEKey: View {
    let button: J2MEButton
    let size: CGFloat
    let changed: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(button.title)
            .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(pressed ? Color.indigo : Color.white.opacity(0.14), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.2)))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setPressed(true) }
                    .onEnded { _ in setPressed(false) }
            )
    }

    private func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        changed(value)
    }
}

@MainActor
final class J2MEEmulatorView: UIView {
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onExit: (() -> Void)?

    private let game: GameRecord
    private let schemeHandler: J2MEResourceSchemeHandler
    private var runtimeReady = false
    private var opened = false
    private var attempts = 0
    private var requestedResolution = PlayerResolution.gameDefault
    private var stretch = false
    private var pressed = Set<J2MEButton>()
    private var modifierValueType = ModifierValueType.int32

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "droidbox-j2me")
        let userContent = WKUserContentController()
        userContent.add(WeakJ2MEMessageHandler(target: self), name: "j2me")
        configuration.userContentController = userContent

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = true
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(game: GameRecord) {
        self.game = game
        schemeHandler = J2MEResourceSchemeHandler(
            runtimeRoot: Self.runtimeRoot,
            gameJAR: URL(fileURLWithPath: game.originalFilePath)
        )
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        guard Self.runtimeRoot != nil else {
            onError?("内置 J2ME 运行时不完整，请重新安装 DroidBox。")
            return
        }
        webView.load(URLRequest(url: URL(string: "droidbox-j2me://runtime/index.html")!))
    }

    required init?(coder: NSCoder) { nil }

    private static var runtimeRoot: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "j2mejs")?
            .deletingLastPathComponent()
    }

    func press(_ button: J2MEButton, pressed isPressed: Bool) {
        if isPressed {
            guard pressed.insert(button).inserted else { return }
        } else {
            pressed.remove(button)
        }
        evaluate("if (window.Input) window.Input.\(isPressed ? "keyDown" : "keyUp")(\(Self.js(button.keyCode)));")
    }

    func apply(resolution: PlayerResolution, stretch: Bool) {
        requestedResolution = resolution
        self.stretch = stretch
        guard runtimeReady else { return }
        let size = resolution.size ?? (
            game.j2meScreenWidth ?? 240,
            game.j2meScreenHeight ?? 320
        )
        evaluate("""
        if (window.j2meAPI) {
          window.j2meAPI.setScaleMode(\(Self.js(stretch ? "stretch" : "fit")));
          window.j2meAPI.setScreenSize(\(size.0), \(size.1));
          if (window.j2meAPI.safeApply) window.j2meAPI.safeApply();
        }
        """)
    }

    func pause() { evaluate("if (window.j2meAPI) window.j2meAPI.pause();") }
    func resume() { evaluate("if (window.j2meAPI) window.j2meAPI.resume();") }
    func setMuted(_ muted: Bool) {
        evaluate("if (window.j2meAPI && window.j2meAPI.setMute) window.j2meAPI.setMute(\(muted));")
    }
    func setSpeed(_ multiplier: Double) {
        let value = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            multiplier
        )
        evaluate("if (window.j2meAPI && window.j2meAPI.setSpeed) window.j2meAPI.setSpeed(\(value));")
    }
    func captureQuickSnapshot() async -> Bool {
        do {
            let raw = try await webView.callAsyncJavaScript(
                """
                if (!window.j2meAPI || !window.j2meAPI.captureQuickSnapshot) {
                  return { success: false, error: 'Snapshot API unavailable' };
                }
                return window.j2meAPI.captureQuickSnapshot();
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return (raw as? [String: Any])?["success"] as? Bool ?? false
        } catch {
            onError?("快照保存失败：\(error.localizedDescription)")
            return false
        }
    }
    func restoreQuickSnapshot() async -> Bool {
        do {
            let raw = try await webView.callAsyncJavaScript(
                """
                if (!window.j2meAPI || !window.j2meAPI.restoreQuickSnapshot) {
                  return { success: false, error: 'Snapshot API unavailable' };
                }
                return window.j2meAPI.restoreQuickSnapshot();
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return (raw as? [String: Any])?["success"] as? Bool ?? false
        } catch {
            onError?("快照加载失败：\(error.localizedDescription)")
            return false
        }
    }
    func modifierFirstScan(
        type: ModifierValueType,
        value: Double
    ) async throws -> ModifierScanPage {
        modifierValueType = type
        return try await modifierPage(
            "window.j2meModifier.firstScan('\(type.rawValue)', \(Self.jsNumber(value)))",
            type: type
        )
    }
    func modifierRefine(
        filter: ModifierFilter,
        value: Double
    ) async throws -> ModifierScanPage {
        try await modifierPage(
            "window.j2meModifier.refine('\(filter.rawValue)', \(Self.jsNumber(value)))",
            type: modifierValueType
        )
    }
    func modifierRefresh() async throws -> ModifierScanPage {
        try await modifierPage(
            "window.j2meModifier.refresh()",
            type: modifierValueType
        )
    }
    func modifierWrite(
        candidate: ModifierCandidate,
        value: Double,
        freeze: Bool
    ) async throws -> ModifierScanPage {
        guard let address = candidate.address else {
            throw DataModifierError.candidateMissing
        }
        modifierValueType = candidate.type
        return try await modifierPage(
            "window.j2meModifier.write('\(candidate.type.rawValue)', \(address), \(Self.jsNumber(value)), \(freeze))",
            type: candidate.type
        )
    }
    func modifierReset() async throws {
        _ = try await modifierPage(
            "window.j2meModifier.reset()",
            type: modifierValueType
        )
    }
    func save() {
        evaluate("""
        if (window.j2meAPI && window.j2meAPI.getSaveData) {
          window.j2meAPI.getSaveData().then(function(value) {
            window.webkit.messageHandlers.j2me.postMessage({type:'getSaveDataResult', base64:value});
          });
        }
        """)
    }

    private func openGame() {
        guard runtimeReady, !opened else { return }
        opened = true
        let size = requestedResolution.size ?? (
            game.j2meScreenWidth ?? 240,
            game.j2meScreenHeight ?? 320
        )
        let saveURL = URL(fileURLWithPath: game.dataPath).appending(path: "j2me-rms.zip")
        let save = (try? Data(contentsOf: saveURL))?.base64EncodedString()
        let font = Self.fontSize(width: size.0, height: size.1)
        evaluate("""
        (async function() {
          try {
            const response = await fetch('droidbox-j2me://runtime/__game.jar');
            if (!response.ok) throw new Error('读取 JAR 失败：HTTP ' + response.status);
            const bytes = new Uint8Array(await response.arrayBuffer());
            if (!window.j2me || !window.j2me.openJar) throw new Error('J2ME API unavailable');
            window.j2meAPI.setScaleMode(\(Self.js(stretch ? "stretch" : "fit")));
            window.j2meAPI.setConfig('fontSize', \(font));
            \(save.map { "await window.j2meAPI.loadSaveData(\(Self.js($0)));" } ?? "")
            window.j2me.openJar(bytes, \(Self.js(URL(fileURLWithPath: game.originalFilePath).lastPathComponent)),
                                \(Self.js("\(size.0)x\(size.1)")), false);
            window.webkit.messageHandlers.j2me.postMessage({type:'openJarCompletion', success:true});
          } catch (error) {
            window.webkit.messageHandlers.j2me.postMessage({
              type:'openJarCompletion', success:false, error:String(error)
            });
          }
        })();
        """)
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error { self?.onError?(error.localizedDescription) }
        }
    }

    private func modifierPage(
        _ expression: String,
        type: ModifierValueType
    ) async throws -> ModifierScanPage {
        guard runtimeReady else { throw DataModifierError.runtimeUnavailable }
        let raw = try await webView.callAsyncJavaScript(
            """
            if (!window.j2meModifier) throw new Error('Data modifier unavailable');
            return \(expression);
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try Self.decodeModifierPage(raw, type: type)
    }

    private static func decodeModifierPage(
        _ raw: Any,
        type: ModifierValueType
    ) throws -> ModifierScanPage {
        guard let payload = raw as? [String: Any],
              let rows = payload["results"] as? [[String: Any]]
        else { throw DataModifierError.invalidResponse }

        let candidates = rows.compactMap { row -> ModifierCandidate? in
            guard let address = (row["address"] as? NSNumber)?.intValue,
                  let value = (row["value"] as? NSNumber)?.doubleValue
            else { return nil }
            return ModifierCandidate(
                id: row["id"] as? String ?? "\(type.rawValue):\(address)",
                type: type,
                address: address,
                source: nil,
                offset: nil,
                endian: nil,
                value: value,
                isFrozen: (row["frozen"] as? NSNumber)?.boolValue ?? false
            )
        }
        return ModifierScanPage(
            total: (payload["total"] as? NSNumber)?.intValue ?? candidates.count,
            truncated: (payload["truncated"] as? NSNumber)?.boolValue ?? false,
            results: candidates
        )
    }

    fileprivate func message(_ body: Any) {
        guard let payload = body as? [String: Any],
              let type = payload["type"] as? String else { return }
        switch type {
        case "ready":
            runtimeReady = true
            openGame()
        case "openJarCompletion":
            if payload["success"] as? Bool == true { onReady?() }
            else { onError?(payload["error"] as? String ?? "Java ME 游戏启动失败。") }
        case "saveDataWritten", "getSaveDataResult":
            guard let encoded = payload["data"] as? String ?? payload["base64"] as? String,
                  let data = Data(base64Encoded: encoded) else { return }
            do {
                let directory = URL(fileURLWithPath: game.dataPath)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appending(path: "j2me-rms.zip"), options: .atomic)
            } catch {
                onError?("J2ME 存档写入失败：\(error.localizedDescription)")
            }
        case "exit":
            save()
            onExit?()
        default:
            break
        }
    }

    private static func js(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    private static func jsNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(
            format: "%.17g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func fontSize(width: Int, height: Int) -> Int {
        switch min(width, height) {
        case ..<112: 10
        case ..<150: 11
        case ..<220: 13
        case ..<300: 16
        case ..<350: 18
        default: 20
        }
    }
}

extension J2MEEmulatorView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollReady()
    }

    private func pollReady() {
        webView.evaluateJavaScript("""
        typeof window.j2me !== 'undefined' &&
        typeof CLASSES !== 'undefined' && !!CLASSES.java_lang_Object &&
        typeof JARStore !== 'undefined' && typeof MIDP !== 'undefined'
        """) { [weak self] result, error in
            guard let self else { return }
            if result as? Bool == true {
                self.runtimeReady = true
                self.openGame()
            } else if self.attempts < 40 {
                self.attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    self?.pollReady()
                }
            } else {
                self.onError?(error?.localizedDescription ?? "J2ME 引擎初始化超时。")
            }
        }
    }
}

private final class WeakJ2MEMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: J2MEEmulatorView?
    init(target: J2MEEmulatorView) { self.target = target }
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in self?.target?.message(message.body) }
    }
}

private final class J2MEResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let runtimeRoot: URL?
    private let gameJAR: URL

    init(runtimeRoot: URL?, gameJAR: URL) {
        self.runtimeRoot = runtimeRoot
        self.gameJAR = gameJAR
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            fail(urlSchemeTask, code: 400)
            return
        }
        let relative = requestURL.path.removingPercentEncoding?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let file: URL?
        if relative == "__game.jar" {
            file = gameJAR
        } else if let runtimeRoot, !relative.contains("..") {
            file = runtimeRoot.appending(path: relative.isEmpty ? "index.html" : relative)
        } else {
            file = nil
        }
        guard let file,
              FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else {
            fail(urlSchemeTask, code: 404)
            return
        }
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mime(for: file.pathExtension),
                "Content-Length": "\(data.count)",
                "Cache-Control": relative == "__game.jar" ? "no-store" : "public, max-age=3600"
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, code: Int) {
        task.didFailWithError(NSError(
            domain: NSURLErrorDomain,
            code: code == 404 ? NSURLErrorFileDoesNotExist : NSURLErrorBadURL
        ))
    }

    private static func mime(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html": "text/html"
        case "js": "text/javascript"
        case "css": "text/css"
        case "jar": "application/java-archive"
        case "wasm": "application/wasm"
        case "png": "image/png"
        case "sf2": "application/octet-stream"
        default: "application/octet-stream"
        }
    }
}
