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
                J2MEPlayerView(
                    game: game,
                    onSettings: { settingsPresented = true },
                    onExit: close
                )
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

            if controls && game.runtimeMode != .j2me {
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
        .persistentSystemOverlays(.hidden)
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
        .onTapGesture {
            if game.runtimeMode != .j2me && !controls { controls = true }
        }
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
                    if game.runtimeMode == .j2me {
                        LabeledContent("Java ME 按键", value: "诺基亚机身皮肤")
                        Text("JAR 游戏固定使用 JavaPocket 的完整方向键、功能键和数字键盘。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("显示虚拟按键", isOn: $settings.virtualControlsEnabled)
                        if settings.virtualControlsEnabled {
                            LabeledContent(
                                "透明度",
                                value: "\(Int(settings.virtualControlsOpacity * 100))%"
                            )
                            Slider(value: $settings.virtualControlsOpacity, in: 0.25...1)
                        }
                    }
                }

                if game.runtimeMode == .j2me {
                    Section("性能诊断") {
                        LabeledContent("设备温控", value: thermalStatus)
                        LabeledContent(
                            "低电量模式",
                            value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "已开启" : "未开启"
                        )
                        Text(performanceHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    private var thermalStatus: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "正常"
        case .fair: "轻微升温"
        case .serious: "过热降频"
        case .critical: "严重过热"
        @unknown default: "未知"
        }
    }

    private var performanceHint: String {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            "当前 iPhone 正在热降频，掉帧主要与发热有关。退出游戏并让设备降温后再试。"
        default:
            ProcessInfo.processInfo.isLowPowerModeEnabled
                ? "低电量模式会限制性能；关闭后通常能减少 Java ME 游戏掉帧。"
                : "温控正常。少量掉帧主要来自 J2meJS 解释执行；本版已减少重复缩放和修改器后台轮询。"
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
