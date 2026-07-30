import XCTest
@testable import DroidBox

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.droidbox.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsMatchDocumentedValues() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.vmMemoryMB, 1024)
        XCTAssertEqual(settings.maximumFileSizeGB, 8)
        XCTAssertEqual(settings.maximumFileSizeBytes, 8 * 1024 * 1024 * 1024)
        XCTAssertTrue(settings.automaticRuntimeSelection)
        XCTAssertTrue(settings.showSystemKeys)
        XCTAssertEqual(settings.playerResolution, .gameDefault)
        XCTAssertTrue(settings.virtualControlsEnabled)
    }

    func testChangesPersistAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.vmMemoryMB = 1280
        settings.maximumFileSizeGB = 16
        settings.showSystemKeys = false
        settings.playerResolution = .r240x320
        settings.virtualControlsOpacity = 0.55

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.vmMemoryMB, 1280)
        XCTAssertEqual(reloaded.maximumFileSizeGB, 16)
        XCTAssertFalse(reloaded.showSystemKeys)
        XCTAssertEqual(reloaded.playerResolution, .r240x320)
        XCTAssertEqual(reloaded.virtualControlsOpacity, 0.55, accuracy: 0.001)
    }

    func testFalseBooleanSurvivesReload() {
        // A plain `bool(forKey:)` returns false for a missing key too, so the store has to
        // distinguish "absent" from "explicitly false" or defaults would win here.
        let settings = AppSettings(defaults: defaults)
        settings.automaticRuntimeSelection = false
        settings.keepScreenAwake = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.automaticRuntimeSelection)
        XCTAssertFalse(reloaded.keepScreenAwake)
    }

    func testOutOfRangeValuesAreRejected() {
        let settings = AppSettings(defaults: defaults)
        settings.vmMemoryMB = 65536
        XCTAssertEqual(settings.vmMemoryMB, 1024, "an unsupported memory size must not stick")
        settings.maximumFileSizeGB = 999
        XCTAssertEqual(settings.maximumFileSizeGB, 8)
    }

    func testResetRestoresDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.vmMemoryMB = 1536
        settings.maximumFileSizeGB = 2
        settings.showSystemKeys = false
        settings.resetToDefaults()
        XCTAssertEqual(settings.vmMemoryMB, 1024)
        XCTAssertEqual(settings.maximumFileSizeGB, 8)
        XCTAssertTrue(settings.showSystemKeys)
        XCTAssertEqual(AppSettings(defaults: defaults).vmMemoryMB, 1024, "reset must be persisted")
    }

    func testLegacyMemorySettingMigratesOnce() {
        defaults.set(1536, forKey: "settings.vmMemoryMB")
        let migrated = AppSettings(defaults: defaults)
        XCTAssertEqual(migrated.vmMemoryMB, 1024)
        migrated.vmMemoryMB = 1536
        XCTAssertEqual(AppSettings(defaults: defaults).vmMemoryMB, 1536)
    }

    func testImportCoordinatorReadsLiveLimit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let paths = try AppPaths(root: root)
        let settings = AppSettings(defaults: defaults)
        let coordinator = ImportCoordinator(library: GameLibrary(paths: paths), settings: settings)
        XCTAssertEqual(coordinator.maximumFileSize, 8 * 1024 * 1024 * 1024)
        settings.maximumFileSizeGB = 2
        XCTAssertEqual(coordinator.maximumFileSize, 2 * 1024 * 1024 * 1024,
                       "the importer must follow the setting rather than cache it")
        try? FileManager.default.removeItem(at: root)
    }
}
