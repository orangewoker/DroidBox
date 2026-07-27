import Foundation
import Observation

enum PlayerResolution: String, CaseIterable, Identifiable, Sendable {
    case gameDefault
    case r128x160
    case r176x208
    case r240x320
    case r360x640
    case r720x1280
    case r1080x1920

    var id: String { rawValue }
    var title: String {
        switch self {
        case .gameDefault: "游戏默认"
        case .r128x160: "128 × 160"
        case .r176x208: "176 × 208"
        case .r240x320: "240 × 320"
        case .r360x640: "360 × 640"
        case .r720x1280: "720 × 1280"
        case .r1080x1920: "1080 × 1920"
        }
    }
    var size: (width: Int, height: Int)? {
        switch self {
        case .gameDefault: nil
        case .r128x160: (128, 160)
        case .r176x208: (176, 208)
        case .r240x320: (240, 320)
        case .r360x640: (360, 640)
        case .r720x1280: (720, 1280)
        case .r1080x1920: (1080, 1920)
        }
    }
}

/// User-adjustable runtime and import limits, persisted to `UserDefaults`.
///
/// The Settings screen previously bound to `.constant()` values, so every choice was
/// discarded on the next redraw. These properties are the real backing store, read by
/// `ImportCoordinator` and `AndroidVMController`.
///
/// Values live in a single tracked `storage` struct rather than as separate stored
/// properties: `@Observable` rewrites stored properties into computed ones, so it cannot
/// also carry `didSet` observers to persist each write.
@MainActor @Observable
final class AppSettings {
    static let memoryOptions = [1024, 1536, 2048, 3072]
    static let fileSizeOptions = [2, 4, 8, 16]

    private struct Storage {
        var vmMemoryMB = 1536
        var maximumFileSizeGB = 8
        var automaticRuntimeSelection = true
        var keepScreenAwake = true
        var showSystemKeys = true
        var playerResolution = PlayerResolution.gameDefault
        var virtualControlsEnabled = true
        var virtualControlsOpacity = 0.82
        var stretchGameDisplay = false
    }

