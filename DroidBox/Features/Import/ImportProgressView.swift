import SwiftUI

struct ImportProgressView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: environment.importer.progress)
                .frame(width: 90)
            VStack(alignment: .leading, spacing: 2) {
                Text(environment.importer.stage.rawValue)
                    .font(.subheadline.weight(.medium))
                if !environment.importer.currentFileName.isEmpty {
                    Text(environment.importer.currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(progressText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { environment.importer.cancel() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消导入")
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .shadow(radius: 5)
    }

    private var progressText: String {
        let importer = environment.importer
        guard importer.totalFileCount > 1 else {
            return "\(Int(importer.progress * 100))%"
        }
        let current = min(importer.completedFileCount + 1, importer.totalFileCount)
        return "第 \(current)/\(importer.totalFileCount) 个 · \(Int(importer.progress * 100))%"
    }
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
            if !environment.importer.currentFileName.isEmpty {
                Text(environment.importer.currentFileName)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            ProgressView(value: environment.importer.progress)
                .progressViewStyle(.linear)
            Text(progressText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("“+”选择后会直接解析并解压到 Games。扫描 Import 会连续处理全部文件；完成或失败都会显示明确结果。")
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

    private var progressText: String {
        let importer = environment.importer
        guard importer.totalFileCount > 1 else {
            return "\(Int(importer.progress * 100))%"
        }
        let current = min(importer.completedFileCount + 1, importer.totalFileCount)
        return "第 \(current)/\(importer.totalFileCount) 个 · \(Int(importer.progress * 100))%"
    }
}
