import Foundation
enum ABIAnalyzer {
    static func analyze(paths: [String]) -> [AndroidABI] {
        let lower=paths.map{$0.lowercased()}; var result:[AndroidABI]=[]
        if lower.contains(where:{$0.hasPrefix("lib/arm64-v8a/")}){result.append(.arm64)}
        if lower.contains(where:{$0.hasPrefix("lib/armeabi-v7a/")}){result.append(.armv7)}
        if lower.contains(where:{$0.hasPrefix("lib/x86/")}){result.append(.x86)}
        if lower.contains(where:{$0.hasPrefix("lib/x86_64/")}){result.append(.x86_64)}
        if result.isEmpty { result.append(lower.contains(where:{$0.hasPrefix("lib/")}) ? .unknown : .javaOnly) }
        return result
    }
}

