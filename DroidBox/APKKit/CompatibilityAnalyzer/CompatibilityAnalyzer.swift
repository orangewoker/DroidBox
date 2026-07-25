import Foundation

enum CompatibilityAnalyzer {
    static func analyze(engine: EngineDetection, abi: [AndroidABI], manifest: ManifestInfo, paths: [String]) -> CompatibilityReport {
        var issues: [CompatibilityIssue] = []
        let text = paths.joined(separator: "\n").lowercased()
        if abi.allSatisfy({ $0 == .x86 || $0 == .x86_64 }) { issues.append(.init(severity:.error,title:"仅支持 x86",detail:"当前 Android ARM64 运行时无法执行此安装包。")) }
        if manifest.permissions.contains(where: { $0.localizedCaseInsensitiveContains("BILLING") }) { issues.append(.init(severity:.warning,title:"可能依赖 Google Play",detail:"检测到应用内购买权限，相关功能可能不可用。")) }
        if text.contains("playintegrity") || text.contains("integrityservice") { issues.append(.init(severity:.error,title:"Play Integrity",detail:"该游戏可能要求设备完整性验证。")) }
        if text.contains("split_config") { issues.append(.init(severity:.warning,title:"可能是不完整分包",detail:"请确认已导入完整的基础 APK 和配置分包。")) }
        if engine.engine == .unity || engine.engine == .godot { issues.append(.init(severity:.warning,title:"大型 3D 引擎",detail:"此引擎仅提供实验兼容，图形性能可能不足。")) }
        let level: CompatibilityLevel = issues.contains{$0.severity == .error} ? .unsupported : (engine.engine == .rpgMakerMV || engine.engine == .rpgMakerMZ) ? .excellent : issues.isEmpty ? .good : .experimental
        let summary: String = switch level { case .excellent:"适合快速运行";case .good:"预计可以运行";case .experimental:"实验兼容";case .unsupported:"检测到阻断问题" }
        return .init(level:level,engineConfidence:engine.confidence,summary:summary,issues:issues)
    }
}

