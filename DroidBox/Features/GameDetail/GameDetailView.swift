import SwiftUI

struct GameDetailView:View{
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmDelete=false
    let game:GameRecord
    var body:some View{List{
        Section{HStack(alignment:.top,spacing:16){GameArtwork(game:game).frame(width:130);VStack(alignment:.leading,spacing:6){Text(game.title).font(.title2.bold());Text(game.packageName ?? "无 Android 包名").font(.caption).textSelection(.enabled);Text(game.compatibility.summary).foregroundStyle(.secondary)}}}
        Section{Button{environment.presentedPlayer=game}label:{Label(game.lastPlayedAt == nil ? "启动":"继续",systemImage:"play.fill")}.disabled(game.runtimeMode == .unavailable)}
        Section("运行信息"){LabeledContent("引擎",value:game.engine.displayName);LabeledContent("运行模式",value:game.runtimeMode.rawValue);LabeledContent("版本",value:game.versionName ?? "未知");LabeledContent("ABI",value:game.abiList.map(\.rawValue).joined(separator:", "))}
        Section("兼容性"){if game.compatibility.issues.isEmpty{Label("未发现明显兼容问题",systemImage:"checkmark.circle").foregroundStyle(.green)}else{ForEach(game.compatibility.issues){issue in VStack(alignment:.leading){Text(issue.title).font(.headline);Text(issue.detail).foregroundStyle(.secondary)}}}}
        Section{Button("删除游戏",systemImage:"trash",role:.destructive){confirmDelete=true}}
    }.navigationTitle("游戏详情").navigationBarTitleDisplayMode(.inline).confirmationDialog("删除游戏及其数据？",isPresented:$confirmDelete,titleVisibility:.visible){Button("删除",role:.destructive){try? environment.library.remove(game)}}}
}

