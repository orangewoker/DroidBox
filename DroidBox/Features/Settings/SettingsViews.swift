import SwiftUI
import UniformTypeIdentifiers

struct RuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Android Runtime") {
                    LabeledContent("状态", value: environment.runtimeManager.runtimeMessage)
                    Button("导入 Runtime ZIP", systemImage: "square.and.arrow.down") { importing = true }
                }
                Section("JIT") {
                    LabeledContent("状态", value: environment.diagnostics.jitText)
                    Button("重新检测", systemImage: "arrow.clockwise") { environment.runtimeManager.probeJIT() }
                    if environment.runtimeManager.jitStatus != .available {
                        Text("Android VM 可尝试无 JIT 模式，但速度会非常慢。快速运行路径不受影响。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("核心组件") {
                    LabeledContent("UTM/QEMU", value: DBQEMUBridge.coreBundled ? "已嵌入" : "未嵌入")
                    LabeledContent("显示通道", value: "VNC/RFB 3.8 (Raw, CopyRect)")
                    Text("Runtime 数据与 QEMU 核心分开管理。当前源码保留固定版本的构建入口，完整核心需由 macOS CI 构建。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("运行时")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    do { try await environment.runtimeManager.importRuntime(url) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("导入失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }
}

struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        NavigationStack {
            List {
                Section("设备与环境") {
                    ForEach(Array(environment.diagnostics.rows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1)
                    }
                }
                Section("隐私") { Text("DroidBox 不会自动上传诊断数据。日志仅在设备本地保存。") }
            }
            .navigationTitle("诊断")
        }
    }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        NavigationStack {
            Form {
                Section("导入限制") {
                    Picker("单文件上限", selection: $settings.maximumFileSizeGB) {
                        ForEach(AppSettings.fileSizeOptions, id: \.self) { size in
                            Text("\(size) GB").tag(size)
                        }
                    }
                    LabeledContent("最大膨胀倍数", value: "20 倍")
                }
                Section("运行策略") {
                    Toggle("自动选择运行时", isOn: $settings.automaticRuntimeSelection)
                    Picker("VM 内存", selection: $settings.vmMemoryMB) {
                        ForEach(AppSettings.memoryOptions, id: \.self) { Text("\($0) MB").tag($0) }
                    }
                    if settings.vmMemoryMB >= 3072 {
                        Text("超过 2048 MB 需要设备提供扩展内存权限，否则 iOS 可能直接终止应用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("播放") {
                    Toggle("运行时保持屏幕常亮", isOn: $settings.keepScreenAwake)
                    Toggle("显示返回/主屏幕按键", isOn: $settings.showSystemKeys)
                }
                Section("关于") {
                    LabeledContent("应用", value: "DroidBox")
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
                    LabeledContent("兼容范围", value: "iOS 18-27")
                    Button("恢复默认设置") { settings.resetToDefaults() }
                }
            }
            .navigationTitle("设置")
        }
    }
}
