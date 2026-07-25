import SwiftUI

struct PlayerContainerView:View{
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var controls=true
    @State private var vm:AndroidVMController?
    let game:GameRecord
    var body:some View{ZStack{
        Color.black.ignoresSafeArea()
        switch game.runtimeMode{
        case .web:RPGMakerPlayerView(game:game).ignoresSafeArea()
        case .renpy:UnavailableRuntimeView(title:"Ren'Py Runtime 尚未安装",detail:"请在运行时页面导入与此游戏匹配的 Ren'Py Runtime。")
        case .androidVM:if let vm{VMPlayerStatusView(controller:vm,game:game)}else{ProgressView().tint(.white)}
        default:UnavailableRuntimeView(title:"无法启动",detail:game.compatibility.summary)
        }
        if controls{VStack{HStack{Button{dismiss()}label:{Image(systemName:"xmark")} .accessibilityLabel("返回游戏库");Spacer();Button{controls=false}label:{Image(systemName:"eye.slash")}.accessibilityLabel("隐藏控制栏")}.font(.title3).foregroundStyle(.white).padding(12).background(.black.opacity(0.55));Spacer()}}
    }.statusBarHidden().onAppear{if game.runtimeMode == .androidVM{let controller=AndroidVMController(runtimeManager:environment.runtimeManager);vm=controller;controller.launch(game)}}.onTapGesture{if !controls{controls=true}}}
}
private struct UnavailableRuntimeView:View{let title:String;let detail:String;var body:some View{ContentUnavailableView{Label(title,systemImage:"externaldrive.badge.exclamationmark")}description:{Text(detail)}.foregroundStyle(.white)}}
private struct VMPlayerStatusView:View{let controller:AndroidVMController;let game:GameRecord;var body:some View{VStack(spacing:18){ProgressView().tint(.white);Text(controller.state.title).font(.headline);Text(controller.detail).foregroundStyle(.secondary).multilineTextAlignment(.center);if controller.state == .failed{Button("返回",role:.cancel){controller.reset()}}}.foregroundStyle(.white).padding(32)}}

