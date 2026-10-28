import Foundation

public struct InstallationPlan: Codable, Sendable {
    public let target: URL
    public let staged: URL
    public let backup: URL
    public let workDirectory: URL
    public let statusFile: URL
    public let oldProcessID: Int32
    public let version: String
    public init(target:URL,staged:URL,backup:URL,workDirectory:URL,statusFile:URL,oldProcessID:Int32,version:String) {
        self.target=target;self.staged=staged;self.backup=backup;self.workDirectory=workDirectory;self.statusFile=statusFile;self.oldProcessID=oldProcessID;self.version=version
    }
}

public struct InstallationStatus: Codable, Sendable {
    public let state: String
    public let message: String
    public init(state:String,message:String) {self.state=state;self.message=message}
}

public enum InstallationError: LocalizedError {
    case invalid(String)
    public var errorDescription:String? {switch self {case .invalid(let text):return text}}
}

public enum InstallerTransaction {
    public static func validatePaths(_ plan:InstallationPlan) throws {
        let urls=[plan.target,plan.staged,plan.backup,plan.workDirectory,plan.statusFile]
        guard urls.allSatisfy(\.isFileURL),plan.oldProcessID>1,
              plan.target.pathExtension=="app",plan.staged.pathExtension=="app",plan.backup.pathExtension=="app",
              plan.staged.lastPathComponent.hasPrefix(".HaloDock-update-"),plan.backup.lastPathComponent.hasPrefix(".HaloDock-backup-"),
              plan.staged != plan.target,plan.backup != plan.target,
              plan.staged.deletingLastPathComponent().resolvingSymlinksInPath().path==plan.target.deletingLastPathComponent().resolvingSymlinksInPath().path,
              plan.backup.deletingLastPathComponent().resolvingSymlinksInPath().path==plan.target.deletingLastPathComponent().resolvingSymlinksInPath().path,
              plan.statusFile.deletingLastPathComponent().resolvingSymlinksInPath().path==plan.workDirectory.resolvingSymlinksInPath().path,
              plan.workDirectory.lastPathComponent.hasPrefix("HaloDockUpdate-"),
              plan.workDirectory.deletingLastPathComponent().resolvingSymlinksInPath().path==FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path,
              plan.statusFile.lastPathComponent=="status.json" else {throw InstallationError.invalid("更新路径无效，已停止安装")}
        for url in [plan.target,plan.staged,plan.backup] {
            if (try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true {throw InstallationError.invalid("无法通过符号链接替换应用")}
        }
    }
    public static func validateBundle(_ url:URL,version:String? = nil) throws {
        let file=url.appendingPathComponent("Contents/Info.plist")
        guard let data=try? Data(contentsOf:file),
              let info=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
              info["CFBundleIdentifier"] as? String=="com.halodock.app",
              info["CFBundleExecutable"] as? String=="HaloDock",
              FileManager.default.isExecutableFile(atPath:url.appendingPathComponent("Contents/MacOS/HaloDock").path) else {throw InstallationError.invalid("安装包不是有效的 HaloDock 应用")}
        if let version,info["CFBundleShortVersionString"] as? String != version {throw InstallationError.invalid("安装包版本与发布版本不一致")}
    }
    public static func preventDowngrade(_ app:URL,to version:String) throws {
        let data=try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
        guard let info=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
              let installed=info["CFBundleShortVersionString"] as? String,
              installed.compare(version,options:.numeric) != .orderedDescending else {throw InstallationError.invalid("当前磁盘上的应用版本更新，已停止降级安装")}
    }
    public static func verifySignature(_ url:URL) throws {
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/codesign")
        process.arguments=["--verify","--deep","--strict",url.path]
        process.standardError=FileHandle.nullDevice
        try process.run();process.waitUntilExit()
        guard process.terminationStatus==0 else {throw InstallationError.invalid("应用签名完整性检查失败")}
    }
    public static func swap(_ plan:InstallationPlan) throws {
        try validatePaths(plan);try validateBundle(plan.target);try validateBundle(plan.staged,version:plan.version)
        try preventDowngrade(plan.target,to:plan.version)
        let fm=FileManager.default
        guard !fm.fileExists(atPath:plan.backup.path) else {throw InstallationError.invalid("更新备份路径已存在")}
        try fm.moveItem(at:plan.target,to:plan.backup)
        do {try fm.moveItem(at:plan.staged,to:plan.target)}
        catch {
            if !fm.fileExists(atPath:plan.target.path) {try fm.moveItem(at:plan.backup,to:plan.target)}
            throw error
        }
    }
    public static func rollback(_ plan:InstallationPlan) throws {
        try validatePaths(plan)
        try validateBundle(plan.backup)
        let fm=FileManager.default
        if fm.fileExists(atPath:plan.target.path) {
            try validateBundle(plan.target,version:plan.version)
            try fm.removeItem(at:plan.target)
        }
        try fm.moveItem(at:plan.backup,to:plan.target)
    }
    public static func writeStatus(_ plan:InstallationPlan,state:String,message:String) {
        try? JSONEncoder().encode(InstallationStatus(state:state,message:message)).write(to:plan.statusFile,options:.atomic)
    }
}
