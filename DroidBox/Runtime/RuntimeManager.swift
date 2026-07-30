import Foundation
import CryptoKit
import Observation

struct RuntimeManifest:Codable,Sendable { let id:String;let version:String;let architecture:String;let downloadURL:String;let sha256:String;let size:UInt64;let license:String;let minimumAppVersion:String;let qemuArguments:[String]? }

@MainActor @Observable
final class RuntimeManager {
    static let defaultRuntimeURL = URL(
        string: "https://github.com/orangewoker/DroidBox/releases/download/android-runtime-v1/DroidBox-Android-x86_64-9.0-r2-droidbox.1-runtime.zip"
    )!

    private(set) var jitStatus:JITStatus = .unknown
    private(set) var jitMethod = "尚未检测"
    private(set) var androidRuntimeValid=false
    private(set) var runtimeMessage="尚未导入 Android Runtime"
    private(set) var isInstallingRuntime = false
    private(set) var installMessage = ""
    let paths:AppPaths
    private var installedManifest: RuntimeManifest?
    var qemuLogURL: URL { paths.android.appending(path: "qemu-last.log") }
    private var vmSessionMarkerURL: URL { paths.android.appending(path: "vm-session-active") }
    init(paths:AppPaths){self.paths=paths;probeJIT();verifyInstalledRuntime()}
    func probeJIT(){
        switch DBRuntimeProbe.jitMode() {
        case 1:
            jitStatus = .available
            jitMethod = "可用（MAP_JIT）"
        case 2:
            jitStatus = .available
            jitMethod = "可用（StikDebug/调试器）"
        default:
            jitStatus = .unavailable
            jitMethod = "不可用"
        }
    }
    func importRuntime(_ url:URL) async throws {
        guard !isInstallingRuntime else {
            throw DroidBoxError.unsupported("已有 Android Runtime 安装任务正在运行。")
        }
        isInstallingRuntime = true
        installMessage = "正在校验并解压 Runtime…"
        defer {
            isInstallingRuntime = false
            installMessage = ""
        }
        let root = runtimeRoot
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try await Task.detached(priority: .userInitiated) {
            let archive=try SafeArchive(url:url,maxExpandedBytes:32*1024*1024*1024,maxRatio:20)
            guard archive.entries.contains(where:{$0.path=="runtime.json"}) else{throw DroidBoxError.runtimeCorrupted}
            let manifest=try JSONDecoder().decode(RuntimeManifest.self,from:archive.data(path:"runtime.json",maximum:1024*1024))
            guard manifest.architecture=="x86_64" else {
                throw DroidBoxError.unsupported("当前 QEMU Core 需要 x86_64 Android Runtime。")
            }
            let temporary = root.deletingLastPathComponent().appending(path: "base.installing")
            try? FileManager.default.removeItem(at: temporary)
            try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
            do {
                try archive.extract(prefix:"",to:temporary,maximumPerFile:20*1024*1024*1024)
                try Self.verify(manifest:manifest,root:temporary)
                try? FileManager.default.removeItem(at:root)
                try FileManager.default.moveItem(at:temporary,to:root)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }.value
        verifyInstalledRuntime()
    }

    func installDefaultRuntime() async throws {
        guard !isInstallingRuntime else {
            throw DroidBoxError.unsupported("已有 Android Runtime 安装任务正在运行。")
        }
        isInstallingRuntime = true
        installMessage = "正在下载 Android Runtime（约 1 GB）…"
        defer {
            isInstallingRuntime = false
            installMessage = ""
        }
        let (downloaded, response) = try await URLSession.shared.download(from: Self.defaultRuntimeURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DroidBoxError.unsupported("Android Runtime 下载失败。")
        }
        isInstallingRuntime = false
        try await importRuntime(downloaded)
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
        let qemuResources = DBQEMUBridge.runtimeBundleURL.appending(path: "qemu").path
        let replacements = ["{runtime}": runtimeRoot.path, "{overlay}": overlay.path, "{base}": baseImageURL.path, "{qemu}": qemuResources, "{qmpPort}": String(qmpPort), "{adbPort}": String(adbPort), "{vncDisplay}": String(vncDisplay), "{memoryMB}": String(memoryMB)]
        if let custom = manifest.qemuArguments, !custom.isEmpty {
            var arguments = custom.map { argument in replacements.reduce(argument) { $0.replacingOccurrences(of: $1.key, with: $1.value) } }
            // Existing Runtime ZIPs used a 512 MB TCG translation cache. Together with
            // guest RAM this can cross the iOS Jetsam limit before QEMU shows a frame.
            if let accelIndex = arguments.firstIndex(of: "-accel"), arguments.indices.contains(accelIndex + 1) {
                var accel = arguments[accelIndex + 1]
                if accel.contains("tb-size=") {
                    accel = accel.replacingOccurrences(of: "tb-size=\\d+", with: "tb-size=128", options: .regularExpression)
                } else if accel.hasPrefix("tcg") {
                    accel += ",tb-size=128"
                }
                arguments[accelIndex + 1] = accel
            }
            arguments += ["-D", qemuLogURL.path, "-d", "guest_errors"]
            return arguments
        }
        throw DroidBoxError.runtimeCorrupted
    }

    func beginVMSession(gameID: UUID) throws {
        try? FileManager.default.removeItem(at: qemuLogURL)
        try gameID.uuidString.write(to: vmSessionMarkerURL, atomically: true, encoding: .utf8)
    }

    func endVMSession() {
        try? FileManager.default.removeItem(at: vmSessionMarkerURL)
    }

    func consumeInterruptedSessionNotice() -> String? {
        guard FileManager.default.fileExists(atPath: vmSessionMarkerURL.path) else { return nil }
        try? FileManager.default.removeItem(at: vmSessionMarkerURL)
        return "上次 Android VM 被系统异常中断，通常是内存超限或 QEMU 崩溃。本版已将默认内存降为 1024 MB。QEMU 日志位于：\n\(qemuLogURL.path)"
    }
    var runtimeRoot: URL { paths.android.appending(path:"base") }
    var baseImageURL: URL { runtimeRoot.appending(path:"system.qcow2") }
    private func verifyInstalledRuntime(){
        let file=paths.android.appending(path:"base/runtime.json")
        guard let data=try? Data(contentsOf:file),let manifest=try? JSONDecoder().decode(RuntimeManifest.self,from:data) else{androidRuntimeValid=false;installedManifest=nil;return}
        do{try Self.verify(manifest:manifest,root:file.deletingLastPathComponent());installedManifest=manifest;androidRuntimeValid=true;runtimeMessage="\(manifest.id) \(manifest.version)"}catch{installedManifest=nil;androidRuntimeValid=false;runtimeMessage="运行时校验失败"}
    }
    nonisolated private static func verify(manifest:RuntimeManifest,root:URL) throws {
        guard !manifest.sha256.isEmpty else{throw DroidBoxError.runtimeCorrupted}
        guard manifest.architecture == "x86_64",
              FileManager.default.fileExists(atPath: root.appending(path: "kernel").path),
              FileManager.default.fileExists(atPath: root.appending(path: "initrd.img").path)
        else { throw DroidBoxError.runtimeCorrupted }
        let image=root.appending(path:"system.qcow2");guard let data=try? Data(contentsOf:image,options:.mappedIfSafe) else{throw DroidBoxError.runtimeCorrupted}
        let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined();guard hash==manifest.sha256.lowercased() else{throw DroidBoxError.runtimeCorrupted}
    }
}
