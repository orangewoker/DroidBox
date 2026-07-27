import Combine
import Foundation
import SwiftUI

enum ModifierValueType: String, CaseIterable, Identifiable, Sendable {
    case int8 = "i8"
    case int16 = "i16"
    case int32 = "i32"
    case float32 = "f32"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .int8: "8 位整数"
        case .int16: "16 位整数"
        case .int32: "32 位整数"
        case .float32: "浮点数"
        }
    }
    var byteWidth: Int {
        switch self {
        case .int8: 1
        case .int16: 2
        case .int32, .float32: 4
        }
    }
}

enum ModifierFilter: String, Sendable {
    case exact
    case changed
    case unchanged
    case increased
    case decreased
}

struct ModifierCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let type: ModifierValueType
    let address: Int?
    let source: String?
    let offset: Int?
    let endian: String?
    var value: Double
    var isFrozen: Bool

    var location: String {
        if let address {
            return String(format: "0x%08X", address)
        }
        let name = source?.split(separator: "/").last.map(String.init) ?? "RMS"
        let byteOffset = offset.map { String(format: "0x%X", $0) } ?? "-"
        return "\(name) + \(byteOffset) \(endian ?? "")"
    }

    var formattedValue: String {
        if type == .float32 {
            return String(format: "%.5g", value)
        }
        return String(Int64(value))
    }
}

struct ModifierScanPage: Sendable {
    var total: Int
    var truncated: Bool
    var results: [ModifierCandidate]
}

enum DataModifierError: LocalizedError {
    case runtimeUnavailable
    case invalidResponse
    case saveMissing
    case candidateMissing

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: "修改器尚未连接到运行中的游戏。"
        case .invalidResponse: "模拟器返回了无法识别的扫描结果。"
        case .saveMissing: "当前游戏还没有可修改的存档。"
        case .candidateMissing: "存档中的目标位置已经发生变化，请重新搜索。"
        }
    }
}

struct DataModifierView: View {
    let controller: J2MEPlayerController
    @State private var valueType = ModifierValueType.int32
    @State private var searchText = ""
    @State private var page = ModifierScanPage(total: 0, truncated: false, results: [])
    @State private var hasMemoryScan = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var editingCandidate: ModifierCandidate?

    private let refreshTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)
                Text("数据修改器")
                    .font(.headline)
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                Button {
                    controller.isModifierPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭数据修改器")
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Picker("类型", selection: $valueType) {
                        ForEach(ModifierValueType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 118)

                    TextField("输入当前数值", text: $searchText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)

                    Button(action: firstScan) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || numericSearchValue == nil)
                }

                HStack {
                    if hasMemoryScan {
                        Menu {
                            Button("等于输入值") { refine(.exact) }
                            Button("数值增加了") { refine(.increased) }
                            Button("数值减少了") { refine(.decreased) }
                            Button("数值发生变化") { refine(.changed) }
                            Button("数值没有变化") { refine(.unchanged) }
                        } label: {
                            Label("继续排查", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: resetScan) {
                        Label("重新搜索", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }

                HStack {
                    Text(resultSummary)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !page.results.isEmpty {
                        Button("刷新", action: refreshMemory)
                            .font(.footnote.weight(.semibold))
                    }
                }

                if page.results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text(hasMemoryScan ? "没有匹配结果" : "输入角色属性的当前数值")
                            .font(.subheadline.weight(.semibold))
                        Text("首次搜索后改变游戏里的数值，再点“继续排查”。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(page.results) { candidate in
                        Button {
                            editingCandidate = candidate
                        } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .padding(14)
        .foregroundStyle(.primary)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .onChange(of: valueType) { _ in resetScan() }
        .onReceive(refreshTimer) { _ in
            if hasMemoryScan, !isBusy { refreshMemory() }
        }
        .sheet(item: $editingCandidate) { candidate in
            ModifierValueEditor(
                candidate: candidate,
                editsLiveMemory: true,
                apply: applyEdit
            )
            .presentationDetents([.height(310)])
        }
        .alert("修改器错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: ModifierCandidate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: candidate.isFrozen ? "pin.fill" : "memorychip")
                .foregroundStyle(candidate.isFrozen ? .orange : .indigo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.formattedValue)
                    .font(.headline.monospacedDigit())
                Text(candidate.location)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var numericSearchValue: Double? {
        Double(searchText.replacingOccurrences(of: ",", with: "."))
    }

    private var resultSummary: String {
        if page.total == 0 { return "0 个结果" }
        let suffix = page.truncated ? "（结果过多，已限制扫描范围）" : ""
        return "找到 \(page.total) 个，显示前 \(page.results.count) 个\(suffix)"
    }

    private func firstScan() {
        guard let value = numericSearchValue else { return }
        isBusy = true
        Task {
            do {
                page = try await controller.modifierFirstScan(type: valueType, value: value)
                hasMemoryScan = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func refine(_ filter: ModifierFilter) {
        isBusy = true
        Task {
            do {
                page = try await controller.modifierRefine(
                    filter: filter,
                    value: numericSearchValue ?? 0
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func refreshMemory() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            do { page = try await controller.modifierRefresh() }
            catch { errorMessage = error.localizedDescription }
            isBusy = false
        }
    }

    private func resetScan() {
        page = ModifierScanPage(total: 0, truncated: false, results: [])
        hasMemoryScan = false
        Task { try? await controller.modifierReset() }
    }

    private func applyEdit(_ candidate: ModifierCandidate, _ value: Double, _ freeze: Bool) {
        editingCandidate = nil
        isBusy = true
        Task {
            do {
                page = try await controller.modifierWrite(
                    candidate: candidate,
                    value: value,
                    freeze: freeze
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}

private struct ModifierValueEditor: View {
    let candidate: ModifierCandidate
    let editsLiveMemory: Bool
    let apply: (ModifierCandidate, Double, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var valueText: String
    @State private var freeze: Bool

    init(
        candidate: ModifierCandidate,
        editsLiveMemory: Bool,
        apply: @escaping (ModifierCandidate, Double, Bool) -> Void
    ) {
        self.candidate = candidate
        self.editsLiveMemory = editsLiveMemory
        self.apply = apply
        _valueText = State(initialValue: candidate.formattedValue)
        _freeze = State(initialValue: candidate.isFrozen)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标位置") {
                    Text(candidate.location).font(.footnote.monospaced())
                }
                Section("新数值") {
                    TextField("数值", text: $valueText)
                        .keyboardType(.numbersAndPunctuation)
                    if editsLiveMemory {
                        Toggle("锁定数值", isOn: $freeze)
                    }
                }
                Button(editsLiveMemory ? "立即写入" : "写入存档并加载") {
                    guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")) else { return }
                    apply(candidate, value, freeze)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("修改数值")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
