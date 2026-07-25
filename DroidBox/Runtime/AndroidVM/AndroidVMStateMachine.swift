import Foundation
import Observation

enum VMState: String, CaseIterable, Sendable {
    case idle,preparingRuntime,checkingJIT,creatingOverlay,startingVM,waitingForADB,installingAPK,resolvingActivity,launchingActivity,running,suspending,stopping,failed
    var title:String { switch self {case .idle:"待机";case .preparingRuntime:"准备运行时";case .checkingJIT:"检查 JIT";case .creatingOverlay:"创建游戏磁盘";case .startingVM:"启动 Android";case .waitingForADB:"等待 Android 服务";case .installingAPK:"安装 APK";case .resolvingActivity:"查找启动入口";case .launchingActivity:"启动游戏";case .running:"运行中";case .suspending:"暂停中";case .stopping:"正在停止";case .failed:"启动失败"} }
}

@MainActor @Observable
final class AndroidVMController {
    private(set) var state:VMState = .idle
    private(set) var detail=""
    private(set) var error:String?
    private var launchTask:Task<Void,Never>?
    private let qmp = QMPClient()
    private let adb = ADBClient()
    private let bridge = DBQEMUBridge()
    private var qmpPort: UInt16 = 0
    private var adbPort: UInt16 = 0
    private(set) var vncDisplay = 0
    let runtimeManager:RuntimeManager
    init(runtimeManager:RuntimeManager){self.runtimeManager=runtimeManager}
    func launch(_ game:GameRecord){
        launchTask?.cancel();error=nil
        launchTask=Task{do{
            try await transition(.preparingRuntime,timeout:.seconds(3)){guard self.runtimeManager.androidRuntimeValid else{throw DroidBoxError.runtimeMissing}}
            try await transition(.checkingJIT,timeout:.seconds(3)){if self.runtimeManager.jitStatus == .unknown{self.runtimeManager.probeJIT()}}
            try await transition(.creatingOverlay,timeout:.seconds(20)){try await self.runtimeManager.prepareOverlay(gameID:game.id)}
            try await transition(.startingVM,timeout:.seconds(15)){try self.startQEMU(game)}
            try await transition(.waitingForADB,timeout:.seconds(120)){try await self.connectServices()}
            if let package = game.packageName {
                try await transition(.installingAPK,timeout:.seconds(180)){try await self.adb.install(apkURL:URL(fileURLWithPath:game.originalFilePath))}
                var activity = ""
                try await transition(.resolvingActivity,timeout:.seconds(20)){activity=try await self.adb.resolveLauncherActivity(packageName:package)}
                try await transition(.launchingActivity,timeout:.seconds(20)){try await self.adb.launch(packageName:package,activity:activity)}
                self.state = .running;self.detail="游戏运行中"
            } else { throw DroidBoxError.activityNotFound }
        }catch is CancellationError{state = .idle;detail="已取消"}catch{self.error=error.localizedDescription;state = .failed;detail=error.localizedDescription}}
    }
    func cancel(){launchTask?.cancel();Task{try? await qmp.quit();await adb.disconnect()}}
    func suspend() { Task { try? await qmp.pause(); state = .suspending; detail = "虚拟机已暂停" } }
    func resume() { Task { try? await qmp.resume(); state = .running; detail = "游戏运行中" } }
    func stop() { Task { state = .stopping; try? await qmp.quit(); await adb.disconnect(); state = .idle; detail = "" } }
    func reset(){state = .idle;detail="";error=nil}
    private func transition(
        _ next: VMState,
        timeout: Duration,
        operation: @escaping @Sendable @MainActor () async throws -> Void
    ) async throws {
        try Task.checkCancellation();state=next;detail=next.title
        try await performWithTimeout(timeout, operation: operation)
    }
    private func startQEMU(_ game: GameRecord) throws {
        guard DBQEMUBridge.coreBundled else { throw DroidBoxError.unsupported("当前 IPA 未包含 QEMU Core。请使用 Full Runtime 构建。") }
        qmpPort = UInt16.random(in: 21000...30000); adbPort = UInt16.random(in: 30001...40000); vncDisplay = Int.random(in: 10...90)
        let arguments = try runtimeManager.qemuArguments(gameID:game.id,qmpPort:qmpPort,adbPort:adbPort,vncDisplay:vncDisplay)
        try bridge.start(withArguments:arguments,environment:["TMPDIR":runtimeManager.paths.temporary.path],exitHandler:{[weak self] code,message in
            guard let self, code != 0 else{return}
            Task { @MainActor in self.error=message ?? "QEMU exited with code \(code)";self.state = .failed;self.detail=self.error ?? "QEMU 已退出" }
        })
    }
    private func connectServices() async throws {
        var lastError: Error = DroidBoxError.adbUnavailable
        for _ in 0..<60 {
            try Task.checkCancellation()
            do { try await qmp.connect(port:qmpPort);try await adb.connect(port:adbPort);return }
            catch { lastError=error;try await Task.sleep(for:.seconds(2)) }
        }
        throw lastError
    }
}

private func performWithTimeout(
    _ timeout: Duration,
    operation: @escaping @Sendable @MainActor () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw DroidBoxError.vmBootTimeout
        }
        _ = try await group.next()
        group.cancelAll()
    }
}
