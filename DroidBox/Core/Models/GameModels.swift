import Foundation

enum SourceType: String, Codable, CaseIterable, Sendable { case apk, zip, jar }
enum GameEngine: String, Codable, CaseIterable, Sendable {
    case android, renpy7, renpy8, j2me, rpgMakerMV, rpgMakerMZ, unity, godot, libgdx, unknown
    var displayName: String {
        switch self {
        case .android: "Android"
        case .renpy7: "Ren'Py 7"
        case .renpy8: "Ren'Py 8"
        case .j2me: "Java ME"
        case .rpgMakerMV: "RPG Maker MV"
        case .rpgMakerMZ: "RPG Maker MZ"
        case .unity: "Unity"
        case .godot: "Godot"
        case .libgdx: "LibGDX"
        case .unknown: "未知"
        }
    }
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
enum RuntimeMode: String, Codable, CaseIterable, Sendable { case automatic, androidVM, renpy, web, j2me, unavailable }
enum AndroidABI: String, Codable, CaseIterable, Sendable { case arm64 = "arm64-v8a", armv7 = "armeabi-v7a", x86, x86_64, javaOnly, unknown }
enum GameOrientation: String, Codable, CaseIterable, Sendable { case automatic, portrait, landscape }
enum CompatibilityLevel: String, Codable, Sendable { case excellent, good, experimental, unsupported }

struct CompatibilityIssue: Codable, Identifiable, Hashable, Sendable {
    enum Severity: String, Codable, Sendable { case info, warning, error }
    var id = UUID()
    var severity: Severity
    var title: String
    var detail: String
}

struct CompatibilityReport: Codable, Hashable, Sendable {
    var level: CompatibilityLevel
    var engineConfidence: Double
    var summary: String
    var issues: [CompatibilityIssue]
}

struct ControllerProfile: Codable, Hashable, Sendable {
    var opacity: Double = 0.6
    var scale: Double = 1
    var enabled: Bool = true
}

struct GameRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var packageName: String?
    var versionName: String?
    var versionCode: Int64?
    var sourceType: SourceType
    var engine: GameEngine
    var runtimeMode: RuntimeMode
    var abiList: [AndroidABI]
    var iconPath: String?
    var coverPath: String?
    var originalFilePath: String
    var installedContentPath: String
    var dataPath: String
    var runtimeProfileID: String
    var orientation: GameOrientation
    var compatibility: CompatibilityReport
    var controllerProfile: ControllerProfile?
    var j2meScreenWidth: Int? = nil
    var j2meScreenHeight: Int? = nil
    var createdAt: Date
    var lastPlayedAt: Date?
    var totalPlayTime: TimeInterval
}

enum JITStatus: String, Codable, Sendable { case available, unavailable, unknown }

enum DroidBoxError: LocalizedError, Sendable {
    case invalidArchive, unsafeArchiveEntry(String), unsupportedABI, incompleteSplitAPK
    case runtimeMissing, runtimeCorrupted, jitUnavailable, insufficientMemory, insufficientStorage
    case vmBootTimeout, adbUnavailable, apkInstallFailed(code: String, message: String)
    case activityNotFound, engineRuntimeMismatch, webRuntimeFailure(message: String), renPyFailure(message: String)
    case importCancelled, fileTooLarge, excessiveExpansion, duplicateEntry(String), unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: "安装包损坏或不是有效的 APK/ZIP"
        case .unsafeArchiveEntry(let path): "压缩包包含不安全路径:\(path)"
        case .unsupportedABI: "此安装包不包含可用的 ARM 架构"
        case .incompleteSplitAPK: "这是不完整的 Split APK,缺少必要分包"
        case .runtimeMissing: "所需运行时尚未安装"
        case .runtimeCorrupted: "运行时校验失败,请重新导入"
        case .jitUnavailable: "当前未启用 JIT,可尝试低速兼容模式"
        case .insufficientMemory: "可用内存不足,无法安全启动虚拟机"
        case .insufficientStorage: "存储空间不足"
        case .vmBootTimeout: "Android 虚拟机启动超时"
        case .adbUnavailable: "无法连接内置 ADB 服务"
        case .apkInstallFailed(_, let message): "APK 安装失败:\(message)"
        case .activityNotFound: "未找到可启动的 Activity"
        case .engineRuntimeMismatch: "游戏与所选运行时不匹配"
        case .webRuntimeFailure(let message): "Web 运行时错误:\(message)"
        case .renPyFailure(let message): "Ren'Py 运行时错误:\(message)"
        case .importCancelled: "导入已取消"
        case .fileTooLarge: "文件超过设置中的大小限制"
        case .excessiveExpansion: "解压体积异常,已停止导入"
        case .duplicateEntry(let path): "压缩包包含重复文件:\(path)"
        case .unsupported(let reason): reason
        }
    }
}
