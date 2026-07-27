import XCTest
@testable import DroidBox

final class APKKitTests:XCTestCase{
    func testSafePaths(){XCTAssertTrue(SafeArchive.isSafe("assets/www/index.html"));XCTAssertFalse(SafeArchive.isSafe("../escape"));XCTAssertFalse(SafeArchive.isSafe("/absolute"));XCTAssertFalse(SafeArchive.isSafe("C:/escape"))}
    func testEngineDetection(){let result=EngineDetector.detect(paths:["assets/www/index.html","assets/www/js/rmmz_core.js","assets/www/data/System.json"]);XCTAssertEqual(result.engine,.rpgMakerMZ);XCTAssertGreaterThan(result.confidence,0.5)}
    func testABIAnalysis(){XCTAssertEqual(ABIAnalyzer.analyze(paths:["lib/arm64-v8a/libgame.so"]),[.arm64]);XCTAssertEqual(ABIAnalyzer.analyze(paths:["classes.dex"]),[.javaOnly])}
    func testRenPyAndroidAssetPathUnescaping() {
        XCTAssertEqual(
            SafeArchive.unescapeRenPyAssetPath("x-cache/x-bytecode-312.rpyb"),
            "cache/bytecode-312.rpyb"
        )
        XCTAssertEqual(
            SafeArchive.unescapeRenPyAssetPath("x-images/x-ui/x-icon.png"),
            "images/ui/icon.png"
        )
    }
    func testAgent17StyleRenPyProfile() {
        let entries = [
            archiveEntry("assets/private.mp3", size: 6_905_147),
            archiveEntry("assets/x-renpy/x-common/x-00start.rpyc", size: 1_024),
            archiveEntry("assets/x-game/x-cache/x-bytecode-312.rpyb", size: 8_317_505),
            archiveEntry("assets/x-game/x-script/x-table.rpyc", size: 253_058),
            archiveEntry("lib/arm64-v8a/librenpython.so", size: 36_642_768),
        ]
        let profile = RenPyPackageAnalyzer.analyze(entries: entries)
        XCTAssertEqual(profile?.pythonBytecodeTag, "312")
        XCTAssertEqual(profile?.gamePrefix, "assets/x-game/")
        XCTAssertEqual(profile?.usesAndroidAssetEscaping, true)
        XCTAssertEqual(profile?.isSupportedByBundledRuntime, true)
    }
    func testTextManifest()throws{let xml="<manifest package=\"com.example.game\" android:versionName=\"1.2\"><application android:label=\"Test\"/></manifest>";let info=try BinaryXMLParser.parse(Data(xml.utf8));XCTAssertEqual(info.packageName,"com.example.game");XCTAssertEqual(info.label,"Test")}
    func testResourceTableStringAndDensity() throws {
        let table = try ResourceTableParser.parse(makeResourceTableFixture())
        XCTAssertEqual(table.string(for: 0x7f010000), "DroidBox Game")
        XCTAssertEqual(table.filePath(for: 0x7f020000, preferredDensity: 480), "res/mipmap-xxhdpi/icon.png")
    }
    func testADBPacketCodec() throws {
        let original = ADBPacket(command: ADBPacket.open, argument0: 7, argument1: 11, payload: Data("shell:id\0".utf8))
        let encoded = original.encoded
        let decoded = try ADBPacket.decode(header: encoded.prefix(24), payload: encoded.dropFirst(24))
        XCTAssertEqual(decoded, original)
        XCTAssertThrowsError(try ADBPacket.decode(header: encoded.prefix(24), payload: Data("bad".utf8)))
    }
    func testQCOW2OverlayHeader() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let base = root.appending(path: "base.qcow2"), overlay = root.appending(path: "overlay.qcow2")
        var header = Data(repeating: 0, count: 104)
        header.replaceSubrange(0..<4, with: UInt32(0x514649fb).bigEndianData)
        header.replaceSubrange(4..<8, with: UInt32(3).bigEndianData)
        header.replaceSubrange(20..<24, with: UInt32(16).bigEndianData)
        header.replaceSubrange(24..<32, with: UInt64(2 * 1024 * 1024 * 1024).bigEndianData)
        try header.write(to: base)
        try QCOW2OverlayBuilder.create(backingFile: base, overlay: overlay)
        let result = try Data(contentsOf: overlay)
        XCTAssertEqual(result.prefix(4), Data([0x51, 0x46, 0x49, 0xfb]))
        XCTAssertEqual(result.count, 4 * 65_536)
        XCTAssertTrue(String(decoding: result[104..<104 + base.path.utf8.count], as: UTF8.self).hasSuffix("base.qcow2"))
    }
    @MainActor func testAtomicLibrary()throws{let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString);let paths=try AppPaths(root:root);let library=GameLibrary(paths:paths);let report=CompatibilityReport(level:.good,engineConfidence:1,summary:"ok",issues:[]);let game=GameRecord(id:UUID(),title:"Test",packageName:nil,versionName:nil,versionCode:nil,sourceType:.apk,engine:.android,runtimeMode:.androidVM,abiList:[.arm64],iconPath:nil,coverPath:nil,originalFilePath:"a",installedContentPath:"b",dataPath:"c",runtimeProfileID:"default",orientation:.automatic,compatibility:report,controllerProfile:nil,createdAt:Date(),lastPlayedAt:nil,totalPlayTime:0);try library.add(game);XCTAssertTrue(FileManager.default.fileExists(atPath:paths.libraryFile.path));XCTAssertEqual(GameLibrary(paths:paths).games.count,1)}

    private func makeResourceTableFixture() -> Data {
        let strings = stringPool(["DroidBox Game", "res/mipmap-xxhdpi/icon.png"])
        let label = typeChunk(typeID: 1, stringIndex: 0, density: 0)
        let icon = typeChunk(typeID: 2, stringIndex: 1, density: 480)
        let packageSize = 288 + label.count + icon.count
        var package = Data()
        package.appendLE(UInt16(0x0200)); package.appendLE(UInt16(288)); package.appendLE(UInt32(packageSize)); package.appendLE(UInt32(0x7f))
        package.append(Data(repeating: 0, count: 256))
        for _ in 0..<5 { package.appendLE(UInt32(0)) }
        package.append(label); package.append(icon)

        var table = Data()
        table.appendLE(UInt16(0x0002)); table.appendLE(UInt16(12)); table.appendLE(UInt32(12 + strings.count + package.count)); table.appendLE(UInt32(1))
        table.append(strings); table.append(package)
        return table
    }

    private func archiveEntry(_ path: String, size: UInt64) -> ArchiveEntryInfo {
        ArchiveEntryInfo(
            path: path,
            compressed: size,
            uncompressed: size,
            localHeaderOffset: 0,
            crc32: 0,
            compressionMethod: 0,
            directory: false
        )
    }

    private func stringPool(_ strings: [String]) -> Data {
        var payload = Data(), offsets: [UInt32] = []
        for string in strings {
            let bytes = Data(string.utf8); offsets.append(UInt32(payload.count))
            payload.append(UInt8(bytes.count)); payload.append(UInt8(bytes.count)); payload.append(bytes); payload.append(0)
        }
        while payload.count % 4 != 0 { payload.append(0) }
        let stringsStart = 28 + strings.count * 4
        var result = Data()
        result.appendLE(UInt16(0x0001)); result.appendLE(UInt16(28)); result.appendLE(UInt32(stringsStart + payload.count))
        result.appendLE(UInt32(strings.count)); result.appendLE(UInt32(0)); result.appendLE(UInt32(0x100)); result.appendLE(UInt32(stringsStart)); result.appendLE(UInt32(0))
        offsets.forEach { result.appendLE($0) }; result.append(payload)
        return result
    }

    private func typeChunk(typeID: UInt8, stringIndex: UInt32, density: UInt16) -> Data {
        var config = Data(repeating: 0, count: 64); config.replaceSubrange(0..<4, with: UInt32(64).littleEndianData); config.replaceSubrange(14..<16, with: density.littleEndianData)
        var result = Data()
        result.appendLE(UInt16(0x0201)); result.appendLE(UInt16(84)); result.appendLE(UInt32(104)); result.append(typeID); result.append(0); result.appendLE(UInt16(0)); result.appendLE(UInt32(1)); result.appendLE(UInt32(88)); result.append(config)
        result.appendLE(UInt32(0)); result.appendLE(UInt16(8)); result.appendLE(UInt16(0)); result.appendLE(UInt32(0)); result.appendLE(UInt16(8)); result.append(0); result.append(0x03); result.appendLE(stringIndex)
        return result
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data { Swift.withUnsafeBytes(of: littleEndian) { Data($0) } }
    var bigEndianData: Data { Swift.withUnsafeBytes(of: bigEndian) { Data($0) } }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { append(value.littleEndianData) }
}
