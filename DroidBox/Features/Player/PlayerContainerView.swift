import SwiftUI

struct PlayerContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var controls = true
    @State private var vm: AndroidVMController?
    let game: GameRecord

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch game.runtimeMode {
            case .web:
                RPGMakerPlayerView(game: game).ignoresSafeArea()
            case .renpy:
                RenPyLaunchView(game: game)
            case .androidVM:
                if let vm { AndroidVMPlayerView(controller: vm, showSystemKeys: environment.settings.showSystemKeys) }
                else { ProgressView().tint(.white) }
            default:
                UnavailableRuntimeView(title: "无法启动", detail: game.compatibility.summary)
            }
            if controls {
                VStack {
                    HStack {
                        Button { close() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("返回游戏库")
                        Spacer()
                        Button { controls = false } label: { Image(systemName: "eye.slash") }
                            .accessibilityLabel("隐藏控制栏")
                    }
                    .font(.title3).foregroundStyle(.white).padding(12).background(.black.opacity(0.55))
                    Spacer()
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = environment.settings.keepScreenAwake
            guard game.runtimeMode == .androidVM else { return }
            let controller = AndroidVMController(runtimeManager: environment.runtimeManager, settings: environment.settings)
            vm = controller
            controller.launch(game)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Dismissing the sheet must tear the VM down, or QEMU keeps running in the
            // background with the framebuffer loop still attached to it.
            vm?.stop()
        }
        .onTapGesture { if !controls { controls = true } }
    }

    private func close() {
        vm?.stop()
        dismiss()
    }
}

@MainActor
private struct RenPyLaunchView: View {
    let game: GameRecord
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            if failed {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                Text("Ren'Py Runtime 未嵌入")
                    .font(.headline)
                Text("请使用 Full Runtime 构建的 IPA。")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().tint(.white)
                Text("正在启动 Ren'Py \(game.runtimeProfileID)")
            }
        }
        .foregroundStyle(.white)
        .task {
            guard !DroidBoxFrontendHost.shared.launchRenPy(game) else { return }
            failed = true
        }
    }
}

/// Shows boot progress until the guest produces its first frame, then the live screen.
private struct AndroidVMPlayerView: View {
    let controller: AndroidVMController
    let showSystemKeys: Bool

    var body: some View {
        ZStack {
            if controller.display.frame != nil {
                VMDisplayView(controller: controller.display)
                if showSystemKeys {
                    VStack {
                        Spacer()
                        VMSystemKeysView(controller: controller.display).padding(.bottom, 28)
                    }
                }
            } else {
                VMBootStatusView(controller: controller)
            }
        }
    }
}

private struct VMBootStatusView: View {
    let controller: AndroidVMController

    var body: some View {
        VStack(spacing: 18) {
            if controller.state != .failed { ProgressView().tint(.white) }
            Text(controller.state.title).font(.headline)
            Text(controller.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if controller.state == .failed { Button("返回", role: .cancel) { controller.reset() } }
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

private struct UnavailableRuntimeView: View {
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(detail)
        }
        .foregroundStyle(.white)
    }
}
