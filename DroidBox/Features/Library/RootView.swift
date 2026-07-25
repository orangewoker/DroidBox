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
        .sheet(item:$environment.presentedPlayer){game in PlayerContainerView(game:game)}
        .overlay(alignment:.bottom){if environment.importer.isImporting{ImportProgressView().padding(.bottom,72)}}
        .alert("导入失败",isPresented:Binding(get:{environment.importer.errorMessage != nil},set:{if !$0{}})){Button("好",role:.cancel){}}message:{Text(environment.importer.errorMessage ?? "")}
    }
}

private struct LibraryView:View {
    @Environment(AppEnvironment.self) private var environment
    @State private var search=""
    @State private var grid=true
    @State private var importing=false
    @State private var sortNewest=true
    private var games:[GameRecord]{
        let filtered=environment.library.games.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.packageName?.localizedCaseInsensitiveContains(search) ?? false)}
        return filtered.sorted { sortNewest ? $0.createdAt > $1.createdAt : $0.title.localizedCompare($1.title) == .orderedAscending }
    }
    var body:some View{
        NavigationStack{
            Group{if games.isEmpty{ContentUnavailableView("还没有游戏",systemImage:"shippingbox",description:Text("从“文件”导入 APK 或 ZIP。"))}else if grid{gridContent}else{listContent}}
                .navigationTitle("DroidBox").searchable(text:$search,prompt:"搜索游戏或包名")
                .toolbar{
                    ToolbarItemGroup(placement:.topBarTrailing){
                        Menu{Button(sortNewest ? "按名称排序":"按最近导入排序",systemImage:"arrow.up.arrow.down"){sortNewest.toggle()}}label:{Image(systemName:"arrow.up.arrow.down")}
                        Button{grid.toggle()}label:{Image(systemName:grid ? "list.bullet":"square.grid.2x2")}.accessibilityLabel("切换视图")
                        Button{importing=true}label:{Image(systemName:"plus")}.accessibilityLabel("导入游戏")
                    }
                }
                .fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:"apk") ?? .archive,.zip],allowsMultipleSelection:false){result in if case .success(let urls)=result,let url=urls.first{environment.importer.start(url:url)}}
        }
    }
    private var gridContent:some View{ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:150,maximum:220),spacing:16)],spacing:20){ForEach(games){GameTile(game:$0)}}.padding()}}
    private var listContent:some View{List(games){GameRow(game:$0)}}
}

struct GameArtwork:View{
    let game:GameRecord
    var body:some View{ZStack{Rectangle().fill(Color(uiColor:.secondarySystemBackground));if let path=game.iconPath,let image=UIImage(contentsOfFile:path){Image(uiImage:image).resizable().scaledToFit().padding(16)}else{Image(systemName:icon).font(.system(size:44,weight:.light)).foregroundStyle(.tint)}}.aspectRatio(4/3,contentMode:.fit).clipShape(.rect(cornerRadius:6))}
    private var icon:String{switch game.engine{case .rpgMakerMV,.rpgMakerMZ:"globe";case .renpy7,.renpy8:"text.book.closed";default:"gamecontroller"}}
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
