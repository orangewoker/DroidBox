import Foundation

struct RuntimeCapability: Sendable { let available: Bool; let reason: String? }
struct RuntimeProgress: Sendable { let fraction: Double; let message: String }
struct RuntimeSession: Identifiable, Sendable { let id: UUID; let gameID: UUID; let startedAt: Date }
struct DiagnosticBundle: Sendable { let values: [String:String]; let logURLs: [URL] }

protocol GameRuntime: Sendable {
    var identifier:String{get}
    func canRun(_ game:GameRecord) async -> RuntimeCapability
    func prepare(_ game:GameRecord,progress:@escaping @Sendable(RuntimeProgress)->Void) async throws
    func launch(_ game:GameRecord) async throws -> RuntimeSession
    func suspend(_ session:RuntimeSession) async throws
    func stop(_ session:RuntimeSession) async
    func collectDiagnostics(_ session:RuntimeSession?) async -> DiagnosticBundle
}

