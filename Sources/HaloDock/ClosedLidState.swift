import AppKit
import Combine
import ClosedLidSupport

@MainActor
final class ClosedLidState:ObservableObject {
    static let shared=ClosedLidState()
    @Published private(set) var active=false
    @Published private(set) var isChanging=false
    @Published private(set) var authorizationInstalled=FileManager.default.fileExists(atPath:ClosedLidCommand.rulePath)
    @Published private(set) var message="合盖模式只用于本次会话，首次需要管理员授权。"
    @Published private(set) var endsAt:Date?
    @Published private(set) var needsRestore=false
    private var session:ClosedLidSession?
    private var helper:Process?
    private var monitor:Task<Void,Never>?
    private init() {}

    func configure() {
        guard monitor==nil else {return}
        monitor=Task { [weak self] in
            if let data=try? Data(contentsOf:ClosedLidPaths.session),let saved=try? JSONDecoder().decode(ClosedLidSession.self,from:data) {
                self?.session=saved
                self?.active=true
                if self?.ownerIsAlive(saved)==true {
                    self?.endsAt=saved.endsAt
                    self?.message="合盖会话正在运行"
                } else {await self?.stop()}
            }
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(2))
                guard let self else {return}
                self.authorizationInstalled=FileManager.default.fileExists(atPath:ClosedLidCommand.rulePath)
                if !self.isChanging {await self.refreshSession()}
            }
        }
    }
    private func refreshSession() async {
        guard let session else {return}
        if let data=try? Data(contentsOf:ClosedLidPaths.result(session.id)),let result=try? JSONDecoder().decode(ClosedLidResult.self,from:data) {
            if result.phase=="restored" {finish(reason:result.reason);return}
            if result.phase=="restorePending" {needsRestore=true;message=result.reason;return}
        }
        if !ownerIsAlive(session) || (helper != nil && helper?.isRunning != true) {await stop()}
    }
    func enable(minutes:Int) async {
        guard !isChanging,!active,[0,30,60,120].contains(minutes) else {return}
        if let data=try? Data(contentsOf:ClosedLidPaths.session),let current=try? JSONDecoder().decode(ClosedLidSession.self,from:data),ownerIsAlive(current) {
            message="已有 HaloDock 合盖会话正在运行，请先关闭该会话";return
        }
        let binary=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HaloDockPowerGuard")
        guard FileManager.default.isExecutableFile(atPath:binary.path),let started=NSRunningApplication.current.launchDate else {message="请从完整安装的 HaloDock.app 使用合盖模式";return}
        let alert=NSAlert()
        alert.messageText="开启合盖保持运行？"
        let duration=minutes==0 ? "直到手动关闭或退出 App":"最多 \(minutes) 分钟"
        alert.informativeText="本次将阻止系统睡眠，合盖后继续运行，\(duration)。电池低于 20% 或系统温度过高时会恢复睡眠。\n\n首次授权只允许当前用户执行两条电源命令。合盖运行时请保持通风。"
        alert.addButton(withTitle:authorizationInstalled ? "开启":"授权并开启");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else {return}
        isChanging=true
        defer {isChanging=false}
        if !authorizationInstalled {
            guard ClosedLidAuthorization.request(ClosedLidAuthorization.installationCommand(uid:getuid(),id:UUID()),prompt:"允许 HaloDock 配置合盖保持运行；仅授权开启、关闭系统睡眠两条命令。") else {message="已取消授权，未开启合盖模式";return}
            authorizationInstalled=true
        }
        guard let previous=await Task.detached(operation:{ClosedLidCommand.readDisabled()}).value else {message="无法读取当前系统睡眠状态，未修改设置";return}
        let battery=ClosedLidCommand.battery()
        guard !(battery.onBattery && (battery.percent ?? 100)<=20),ProcessInfo.processInfo.thermalState != .critical,ProcessInfo.processInfo.thermalState != .serious else {message="当前电量或温度不适合开启合盖模式";return}
        let uptime=ProcessInfo.processInfo.systemUptime
        let next=ClosedLidSession(id:UUID(),ownerPID:ProcessInfo.processInfo.processIdentifier,ownerStarted:started,bootEpoch:Date().timeIntervalSince1970-uptime,previousDisabled:previous,deadlineUptime:minutes>0 ? uptime+Double(minutes*60):nil,endsAt:minutes>0 ? Date().addingTimeInterval(Double(minutes*60)):nil)
        do {
            try FileManager.default.createDirectory(at:ClosedLidPaths.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(next).write(to:ClosedLidPaths.session,options:.atomic)
            session=next
            let process=Process();process.executableURL=binary
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            helper=process;try process.run()
            var ready=false
            for _ in 0..<50 {
                if let data=try? Data(contentsOf:ClosedLidPaths.result(next.id)),let result=try? JSONDecoder().decode(ClosedLidResult.self,from:data),result.phase=="ready" {ready=true;break}
                if !process.isRunning {break}
                try await Task.sleep(for:.milliseconds(100))
            }
            guard ready else {throw LidFailure("保护进程未能就绪，未开启合盖模式")}
            var changed=previous
            if !previous {changed=await Task.detached {ClosedLidCommand.setDisabled(true)}.value}
            guard changed else {throw LidFailure("合盖授权未生效，请在设置中重新授权")}
            try Data().write(to:ClosedLidPaths.armed(next.id))
            active=true;needsRestore=false;endsAt=next.endsAt
            message=minutes==0 ? "合盖保持运行中 · 直到关闭或退出":"合盖保持运行中 · \(minutes) 分钟"
        } catch {
            message=error.localizedDescription
            if let session {
                try? Data().write(to:ClosedLidPaths.stop(session.id))
                let restored=await Task.detached {ClosedLidCommand.restore(session)}.value
                if restored {finish(reason:message)} else {active=true;needsRestore=true;message="开启未完成，请点击授权恢复睡眠"}
            }
        }
    }
    @discardableResult func stop() async -> Bool {
        guard !isChanging else {return false}
        guard let session else {return true}
        isChanging=true;defer {isChanging=false}
        try? Data().write(to:ClosedLidPaths.stop(session.id))
        if helper?.isRunning==true {
            for _ in 0..<40 {
                if let data=try? Data(contentsOf:ClosedLidPaths.result(session.id)),let result=try? JSONDecoder().decode(ClosedLidResult.self,from:data),result.phase=="restored" {finish(reason:result.reason);return true}
                if helper?.isRunning != true {break}
                try? await Task.sleep(for:.milliseconds(100))
            }
        }
        if await Task.detached(operation:{ClosedLidCommand.restore(session)}).value {finish(reason:"合盖模式已关闭，已恢复原有设置");return true}
        active=true;needsRestore=true;message="恢复睡眠需要重新授权，请点击“授权恢复睡眠”"
        return false
    }
    @discardableResult func restoreWithAuthorization() -> Bool {
        guard !isChanging else {return false}
        guard let session else {return true}
        isChanging=true;defer {isChanging=false}
        if let current=ClosedLidCommand.readDisabled(),ClosedLidPolicy.restoreValue(previous:session.previousDisabled,current:current)==nil {
            finish(reason:"系统已恢复原有睡眠状态");return true
        }
        let command="/usr/bin/pmset disablesleep \(session.previousDisabled ? "1":"0")"
        guard ClosedLidAuthorization.request(command,prompt:"允许 HaloDock 恢复启用合盖模式前的系统睡眠设置。") else {message="未恢复睡眠，请重试授权";return false}
        guard ClosedLidCommand.readDisabled()==session.previousDisabled else {message="系统设置尚未恢复，请重试";return false}
        try? Data().write(to:ClosedLidPaths.stop(session.id))
        finish(reason:"已授权恢复原有睡眠设置")
        return true
    }
    func authorize() {
        guard !isChanging,!active else {return}
        isChanging=true;defer {isChanging=false}
        if ClosedLidAuthorization.request(ClosedLidAuthorization.installationCommand(uid:getuid(),id:UUID()),prompt:"允许 HaloDock 配置合盖电源控制，仅授权两条 pmset 命令。") {
            authorizationInstalled=true;message="合盖授权已配置，可以开启本次会话"
        } else {message="已取消授权，未修改睡眠设置"}
    }
    func removeAuthorization() async {
        guard await stop() else {return}
        if ClosedLidAuthorization.request("/bin/rm -f \(ClosedLidCommand.rulePath)",prompt:"移除 HaloDock 的合盖电源命令授权。") {authorizationInstalled=false;message="已移除 HaloDock 合盖授权"}
    }
    private func ownerIsAlive(_ session:ClosedLidSession) -> Bool {
        let owner=NSRunningApplication(processIdentifier:session.ownerPID)
        let sameBoot=abs(Date().timeIntervalSince1970-ProcessInfo.processInfo.systemUptime-session.bootEpoch)<30
        return sameBoot && owner?.bundleIdentifier=="com.halodock.app" && owner?.launchDate.map({abs($0.timeIntervalSince(session.ownerStarted))<2})==true
    }
    private func finish(reason:String) {
        if let session {
            if let data=try? Data(contentsOf:ClosedLidPaths.session),let current=try? JSONDecoder().decode(ClosedLidSession.self,from:data),current.id==session.id {try? FileManager.default.removeItem(at:ClosedLidPaths.session)}
            try? FileManager.default.removeItem(at:ClosedLidPaths.armed(session.id))
        }
        session=nil;active=false;needsRestore=false;endsAt=nil;message=reason
    }
}
private struct LidFailure:LocalizedError {
    let errorDescription:String?
    init(_ text:String) {errorDescription=text}
}
