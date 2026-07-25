import Foundation
import Observation
import UIKit

enum ImportStage: String, CaseIterable, Sendable { case copying="复制文件",security="安全检查",parsing="解析 APK",icon="提取图标",engine="检测引擎",compatibility="分析兼容性",runtime="准备 Runtime",finished="完成" }

@MainActor @Observable
final class ImportCoordinator {
    private(set) var stage: ImportStage = .copying
    private(set) var progress: Double = 0
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    private var task: Task<Void,Never>?
    let library: GameLibrary
    var maximumFileSize: UInt64 = 8*1024*1024*1024
    init(library: GameLibrary){self.library=library}
    func cancel(){task?.cancel()}
    func start(url: URL){
        guard !isImporting else{return};isImporting=true;errorMessage=nil
        task=Task{ do{let game=try await importFile(url);try library.add(game);stage = .finished;progress=1}catch is CancellationError{errorMessage=DroidBoxError.importCancelled.localizedDescription}catch{errorMessage=error.localizedDescription};isImporting=false }
    }
    private func importFile(_ source: URL) async throws -> GameRecord {
        let access=source.startAccessingSecurityScopedResource();defer{if access{source.stopAccessingSecurityScopedResource()}}
        try Task.checkCancellation();let values=try source.resourceValues(forKeys:[.fileSizeKey]);guard UInt64(values.fileSize ?? 0)<=maximumFileSize else{throw DroidBoxError.fileTooLarge}
        let id=UUID(),root=library.paths.game(id),sourceDir=root.appending(path:"source"),content=root.appending(path:"content"),dataDir=root.appending(path:"saves")
        try FileManager.default.createDirectory(at:sourceDir,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:content,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:dataDir,withIntermediateDirectories:true)
        let local=sourceDir.appending(path:source.lastPathComponent);try FileManager.default.copyItem(at:source,to:local);set(.security,0.12);try Task.checkCancellation()
        let archive=try SafeArchive(url:local);let paths=archive.entries.map(\.path);set(.parsing,0.25)
        let manifest:ManifestInfo
        if let item=archive.entries.first(where:{$0.path=="AndroidManifest.xml"}){manifest=try BinaryXMLParser.parse(archive.data(path:item.path,maximum:16*1024*1024))}else{manifest=ManifestInfo()}
        set(.icon,0.40)
        var resolvedTitle = manifest.label
        var extractedIconPath: String?
        if let resourcesEntry = archive.entries.first(where: { $0.path == "resources.arsc" }),
           let tableData = try? archive.data(path: resourcesEntry.path, maximum: 256 * 1024 * 1024),
           let table = try? ResourceTableParser.parse(tableData) {
            if let labelID = manifest.labelResourceID { resolvedTitle = table.string(for: labelID) ?? resolvedTitle }
            if let iconID = manifest.iconResourceID,
               let archivePath = table.filePath(for: iconID),
               let imageData = try? archive.data(path: archivePath, maximum: 64 * 1024 * 1024),
               let png = UIImage(data: imageData)?.pngData() {
                let destination = root.appending(path: "icon.png")
                try png.write(to: destination, options: .atomic)
                extractedIconPath = destination.path
            }
        }
        let abi=ABIAnalyzer.analyze(paths:paths);set(.engine,0.55);let detected=EngineDetector.detect(paths:paths);set(.compatibility,0.70)
        let report=CompatibilityAnalyzer.analyze(engine:detected,abi:abi,manifest:manifest,paths:paths);let mode:RuntimeMode
        switch detected.engine{case .rpgMakerMV,.rpgMakerMZ:mode = .web;case .renpy7,.renpy8:mode = .renpy;default:mode = report.level == .unsupported ? .unavailable : .androidVM}
        if mode == .web { try archive.extract(prefix:"assets/www/",to:content) }
        else if mode == .renpy { let prefix=paths.contains(where:{$0.hasPrefix("assets/x-game/")}) ? "assets/x-game/" : "assets/game/";try archive.extract(prefix:prefix,to:content) }
        set(.runtime,0.9);try Task.checkCancellation();let title=(resolvedTitle?.hasPrefix("@") == false ? resolvedTitle:nil) ?? source.deletingPathExtension().lastPathComponent
        let game=GameRecord(id:id,title:title,packageName:manifest.packageName,versionName:manifest.versionName,versionCode:manifest.versionCode,sourceType:source.pathExtension.lowercased()=="apk" ? .apk:.zip,engine:detected.engine,runtimeMode:mode,abiList:abi,iconPath:extractedIconPath,coverPath:nil,originalFilePath:local.path,installedContentPath:content.path,dataPath:dataDir.path,runtimeProfileID:"default",orientation:manifest.orientation,compatibility:report,controllerProfile:.init(),createdAt:Date(),lastPlayedAt:nil,totalPlayTime:0)
        let meta=try JSONEncoder().encode(game);try meta.write(to:root.appending(path:"metadata.json"),options:.atomic);return game
    }
    private func set(_ stage:ImportStage,_ progress:Double){self.stage=stage;self.progress=progress}
}
