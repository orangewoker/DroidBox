import Foundation
import UIKit

@MainActor
final class DiagnosticsService {
    let runtimeManager:RuntimeManager
    init(runtimeManager:RuntimeManager){self.runtimeManager=runtimeManager}
    var rows:[(String,String)] {
        let device=UIDevice.current
        return [("iOS",device.systemVersion),("设备",device.model),("App 版本",Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"),("JIT",jitText),("物理内存",ByteCountFormatter.string(fromByteCount:Int64(DBRuntimeProbe.physicalMemory()),countStyle:.memory)),("估算可用内存",ByteCountFormatter.string(fromByteCount:Int64(DBRuntimeProbe.availableMemoryEstimate()),countStyle:.memory)),("Android Runtime",runtimeManager.runtimeMessage),("QEMU Core",DBQEMUBridge.coreBundled ? "已嵌入":"未嵌入")]
    }
    var jitText:String{switch runtimeManager.jitStatus{case .available:"已启用";case .unavailable:"未启用";case .unknown:"未知"}}
}
