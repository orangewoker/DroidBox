import XCTest
@testable import DroidBox

final class APKKitTests:XCTestCase{
    func testSafePaths(){XCTAssertTrue(SafeArchive.isSafe("assets/www/index.html"));XCTAssertFalse(SafeArchive.isSafe("../escape"));XCTAssertFalse(SafeArchive.isSafe("/absolute"));XCTAssertFalse(SafeArchive.isSafe("C:/escape"))}
    func testEngineDetection(){let result=EngineDetector.detect(paths:["assets/www/index.html","assets/www/js/rmmz_core.js","assets/www/data/System.json"]);XCTAssertEqual(result.engine,.rpgMakerMZ);XCTAssertGreaterThan(result.confidence,0.5)}
    func testABIAnalysis(){XCTAssertEqual(ABIAnalyzer.analyze(paths:["lib/arm64-v8a/libgame.so"]),[.arm64]);XCTAssertEqual(ABIAnalyzer.analyze(paths:["classes.dex"]),[.javaOnly])}
    func testTextManifest()throws{let xml="<manifest package=\"com.example.game\" android:versionName=\"1.2\"><application android:label=\"Test\"/></manifest>";let info=try BinaryXMLParser.parse(Data(xml.utf8));XCTAssertEqual(info.packageName,"com.example.game");XCTAssertEqual(info.label,"Test")}
    @MainActor func testAtomicLibrary()throws{let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString);let paths=try AppPaths(root:root);let library=GameLibrary(paths:paths);let report=CompatibilityReport(level:.good,engineConfidence:1,summary:"ok",issues:[]);let game=GameRecord(id:UUID(),title:"Test",packageName:nil,versionName:nil,versionCode:nil,sourceType:.apk,engine:.android,runtimeMode:.androidVM,abiList:[.arm64],iconPath:nil,coverPath:nil,originalFilePath:"a",installedContentPath:"b",dataPath:"c",runtimeProfileID:"default",orientation:.automatic,compatibility:report,controllerProfile:nil,createdAt:Date(),lastPlayedAt:nil,totalPlayTime:0);try library.add(game);XCTAssertTrue(FileManager.default.fileExists(atPath:paths.libraryFile.path));XCTAssertEqual(GameLibrary(paths:paths).games.count,1)}
}

