import SwiftUI
struct ImportProgressView:View{
    @Environment(AppEnvironment.self) private var environment
    var body:some View{HStack(spacing:12){ProgressView(value:environment.importer.progress).frame(width:90);VStack(alignment:.leading){Text(environment.importer.stage.rawValue).font(.subheadline.weight(.medium));Text("\(Int(environment.importer.progress*100))%").font(.caption).foregroundStyle(.secondary)};Button{environment.importer.cancel()}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).accessibilityLabel("取消导入")}.padding(12).background(.regularMaterial,in:.rect(cornerRadius:8)).shadow(radius:5)}
}

