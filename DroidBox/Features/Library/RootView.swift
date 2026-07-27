import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection = 0
    var body: some View {
        @Bindable var environment = environment
        TabView(selection:$selection) {
            LibraryView().tabItem{Label("游戏库",systemImage:"square.grid.2x2")}.tag(0)
            RuntimeSettingsView().tabItem{Label("运行时",systemImage:"cpu")}.tag(1)
            DiagnosticsView().tabItem{Label("诊断",systemImage:"stethoscope")}.tag(2)
            SettingsView().tabItem{Label("设置",systemImage:"gearshape")}.tag(3)
        }
        .fullScreenCover(item: $environment.presentedPlayer) { game in
            PlayerContainerView(game: game)
                .environment(environment)
        }
        .safeAreaInset(edge: .bottom) {
            if environment.importer.isImporting {
                ImportProgressView()
                    .environment(environment)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .alert(
            item: Binding(
                get: { environment.importer.notice },
                set: { if $0 == nil { environment.importer.clearNotice() } }
            )
        ) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好")) { environment.importer.clearNotice() }
            )
        }
    }
}

private struct LibraryView:View {
    @Environment(AppEnvironment.self) private var environment
    @State private var search=""
    @State private var grid=true
    @State private var sortNewest=true
    @State private var renamingGame: GameRecord?
    @State private var renameDraft = ""
    private var games:[GameRecord]{
        let filtered=environment.library.games.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.packageName?.localizedCaseInsensitiveContains(search) ?? false)}
        return filtered.sorted { sortNewest ? $0.createdAt > $1.createdAt : $0.title.localizedCompare($1.title) == .orderedAscending }
    }
    var body:some View{
        NavigationStack{
            Group{if games.isEmpty{EmptyLibraryView()}else if grid{gridContent}else{listContent}}
                .navigationTitle("DroidBox").searchable(text:$search,prompt:"搜索游戏或包名")
                .toolbar{
                    ToolbarItemGroup(placement:.topBarTrailing){
                        Menu{
                            Button(sortNewest ? "按名称排序":"按最近导入排序",systemImage:"arrow.up.arrow.down"){sortNewest.toggle()}
                            Divider()
                            Button("打开 DroidBox 文件夹",systemImage:"folder"){environment.openImportDirectoryInFiles()}
                            Button("扫描 Import 目录",systemImage:"arrow.clockwise"){environment.scanImportDirectory()}
                        }label:{Image(systemName:"ellipsis.circle")}
                        Button{grid.toggle()}label:{Image(systemName:grid ? "list.bullet":"square.grid.2x2")}.accessibilityLabel("切换视图")
                        Button{DroidBoxFrontendHost.shared.presentGameImporter()}label:{Image(systemName:"plus")}.accessibilityLabel("导入游戏")
                    }
                }
                .alert(
                    "修改游戏名称",
                    isPresented: Binding(
                        get: { renamingGame != nil },
                        set: { if !$0 { renamingGame = nil } }
                    )
                ) {
                    TextField("游戏名称", text: $renameDraft)
                    Button("取消", role: .cancel) { renamingGame = nil }
                    Button("保存") { saveRename() }
                } message: {
                    Text("输入新的游戏库显示名称，不会修改游戏文件。")
                }
        }
    }
    private var gridContent:some View{
        ScrollView{
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150,maximum:220),spacing:16)],spacing:20){
                ForEach(games){ game in
                    GameTile(game: game)
                        .contextMenu { renameButton(for: game) }
                }
            }
            .padding()
        }
    }
    private var listContent:some View{
        List(games){ game in
            GameRow(game: game)
                .contextMenu { renameButton(for: game) }
        }
    }

    private func renameButton(for game: GameRecord) -> some View {
        Button("修改名称", systemImage: "pencil") {
            renameDraft = game.title
            renamingGame = game
        }
    }

    private func saveRename() {
        guard var game = renamingGame else { return }
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingGame = nil
        guard !title.isEmpty, title != game.title else { return }
        game.title = String(title.prefix(100))
        do {
            try environment.library.update(game)
        } catch {
            environment.importer.reportNotice(
                title: "修改名称失败",
                message: error.localizedDescription
            )
        }
    }
}

private struct EmptyLibraryView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ContentUnavailableView {
            Label("还没有游戏", systemImage: "shippingbox")
        } description: {
            Text("可以直接选择 APK/ZIP/JAR，也可以把文件放入 DroidBox/Import 后扫描。")
        } actions: {
            VStack(spacing: 10) {
                Button("选择 APK、ZIP 或 JAR", systemImage: "doc.badge.plus") {
                    DroidBoxFrontendHost.shared.presentGameImporter()
                }
                .buttonStyle(.borderedProminent)
                Button("打开 DroidBox 文件夹", systemImage: "folder") {
                    environment.openImportDirectoryInFiles()
                }
                Button("扫描 Import 目录", systemImage: "arrow.clockwise") {
                    environment.scanImportDirectory()
                }
            }
        }
    }
}

struct GameArtwork:View{
    let game:GameRecord
    var body:some View{ZStack{Rectangle().fill(Color(uiColor:.secondarySystemBackground));if let path=game.iconPath,let image=UIImage(contentsOfFile:path){Image(uiImage:image).resizable().scaledToFit().padding(16)}else{Image(systemName:icon).font(.system(size:44,weight:.light)).foregroundStyle(.tint)}}.aspectRatio(4/3,contentMode:.fit).clipShape(.rect(cornerRadius:6))}
    private var icon:String{switch game.engine{case .rpgMakerMV,.rpgMakerMZ:"globe";case .renpy7,.renpy8:"text.book.closed";case .j2me:"cup.and.heat.waves";default:"gamecontroller"}}
}
private struct GameTile:View{
    let game:GameRecord
    var body:some View{NavigationLink{GameDetailView(game:game)}label:{VStack(alignment:.leading,spacing:8){GameArtwork(game:game);Text(game.title).font(.headline).lineLimit(2);HStack{Label(game.engine.displayName,systemImage:"cpu").font(.caption);Spacer();CompatibilityBadge(level:game.compatibility.level)}}.contentShape(Rectangle())}.buttonStyle(.plain)}
}
private struct GameRow:View{
    let game:GameRecord
    var body:some View{NavigationLink{GameDetailView(game:game)}label:{HStack{GameArtwork(game:game).frame(width:92);VStack(alignment:.leading){Text(game.title).font(.headline);Text(game.engine.displayName).foregroundStyle(.secondary);CompatibilityBadge(level:game.compatibility.level)};Spacer()}}}
}
private struct CompatibilityBadge:View{let level:CompatibilityLevel;var body:some View{Image(systemName:level == .unsupported ? "exclamationmark.octagon.fill":level == .experimental ? "flask.fill":"checkmark.circle.fill").foregroundStyle(level == .unsupported ? .red:level == .experimental ? .orange:.green).accessibilityLabel(label)};var label:String{switch level{case .excellent:"极佳";case .good:"良好";case .experimental:"实验";case .unsupported:"不支持"}}}
