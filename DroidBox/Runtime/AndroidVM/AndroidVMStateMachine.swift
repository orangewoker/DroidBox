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
    let runtimeManager:RuntimeManager
    init(runtimeManager:RuntimeManager){self.runtimeManager=runtimeManager}
    func launch(_ game:GameRecord){
        launchTask?.cancel();error=nil
        launchTask=Task{do{
            try await transition(.preparingRuntime,timeout:.seconds(3)){guard self.runtimeManager.androidRuntimeValid else{throw DroidBoxError.runtimeMissing}}
            try await transition(.checkingJIT,timeout:.seconds(3)){if self.runtimeManager.jitStatus == .unknown{self.runtimeManager.probeJIT()}}
            try await transition(.creatingOverlay,timeout:.seconds(20)){try await self.runtimeManager.prepareOverlay(gameID:game.id)}
            try await transition(.startingVM,timeout:.seconds(15)){throw DroidBoxError.unsupported("当前构建未包含 QEMU 可执行核心。请安装带 UTM/QEMU Core 的完整运行时版本。")}
        }catch is CancellationError{state = .idle;detail="已取消"}catch{self.error=error.localizedDescription;state = .failed;detail=error.localizedDescription}}
    }
    func cancel(){launchTask?.cancel()}
    func reset(){state = .idle;detail="";error=nil}
    private func transition(_ next:VMState,timeout:Duration,operation:@escaping @MainActor() async throws -> Void) async throws {
        try Task.checkCancellation();state=next;detail=next.title
        try await withThrowingTaskGroup(of:Void.self){group in
            group.addTask{@MainActor in try await operation()};group.addTask{try await Task.sleep(for:timeout);throw DroidBoxError.vmBootTimeout}
            _=try await group.next();group.cancelAll()
        }
    }
}
