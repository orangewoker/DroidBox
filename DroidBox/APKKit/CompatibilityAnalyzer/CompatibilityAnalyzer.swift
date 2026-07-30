import Foundation

enum CompatibilityAnalyzer {
    static func analyze(
        engine: EngineDetection,
        abi: [AndroidABI],
        manifest: ManifestInfo,
        entries: [ArchiveEntryInfo]
    ) -> CompatibilityReport {
        var issues: [CompatibilityIssue] = []
        let paths = entries.map(\.path)
        let text = paths.joined(separator: "\n").lowercased()

        // Android ABI does not constrain the native Ren'Py path: the Python bytecode
        // and game assets are interpreted by DroidBox's iOS build of Ren'Py.
        if engine.engine != .renpy7,
           engine.engine != .renpy8,
           !abi.contains(.x86_64),
           !abi.contains(.javaOnly) {
            issues.append(.init(
                severity: .error,
                title: "缺少 x86_64 原生库",
                detail: "当前 Android-x86 Runtime 无法执行仅包含 ARM 原生库的安装包。"
            ))
        }
        if manifest.permissions.contains(where: { $0.localizedCaseInsensitiveContains("BILLING") }) {
            issues.append(.init(
                severity: .warning,
                title: "可能依赖 Google Play",
                detail: "检测到应用内购买权限，相关功能可能不可用。"
            ))
        }
        if manifest.packageName?.localizedCaseInsensitiveContains("pojavlaunch") == true {
            issues.append(.init(
                severity: .warning,
                title: "Java/OpenGL 嵌套启动器",
                detail: "PojavLauncher 本身只是 Minecraft Java 版启动器。它可尝试在 Android VM 中启动，但 Minecraft 仍受软件渲染、内存和二次 JIT 限制。"
            ))
        }
        if text.contains("playintegrity") || text.contains("integrityservice") {
            issues.append(.init(
                severity: .error,
                title: "Play Integrity",
                detail: "该游戏可能要求设备完整性验证。"
            ))
        }
        if text.contains("split_config") {
            issues.append(.init(
                severity: .warning,
                title: "可能是不完整分包",
                detail: "请确认已导入完整的基础 APK 和配置分包。"
            ))
        }
        if engine.engine == .unity || engine.engine == .godot {
            issues.append(.init(
                severity: .warning,
                title: "大型 3D 引擎",
                detail: "此引擎仅提供实验兼容，图形性能可能不足。"
            ))
        }

        if engine.engine == .renpy8, let profile = RenPyPackageAnalyzer.analyze(entries: entries) {
            if !profile.hasPrivateRuntimeArchive || !profile.hasCommonAssets {
                issues.append(.init(
                    severity: .error,
                    title: "Ren'Py 安装包不完整",
                    detail: "缺少 private.mp3 或 renpy/common 资源，无法确认这是可独立运行的 Ren'Py APK。"
                ))
            }
            if !profile.isSupportedByBundledRuntime {
                issues.append(.init(
                    severity: .error,
                    title: "Python 字节码版本不匹配",
                    detail: "内置 Ren'Py \(RenPyPackageProfile.bundledRuntimeVersion) 需要 Python \(RenPyPackageProfile.bundledPythonBytecodeTag) 字节码，此 APK 为 \(profile.pythonBytecodeTag ?? "未知")。"
                ))
            }
            if profile.gameBytes > 2 * 1024 * 1024 * 1024 {
                issues.append(.init(
                    severity: .info,
                    title: "大型 Ren'Py 游戏",
                    detail: "资源约 \(ByteCountFormatter.string(fromByteCount: Int64(profile.gameBytes), countStyle: .file))。导入时会直接解包且不保留 APK 副本，以降低峰值存储占用。"
                ))
            }
        }

        let hasBlockingIssue = issues.contains { $0.severity == .error }
        let hasNativeFastPath = engine.engine == .rpgMakerMV ||
            engine.engine == .rpgMakerMZ ||
            (engine.engine == .renpy8 && !hasBlockingIssue)
        let level: CompatibilityLevel = hasBlockingIssue
            ? .unsupported
            : hasNativeFastPath
                ? .excellent
                : issues.isEmpty ? .good : .experimental
        let summary: String = switch level {
        case .excellent: "适合快速运行"
        case .good: "预计可以运行"
        case .experimental: "实验兼容"
        case .unsupported: "检测到阻断问题"
        }
        return .init(
            level: level,
            engineConfidence: engine.confidence,
            summary: summary,
            issues: issues
        )
    }
}