    private var storage: Storage
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = Storage()
        loaded.vmMemoryMB = Self.readInt(defaults, .vmMemoryMB, fallback: loaded.vmMemoryMB, allowed: Self.memoryOptions)
        loaded.maximumFileSizeGB = Self.readInt(defaults, .maximumFileSizeGB, fallback: loaded.maximumFileSizeGB, allowed: Self.fileSizeOptions)
        loaded.automaticRuntimeSelection = Self.readBool(defaults, .automaticRuntimeSelection, fallback: loaded.automaticRuntimeSelection)
        loaded.keepScreenAwake = Self.readBool(defaults, .keepScreenAwake, fallback: loaded.keepScreenAwake)
        loaded.showSystemKeys = Self.readBool(defaults, .showSystemKeys, fallback: loaded.showSystemKeys)
        loaded.playerResolution = PlayerResolution(
            rawValue: defaults.string(forKey: Key.playerResolution.rawValue) ?? ""
        ) ?? loaded.playerResolution
        loaded.virtualControlsEnabled = Self.readBool(
            defaults, .virtualControlsEnabled, fallback: loaded.virtualControlsEnabled
        )
        let opacity = defaults.object(forKey: Key.virtualControlsOpacity.rawValue) as? Double
        loaded.virtualControlsOpacity = min(max(opacity ?? loaded.virtualControlsOpacity, 0.25), 1)
        loaded.stretchGameDisplay = Self.readBool(
            defaults, .stretchGameDisplay, fallback: loaded.stretchGameDisplay
        )
        storage = loaded
    }

    /// Guest RAM. Values outside the offered options are ignored so a stale or hand-edited
    /// preference cannot ask QEMU for more memory than iOS will ever grant.
    var vmMemoryMB: Int {
        get { storage.vmMemoryMB }
        set {
            guard Self.memoryOptions.contains(newValue) else { return }
            storage.vmMemoryMB = newValue
            defaults.set(newValue, forKey: Key.vmMemoryMB.rawValue)
        }
    }

    var maximumFileSizeGB: Int {
        get { storage.maximumFileSizeGB }
        set {
            guard Self.fileSizeOptions.contains(newValue) else { return }
            storage.maximumFileSizeGB = newValue
            defaults.set(newValue, forKey: Key.maximumFileSizeGB.rawValue)
        }
    }

    var automaticRuntimeSelection: Bool {
        get { storage.automaticRuntimeSelection }
        set { storage.automaticRuntimeSelection = newValue; defaults.set(newValue, forKey: Key.automaticRuntimeSelection.rawValue) }
    }

    var keepScreenAwake: Bool {
        get { storage.keepScreenAwake }
        set { storage.keepScreenAwake = newValue; defaults.set(newValue, forKey: Key.keepScreenAwake.rawValue) }
    }

    var showSystemKeys: Bool {
        get { storage.showSystemKeys }
        set { storage.showSystemKeys = newValue; defaults.set(newValue, forKey: Key.showSystemKeys.rawValue) }
    }

    var playerResolution: PlayerResolution {
        get { storage.playerResolution }
        set {
            storage.playerResolution = newValue
            defaults.set(newValue.rawValue, forKey: Key.playerResolution.rawValue)
        }
    }

    var virtualControlsEnabled: Bool {
        get { storage.virtualControlsEnabled }
        set {
            storage.virtualControlsEnabled = newValue
            defaults.set(newValue, forKey: Key.virtualControlsEnabled.rawValue)
        }
    }

    var virtualControlsOpacity: Double {
        get { storage.virtualControlsOpacity }
        set {
            storage.virtualControlsOpacity = min(max(newValue, 0.25), 1)
            defaults.set(storage.virtualControlsOpacity, forKey: Key.virtualControlsOpacity.rawValue)
        }
    }

    var stretchGameDisplay: Bool {
        get { storage.stretchGameDisplay }
        set {
            storage.stretchGameDisplay = newValue
            defaults.set(newValue, forKey: Key.stretchGameDisplay.rawValue)
        }
    }

    var maximumFileSizeBytes: UInt64 { UInt64(maximumFileSizeGB) * 1024 * 1024 * 1024 }

    func resetToDefaults() {
        let fresh = Storage()
        vmMemoryMB = fresh.vmMemoryMB
        maximumFileSizeGB = fresh.maximumFileSizeGB
        automaticRuntimeSelection = fresh.automaticRuntimeSelection
        keepScreenAwake = fresh.keepScreenAwake
        showSystemKeys = fresh.showSystemKeys
        playerResolution = fresh.playerResolution
        virtualControlsEnabled = fresh.virtualControlsEnabled
        virtualControlsOpacity = fresh.virtualControlsOpacity
        stretchGameDisplay = fresh.stretchGameDisplay
    }

    private enum Key: String {
        case vmMemoryMB = "settings.vmMemoryMB"
        case maximumFileSizeGB = "settings.maximumFileSizeGB"
        case automaticRuntimeSelection = "settings.automaticRuntimeSelection"
        case keepScreenAwake = "settings.keepScreenAwake"
        case showSystemKeys = "settings.showSystemKeys"
        case playerResolution = "settings.playerResolution"
        case virtualControlsEnabled = "settings.virtualControlsEnabled"
        case virtualControlsOpacity = "settings.virtualControlsOpacity"
        case stretchGameDisplay = "settings.stretchGameDisplay"
    }

    /// `integer(forKey:)` and `bool(forKey:)` both return zero values for a missing key,
    /// so absence has to be checked separately or a stored `false` is indistinguishable
    /// from an unset preference.
    private static func readInt(_ defaults: UserDefaults, _ key: Key, fallback: Int, allowed: [Int]) -> Int {
        guard defaults.object(forKey: key.rawValue) != nil else { return fallback }
        let value = defaults.integer(forKey: key.rawValue)
        return allowed.contains(value) ? value : fallback
    }
    private static func readBool(_ defaults: UserDefaults, _ key: Key, fallback: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) == nil ? fallback : defaults.bool(forKey: key.rawValue)
    }
}
