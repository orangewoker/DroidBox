import Foundation
import CryptoKit
import Observation

struct RuntimeManifest:Codable,Sendable { let id:String;let version:String;let architecture:String;let downloadURL:String;let sha256:String;let size:UInt64;let license:String;let minimumAppVersion:String;let qemuArguments:[String]? }

@MainActor @Observable
final class RuntimeManager {
    private(set) var jitStatus:JITStatus = .unknown
    private(set) var androidRuntimeValid=false
    private(set) var runtimeMessage="尚未导入 Android Runtime"
    let paths:AppPaths
    private var installedManifest: RuntimeManifest?
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
        guard androidRuntimeValid else { throw DroidBoxError.runtimeMissing }
        let root=paths.android.appending(path:"overlays").appending(path:gameID.uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let overlay = root.appending(path: "disk.qcow2")
        if !FileManager.default.fileExists(atPath: overlay.path) { try QCOW2OverlayBuilder.create(backingFile: baseImageURL, overlay: overlay) }
    }
    func qemuArguments(gameID: UUID, qmpPort: UInt16, adbPort: UInt16, vncDisplay: Int, memoryMB: Int = 1536) throws -> [String] {
        guard let manifest = installedManifest else { throw DroidBoxError.runtimeMissing }
        let overlay = paths.android.appending(path:"overlays").appending(path:gameID.uuidString).appending(path:"disk.qcow2")
        let replacements = ["{runtime}": runtimeRoot.path, "{overlay}": overlay.path, "{base}": baseImageURL.path, "{qmpPort}": String(qmpPort), "{adbPort}": String(adbPort), "{vncDisplay}": String(vncDisplay), "{memoryMB}": String(memoryMB)]
        if let custom = manifest.qemuArguments, !custom.isEmpty {
            return custom.map { argument in replacements.reduce(argument) { $0.replacingOccurrences(of: $1.key, with: $1.value) } }
        }
        return ["-machine","virt","-cpu","max","-smp","4","-m",String(memoryMB),"-drive","file=\(overlay.path),if=none,id=system,format=qcow2","-device","virtio-blk-pci,drive=system","-device","virtio-gpu-pci","-device","virtio-keyboard-pci","-device","virtio-tablet-pci","-netdev","user,id=net0,hostfwd=tcp:127.0.0.1:\(adbPort)-:5555","-device","virtio-net-pci,netdev=net0","-qmp","tcp:127.0.0.1:\(qmpPort),server=on,wait=off","-vnc","127.0.0.1:\(vncDisplay)"]
    }
    var runtimeRoot: URL { paths.android.appending(path:"base") }
    var baseImageURL: URL { runtimeRoot.appending(path:"system.qcow2") }
    private func verifyInstalledRuntime(){
        let file=paths.android.appending(path:"base/runtime.json")
        guard let data=try? Data(contentsOf:file),let manifest=try? JSONDecoder().decode(RuntimeManifest.self,from:data) else{androidRuntimeValid=false;installedManifest=nil;return}
        do{try verify(manifest:manifest,root:file.deletingLastPathComponent());installedManifest=manifest;androidRuntimeValid=true;runtimeMessage="\(manifest.id) \(manifest.version)"}catch{installedManifest=nil;androidRuntimeValid=false;runtimeMessage="运行时校验失败"}
    }
    private func verify(manifest:RuntimeManifest,root:URL) throws {
        guard !manifest.sha256.isEmpty else{throw DroidBoxError.runtimeCorrupted}
        let image=root.appending(path:"system.qcow2");guard let data=try? Data(contentsOf:image,options:.mappedIfSafe) else{throw DroidBoxError.runtimeCorrupted}
        let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined();guard hash==manifest.sha256.lowercased() else{throw DroidBoxError.runtimeCorrupted}
    }
}
