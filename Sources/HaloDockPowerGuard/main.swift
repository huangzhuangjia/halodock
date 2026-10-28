import AppKit
import ClosedLidSupport

@main struct HaloDockPowerGuard {
    @MainActor static func main() async {
        guard let data=try? Data(contentsOf:ClosedLidPaths.session),let session=try? JSONDecoder().decode(ClosedLidSession.self,from:data) else {return}
        ClosedLidPaths.writeResult(session.id,phase:"ready",reason:"合盖保护已就绪")
        let armDeadline=Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath:ClosedLidPaths.armed(session.id).path) && Date()<armDeadline && kill(session.ownerPID,0)==0 && !FileManager.default.fileExists(atPath:ClosedLidPaths.stop(session.id).path) {
            try? await Task.sleep(for:.milliseconds(100))
        }
        if !FileManager.default.fileExists(atPath:ClosedLidPaths.armed(session.id).path) {
            let ok=ClosedLidCommand.restore(session)
            ClosedLidPaths.writeResult(session.id,phase:ok ? "restored":"restorePending",reason:ok ? "开启未完成，已恢复睡眠":"请授权恢复睡眠")
            return
        }
        var reason=""
        while true {
            let owner=NSRunningApplication(processIdentifier:session.ownerPID)
            let alive=owner?.bundleIdentifier=="com.halodock.app" && owner?.launchDate.map({abs($0.timeIntervalSince(session.ownerStarted))<2})==true
            let uptime=ProcessInfo.processInfo.systemUptime
            let sameBoot=abs(Date().timeIntervalSince1970-uptime-session.bootEpoch)<30
            let battery=ClosedLidCommand.battery()
            if let stop=ClosedLidPolicy.stopReason(ownerAlive:alive,sameBoot:sameBoot,uptime:uptime,deadline:session.deadlineUptime,onBattery:battery.onBattery,batteryPercent:battery.percent,thermal:ProcessInfo.processInfo.thermalState,stopRequested:FileManager.default.fileExists(atPath:ClosedLidPaths.stop(session.id).path)) {reason=stop;break}
            if ClosedLidCommand.readDisabled()==false {reason="系统已恢复睡眠";break}
            try? await Task.sleep(for:.seconds(1))
        }
        for _ in 0..<10 {
            if ClosedLidCommand.restore(session) {
                ClosedLidPaths.writeResult(session.id,phase:"restored",reason:reason)
                return
            }
            try? await Task.sleep(for:.seconds(2))
        }
        ClosedLidPaths.writeResult(session.id,phase:"restorePending",reason:"恢复睡眠失败，请在 HaloDock 中重新授权恢复")
    }
}
