import SwiftUI

struct GameDetailView:View{
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmDelete=false
    let game:GameRecord
    var body:some View{List{
        Section{HStack(alignment:.top,spacing:16){GameArtwork(game:game).frame(width:130);VStack(alignment:.leading,spacing:6){Text(game.title).font(.title2.bold());Text(game.packageName ?? "无 Android 包名").font(.caption).textSelection(.enabled);Text(game.compatibility.summary).foregroundStyle(.secondary)}}}
        Section{Button{environment.presentedPlayer=game}label:{Label(game.lastPlayedAt == nil ? "启动":"继续",systemImage:"play.fill")}.disabled(game.runtimeMode == .unavailable)}
        if game.engine == .kirikiri {
            Section("KiriKiri 配套引擎") {
                if let engineURL = Bundle.main.url(
                    forResource: "Kirikiroid2-1.3.9",
                    withExtension: "ipa",
                    subdirectory: "EmbeddedRuntimes"
                ) {
                    ShareLink(item: engineURL) {
                        Label("导出内置 Kirikiroid2 1.3.9 IPA", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label("此构建没有附带 KiriKiri 引擎包", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if !game.originalFilePath.isEmpty,
                   FileManager.default.fileExists(atPath: game.originalFilePath) {
                    ShareLink(item: URL(fileURLWithPath: game.originalFilePath)) {
                        Label("发送游戏 ZIP 到 KiriKiri 引擎", systemImage: "arrow.up.doc")
                    }
                }
                Text("iOS 不能从一个普通签名 App 内启动另一个 App 的可执行文件。内置的是可导出、可重签的官方配套引擎 IPA；安装后再把游戏 ZIP 发送给它。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        Section("运行信息"){LabeledContent("引擎",value:game.engine.displayName);LabeledContent("运行模式",value:game.runtimeMode.rawValue);LabeledContent("版本",value:game.versionName ?? "未知");LabeledContent("ABI",value:game.abiList.map(\.rawValue).joined(separator:", "))}
        Section("兼容性"){if game.compatibility.issues.isEmpty{Label("未发现明显兼容问题",systemImage:"checkmark.circle").foregroundStyle(.green)}else{ForEach(game.compatibility.issues){issue in VStack(alignment:.leading){Text(issue.title).font(.headline);Text(issue.detail).foregroundStyle(.secondary)}}}}
        Section{Button("删除游戏",systemImage:"trash",role:.destructive){confirmDelete=true}}
    }.navigationTitle("游戏详情").navigationBarTitleDisplayMode(.inline).confirmationDialog("删除游戏及其数据?",isPresented:$confirmDelete,titleVisibility:.visible){Button("删除",role:.destructive){try? environment.library.remove(game)}}}
}
