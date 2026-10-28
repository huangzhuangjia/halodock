import AppKit
import UpdateInstallation

@main struct HaloDockUpdater {
    @MainActor static func main() async {
        guard CommandLine.arguments.count==2,
              let data=try? Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),
              let plan=try? JSONDecoder().decode(InstallationPlan.self,from:data) else {return}
        do {
            try InstallerTransaction.validatePaths(plan)
            try InstallerTransaction.validateBundle(plan.staged,version:plan.version)
            try InstallerTransaction.verifySignature(plan.staged)
            try InstallerTransaction.validateBundle(plan.target)
            try InstallerTransaction.preventDowngrade(plan.target,to:plan.version)
            guard !FileManager.default.fileExists(atPath:plan.backup.path),plan.oldProcessID != ProcessInfo.processInfo.processIdentifier else {throw InstallationError.invalid("更新备份状态异常，当前版本保持不变")}
            InstallerTransaction.writeStatus(plan,state:"ready",message:"更新器已准备好")
            let deadline=Date().addingTimeInterval(60)
            while kill(plan.oldProcessID,0)==0 && Date()<deadline {try? await Task.sleep(for:.milliseconds(100))}
            guard kill(plan.oldProcessID,0) != 0 else {throw InstallationError.invalid("旧版未退出，已保留原应用")}
            try InstallerTransaction.swap(plan)
            InstallerTransaction.writeStatus(plan,state:"installed",message:"已更新至 \(plan.version)")
            if await launch(plan.target) {
                try? FileManager.default.removeItem(at:plan.backup)
                try? FileManager.default.removeItem(at:plan.workDirectory)
            } else {
                try InstallerTransaction.rollback(plan)
                InstallerTransaction.writeStatus(plan,state:"failed",message:"新版未能启动，已恢复旧版")
                _=await launch(plan.target)
            }
        } catch {
            FileHandle.standardError.write(Data("Updater error: \(error.localizedDescription)\n".utf8))
            InstallerTransaction.writeStatus(plan,state:"failed",message:error.localizedDescription)
            if FileManager.default.fileExists(atPath:plan.backup.path) {try? InstallerTransaction.rollback(plan)}
            if kill(plan.oldProcessID,0) != 0 {_=await launch(plan.target)}
        }
    }
    @MainActor private static func launch(_ app:URL) async -> Bool {
        let configuration=NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance=true
        configuration.activates=true
        do {
            let running=try await NSWorkspace.shared.openApplication(at:app,configuration:configuration)
            let deadline=Date().addingTimeInterval(30)
            while Date()<deadline {
                if running.isTerminated {return false}
                if running.isFinishedLaunching {return true}
                try? await Task.sleep(for:.milliseconds(100))
            }
            running.terminate()
            let stop=Date().addingTimeInterval(3)
            while !running.isTerminated && Date()<stop {try? await Task.sleep(for:.milliseconds(100))}
            if !running.isTerminated {running.forceTerminate()}
            return false
        } catch {return false}
    }
}
