import SwiftUI
struct ImportProgressView:View{
    @Environment(AppEnvironment.self) private var environment
    var body:some View{HStack(spacing:12){ProgressView(value:environment.importer.progress).frame(width:90);VStack(alignment:.leading){Text(environment.importer.stage.rawValue).font(.subheadline.weight(.medium));Text("\(Int(environment.importer.progress*100))%").font(.caption).foregroundStyle(.secondary)};Button{environment.importer.cancel()}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).accessibilityLabel("取消导入")}.padding(12).background(.regularMaterial,in:.rect(cornerRadius:8)).shadow(radius:5)}
}

struct ImportProgressSheet: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("正在导入")
                .font(.title.bold())
            Text(environment.importer.stage.rawValue)
                .font(.headline)
            ProgressView(value: environment.importer.progress)
                .progressViewStyle(.linear)
            Text("\(Int(environment.importer.progress * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("大型 APK 需要读取并解压数万个文件，请保持 DroidBox 在前台。完成或失败后都会显示明确结果。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("取消导入", role: .destructive) {
                environment.importer.cancel()
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}
