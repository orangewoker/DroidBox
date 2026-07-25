import Foundation
import CryptoKit
import Observation

struct RuntimeManifest:Codable,Sendable { let id:String;let version:String;let architecture:String;let downloadURL:String;let sha256:String;let size:UInt64;let license:String;let minimumAppVersion:String }

@MainActor @Observable
final class RuntimeManager {
    private(set) var jitStatus:JITStatus = .unknown
    private(set) var androidRuntimeValid=false
    private(set) var runtimeMessage="尚未导入 Android Runtime"
    let paths:AppPaths
    init(paths:AppPaths){self.paths=paths;probeJIT();verifyInstalledRuntime()}
    func probeJIT(){jitStatus=DBRuntimeProbe.canAllocateExecutableMemory() ? .available:.unavailable}
    func importRuntime(_ url:URL) async throws {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let archive=try SafeArchive(url:url,maxExpandedBytes:32*1024*1024*1024,maxRatio:10)
        guard archive.entries.contains(where:{$0.path=="runtime.json"}) else{throw DroidBoxError.runtimeCorrupted}
        let manifest=try JSONDecoder().decode(RuntimeManifest.self,from:archive.data(path:"runtime.json",maximum:1024*1024))
        guard manifest.architecture=="arm64" else{throw DroidBoxError.runtimeCorrupted}
        let root=paths.android.appending(path:"base");try? FileManager.default.removeItem(at:root);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try archive.extract(prefix:"",to:root,maximumPerFile:12*1024*1024*1024)
        try verify(manifest:manifest,root:root);verifyInstalledRuntime()
    }
    func prepareOverlay(gameID:UUID) async throws {
        let root=paths.android.appending(path:"overlays").appending(path:gameID.uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let marker=root.appending(path:"overlay.pending");try Data("DroidBox overlay v1".utf8).write(to:marker,options:.atomic)
    }
    private func verifyInstalledRuntime(){
        let file=paths.android.appending(path:"base/runtime.json")
        guard let data=try? Data(contentsOf:file),let manifest=try? JSONDecoder().decode(RuntimeManifest.self,from:data) else{androidRuntimeValid=false;return}
        do{try verify(manifest:manifest,root:file.deletingLastPathComponent());androidRuntimeValid=true;runtimeMessage="\(manifest.id) \(manifest.version)"}catch{androidRuntimeValid=false;runtimeMessage="运行时校验失败"}
    }
    private func verify(manifest:RuntimeManifest,root:URL) throws {
        guard !manifest.sha256.isEmpty else{throw DroidBoxError.runtimeCorrupted}
        let image=root.appending(path:"system.qcow2");guard let data=try? Data(contentsOf:image,options:.mappedIfSafe) else{throw DroidBoxError.runtimeCorrupted}
        let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined();guard hash==manifest.sha256.lowercased() else{throw DroidBoxError.runtimeCorrupted}
    }
}

