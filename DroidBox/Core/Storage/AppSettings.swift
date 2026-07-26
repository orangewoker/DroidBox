import Foundation
import Observation

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

    var maximumFileSizeBytes: UInt64 { UInt64(maximumFileSizeGB) * 1024 * 1024 * 1024 }

    func resetToDefaults() {
        let fresh = Storage()
        vmMemoryMB = fresh.vmMemoryMB
        maximumFileSizeGB = fresh.maximumFileSizeGB
        automaticRuntimeSelection = fresh.automaticRuntimeSelection
        keepScreenAwake = fresh.keepScreenAwake
        showSystemKeys = fresh.showSystemKeys
    }

    private enum Key: String {
        case vmMemoryMB = "settings.vmMemoryMB"
        case maximumFileSizeGB = "settings.maximumFileSizeGB"
        case automaticRuntimeSelection = "settings.automaticRuntimeSelection"
        case keepScreenAwake = "settings.keepScreenAwake"
        case showSystemKeys = "settings.showSystemKeys"
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
