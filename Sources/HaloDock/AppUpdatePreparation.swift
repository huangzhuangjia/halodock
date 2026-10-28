import Foundation
import UpdateInstallation

struct PreparedAppUpdate: Sendable {
    let plan:InstallationPlan
    let manifest:URL
    let helper:URL
}

enum AppUpdatePreparation {
    static func prepare(dmg:URL,version:String,target:URL,helper:URL) async throws -> PreparedAppUpdate {
        try await Task.detached {
            let fm=FileManager.default,parent=target.deletingLastPathComponent()
            guard fm.isWritableFile(atPath:parent.path),fm.isExecutableFile(atPath:helper.path) else {
                throw InstallationError.invalid("请将 HaloDock 安装到有写入权限的“应用程序”目录，再使用 App 内更新")
            }
            try InstallerTransaction.validateBundle(target)
            try InstallerTransaction.preventDowngrade(target,to:version)
            let identifier=UUID().uuidString
            let work=fm.temporaryDirectory.appendingPathComponent("HaloDockUpdate-\(identifier)")
            let mount=work.appendingPathComponent("mounted")
            let staged=parent.appendingPathComponent(".HaloDock-update-\(identifier).app")
            let backup=parent.appendingPathComponent(".HaloDock-backup-\(identifier).app")
            var mounted=false,prepared=false
            try fm.createDirectory(at:mount,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            defer {
                if mounted {try? command("/usr/bin/hdiutil",["detach",mount.path])}
                if !prepared {try? fm.removeItem(at:staged);try? fm.removeItem(at:work)}
            }
            try command("/usr/bin/hdiutil",["attach","-readonly","-nobrowse","-mountpoint",mount.path,dmg.path])
            mounted=true
            let source=mount.appendingPathComponent("HaloDock.app")
            try InstallerTransaction.validateBundle(source,version:version)
            try InstallerTransaction.verifySignature(source)
            try fm.copyItem(at:source,to:staged)
            try InstallerTransaction.validateBundle(staged,version:version)
            try InstallerTransaction.verifySignature(staged)
            let plan=InstallationPlan(target:target,staged:staged,backup:backup,workDirectory:work,statusFile:work.appendingPathComponent("status.json"),oldProcessID:ProcessInfo.processInfo.processIdentifier,version:version)
            try InstallerTransaction.validatePaths(plan)
            let manifest=work.appendingPathComponent("plan.json")
            try JSONEncoder().encode(plan).write(to:manifest,options:.atomic)
            try command("/usr/bin/hdiutil",["detach",mount.path])
            mounted=false
            prepared=true
            return PreparedAppUpdate(plan:plan,manifest:manifest,helper:helper)
        }.value
    }
    private static func command(_ executable:String,_ arguments:[String]) throws {
        let process=Process();process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        try process.run();process.waitUntilExit()
        guard process.terminationStatus==0 else {throw InstallationError.invalid("无法准备更新安装包，请稍后重试")}
    }
}

