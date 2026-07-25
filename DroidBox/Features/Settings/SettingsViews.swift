import SwiftUI
import UniformTypeIdentifiers

struct RuntimeSettingsView:View{
    @Environment(AppEnvironment.self) private var environment
    @State private var importing=false
    @State private var error:String?
    var body:some View{NavigationStack{List{
        Section("Android Runtime"){LabeledContent("状态",value:environment.runtimeManager.runtimeMessage);Button("导入 Runtime ZIP",systemImage:"square.and.arrow.down"){importing=true}}
        Section("JIT"){LabeledContent("状态",value:environment.diagnostics.jitText);Button("重新检测",systemImage:"arrow.clockwise"){environment.runtimeManager.probeJIT()};if environment.runtimeManager.jitStatus != .available{Text("Android VM 可尝试无 JIT 模式，但速度会非常慢。快速运行路径不受影响。").font(.footnote).foregroundStyle(.secondary)}}
        Section("核心组件"){LabeledContent("UTM/QEMU",value:"未嵌入");Text("Runtime 数据与 QEMU 核心分开管理。当前源码保留了固定版本的构建入口，完整核心需由 macOS CI 构建。 ").font(.footnote).foregroundStyle(.secondary)}
    }.navigationTitle("运行时").fileImporter(isPresented:$importing,allowedContentTypes:[.zip],allowsMultipleSelection:false){result in if case .success(let urls)=result,let url=urls.first{Task{do{try await environment.runtimeManager.importRuntime(url)}catch{self.error=error.localizedDescription}}}}.alert("导入失败",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("好",role:.cancel){}}message:{Text(error ?? "")}}}
}
struct DiagnosticsView:View{
    @Environment(AppEnvironment.self) private var environment
    var body:some View{NavigationStack{List{Section("设备与环境"){ForEach(Array(environment.diagnostics.rows.enumerated()),id:\.offset){_,row in LabeledContent(row.0,value:row.1)}}Section("隐私"){Text("DroidBox 不会自动上传诊断数据。日志仅在设备本地保存。")}}.navigationTitle("诊断")}}
}
struct SettingsView:View{
    @Environment(AppEnvironment.self) private var environment
    var body:some View{NavigationStack{Form{Section("导入限制"){LabeledContent("单文件上限",value:"8 GB");LabeledContent("最大膨胀倍数",value:"20 倍")}Section("运行策略"){Toggle("自动选择运行时",isOn:.constant(true));Picker("VM 内存",selection:.constant(1536)){Text("1024 MB").tag(1024);Text("1536 MB").tag(1536);Text("2048 MB").tag(2048)}}Section("关于"){LabeledContent("应用",value:"DroidBox");LabeledContent("兼容范围",value:"iOS 18–27")}}.navigationTitle("设置")}}
}

