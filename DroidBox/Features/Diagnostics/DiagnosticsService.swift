import Foundation
import UIKit

@MainActor
final class DiagnosticsService {
    let runtimeManager:RuntimeManager
    init(runtimeManager:RuntimeManager){self.runtimeManager=runtimeManager}
    var rows:[(String,String)] {
        let device=UIDevice.current
        let runtime = DBQEMUBridge.coreBundled
            ? runtimeManager.runtimeMessage
            : "不可用（QEMU Core 未嵌入）"
        return [("iOS",device.systemVersion),("设备",device.model),("App 版本",Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"),("JIT",jitText),("物理内存",ByteCountFormatter.string(fromByteCount:Int64(DBRuntimeProbe.physicalMemory()),countStyle:.memory)),("估算可用内存",ByteCountFormatter.string(fromByteCount:Int64(DBRuntimeProbe.availableMemoryEstimate()),countStyle:.memory)),("Android Runtime",runtime),("QEMU Core",DBQEMUBridge.coreBundled ? "已嵌入":"未嵌入")]
    }
    var jitText:String{switch runtimeManager.jitStatus{case .available:"可用（MAP_JIT 实测）";case .unavailable:"不可用";case .unknown:"未知"}}
}
