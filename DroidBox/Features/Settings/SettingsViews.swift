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
                    LabeledContent(
                        "状态",
                        value: DBQEMUBridge.coreBundled
                            ? environment.runtimeManager.runtimeMessage
                            : "不可用（QEMU Core 未嵌入）"
                    )
                    Button("导入 Runtime ZIP", systemImage: "square.and.arrow.down") { importing = true }
                        .disabled(!DBQEMUBridge.coreBundled)
                    Text("Android Runtime 是供 QEMU 虚拟机启动 Android 客体系统的磁盘镜像，不是通用游戏插件。此 IPA 没有 QEMU Core，所以单独导入镜像也无法运行普通 Android APK。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("本机游戏引擎") {
                    Label("Ren'Py APK 直接使用内置 Ren'Py 8.4.1，不需要 Android Runtime。", systemImage: "checkmark.circle")
                    Label("Java ME 游戏直接使用内置 J2ME 引擎，不需要 JIT。", systemImage: "cup.and.heat.waves")
                }
                Section("JIT") {
                    LabeledContent("状态", value: environment.diagnostics.jitText)
                    Button("重新检测", systemImage: "arrow.clockwise") { environment.runtimeManager.probeJIT() }
                    Text("检测会区分 MAP_JIT 权限和 StikDebug 调试器权限。只有具备 MAP_JIT，或进程确实处于 CS_DEBUGGED/P_TRACED 状态且能创建可执行内存时，才会显示可用。Ren'Py 与 Java ME 不依赖 JIT。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if environment.runtimeManager.jitStatus != .available {
                        Text("Android VM 可尝试无 JIT 模式,但速度会非常慢。快速运行路径不受影响。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("核心组件") {
                    LabeledContent(
                        "Ren'Py",
                        value: DroidBoxFrontendHost.shared.renPyRuntimeAvailable
                            ? "\(RenPyPackageProfile.bundledRuntimeVersion) 已嵌入"
                            : "未嵌入"
                    )
                    LabeledContent(
                        "J2ME",
                        value: Bundle.main.url(
                            forResource: "index",
                            withExtension: "html",
                            subdirectory: "j2mejs"
                        ) == nil ? "未嵌入" : "已嵌入"
                    )
                    LabeledContent("UTM/QEMU", value: DBQEMUBridge.coreBundled ? "已嵌入" : "未嵌入")
                    LabeledContent("显示通道", value: "VNC/RFB 3.8 (Raw, CopyRect)")
                    Text("Android Runtime 数据与 QEMU 核心是两项独立组件；两者缺一都不能启动 Android VM。")
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
                Section("本地导入目录") {
                    LabeledContent("位置", value: "DroidBox/Import")
                    Button("打开 DroidBox 文件夹", systemImage: "folder") {
                        environment.openImportDirectoryInFiles()
                    }
                    Button("扫描 Import 目录", systemImage: "arrow.clockwise") {
                        environment.scanImportDirectory()
                    }
                    Text("如果系统文件选择器或 LiveContainer 没有回调，可把 APK/ZIP 直接放进此目录，再回到 DroidBox 扫描。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                        Text("超过 2048 MB 需要设备提供扩展内存权限,否则 iOS 可能直接终止应用。")
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
