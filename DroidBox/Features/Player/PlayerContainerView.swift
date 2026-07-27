import SwiftUI

struct PlayerContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var controls = true
    @State private var settingsPresented = false
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
            case .j2me:
                J2MEPlayerView(game: game, onExit: close)
            case .androidVM:
                if let vm {
                    AndroidVMPlayerView(
                        controller: vm,
                        showSystemKeys: environment.settings.showSystemKeys &&
                            environment.settings.virtualControlsEnabled,
                        stretch: environment.settings.stretchGameDisplay,
                        controlOpacity: environment.settings.virtualControlsOpacity
                    )
                } else {
                    ProgressView().tint(.white)
                }
            default:
                UnavailableRuntimeView(
                    title: "无法启动",
                    detail: game.compatibility.summary
                )
            }

            if controls {
                VStack {
                    HStack {
                        Button { settingsPresented = true } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .accessibilityLabel("游戏设置")
                        Spacer()
                        Button { controls = false } label: {
                            Image(systemName: "eye.slash")
                        }
                        .accessibilityLabel("隐藏控制栏")
                    }
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55))
                    Spacer()
                }
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $settingsPresented) {
            PlayerSettingsView(game: game) {
                settingsPresented = false
                close()
            }
            .environment(environment)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = environment.settings.keepScreenAwake
            guard game.runtimeMode == .androidVM else { return }
            let controller = AndroidVMController(
                runtimeManager: environment.runtimeManager,
                settings: environment.settings
            )
            vm = controller
            controller.launch(game)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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

private struct AndroidVMPlayerView: View {
    let controller: AndroidVMController
    let showSystemKeys: Bool
    let stretch: Bool
    let controlOpacity: Double

    var body: some View {
        ZStack {
            if controller.display.frame != nil {
                VMDisplayView(controller: controller.display, stretch: stretch)
                if showSystemKeys {
                    VStack {
                        Spacer()
                        VMSystemKeysView(controller: controller.display)
                            .opacity(controlOpacity)
                            .padding(.bottom, 28)
                    }
                }
            } else {
                VMBootStatusView(controller: controller)
            }
        }
    }
}

private struct PlayerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    let game: GameRecord
    let exitGame: () -> Void

    var body: some View {
        @Bindable var settings = environment.settings
        NavigationStack {
            Form {
                Section("显示") {
                    Picker("分辨率", selection: $settings.playerResolution) {
                        ForEach(PlayerResolution.allCases) { resolution in
                            Text(resolution.title).tag(resolution)
                        }
                    }
                    Toggle("铺满屏幕", isOn: $settings.stretchGameDisplay)
                    Text(game.runtimeMode == .j2me
                         ? "Java ME 会立即切换逻辑分辨率；“游戏默认”使用 JAR 检测到的尺寸。"
                         : "Android 与网页游戏使用显示缩放；虚拟机内部尺寸由运行时决定。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("虚拟按键") {
                    Toggle("显示虚拟按键", isOn: $settings.virtualControlsEnabled)
                    if settings.virtualControlsEnabled {
                        LabeledContent(
                            "透明度",
                            value: "\(Int(settings.virtualControlsOpacity * 100))%"
                        )
                        Slider(value: $settings.virtualControlsOpacity, in: 0.25...1)
                    }
                }

                Section {
                    Button(
                        "退出当前游戏",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        role: .destructive
                    ) {
                        exitGame()
                    }
                } footer: {
                    Text("退出会先停止当前运行时并返回 DroidBox 游戏库。")
                }
            }
            .navigationTitle("游戏设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
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
            if controller.state == .failed {
                Button("返回", role: .cancel) { controller.reset() }
            }
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
