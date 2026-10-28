import Foundation
import Testing
import UpdateInstallation
@testable import HaloDock

private func fixtureApp(_ url:URL,version:String,marker:String,id:String="com.halodock.app") throws {
    let fm=FileManager.default
    try fm.createDirectory(at:url.appendingPathComponent("Contents/MacOS"),withIntermediateDirectories:true)
    let info:[String:String]=["CFBundleIdentifier":id,"CFBundleExecutable":"HaloDock","CFBundleShortVersionString":version]
    try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:url.appendingPathComponent("Contents/Info.plist"))
    let exe=url.appendingPathComponent("Contents/MacOS/HaloDock")
    try Data(marker.utf8).write(to:exe)
    try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:exe.path)
}

private func fixturePlan() throws -> InstallationPlan {
    let fm=FileManager.default,id=UUID().uuidString
    let parent=fm.temporaryDirectory.appendingPathComponent("HaloDockInstallTests-\(id)")
    let work=fm.temporaryDirectory.appendingPathComponent("HaloDockUpdate-\(id)")
    try fm.createDirectory(at:parent,withIntermediateDirectories:true)
    try fm.createDirectory(at:work,withIntermediateDirectories:true)
    let plan=InstallationPlan(target:parent.appendingPathComponent("HaloDock.app"),staged:parent.appendingPathComponent(".HaloDock-update-\(id).app"),backup:parent.appendingPathComponent(".HaloDock-backup-\(id).app"),workDirectory:work,statusFile:work.appendingPathComponent("status.json"),oldProcessID:ProcessInfo.processInfo.processIdentifier,version:"0.1.6")
    try fixtureApp(plan.target,version:"0.1.5",marker:"old")
    try fixtureApp(plan.staged,version:"0.1.6",marker:"new")
    return plan
}
private func cleanup(_ plan:InstallationPlan) {
    try? FileManager.default.removeItem(at:plan.target.deletingLastPathComponent())
    try? FileManager.default.removeItem(at:plan.workDirectory)
}
private func marker(_ url:URL) throws -> String {
    try String(contentsOf:url.appendingPathComponent("Contents/MacOS/HaloDock"),encoding:.utf8)
}

@Test func updateTransactionCanSwapAndRollbackWithoutTouchingPreferences() throws {
    let plan=try fixturePlan();defer {cleanup(plan)}
    try InstallerTransaction.swap(plan)
    #expect(try marker(plan.target)=="new")
    #expect(try marker(plan.backup)=="old")
    try InstallerTransaction.rollback(plan)
    #expect(try marker(plan.target)=="old")
}

@Test func invalidInstallerCannotReplaceCurrentApp() throws {
    let plan=try fixturePlan();defer {cleanup(plan)}
    try fixtureApp(plan.staged,version:"0.1.6",marker:"foreign",id:"com.other.application")
    #expect(throws:InstallationError.self) {try InstallerTransaction.swap(plan)}
    #expect(try marker(plan.target)=="old")
    #expect(!FileManager.default.fileExists(atPath:plan.backup.path))
}

@Test func existingBackupStopsBeforeMovingCurrentApp() throws {
    let plan=try fixturePlan();defer {cleanup(plan)}
    try FileManager.default.createDirectory(at:plan.backup,withIntermediateDirectories:true)
    #expect(throws:InstallationError.self) {try InstallerTransaction.swap(plan)}
    #expect(try marker(plan.target)=="old")
}

@Test @MainActor func successfulRelaunchRestoresUpdateResult() throws {
    let name="HaloDock.RelaunchTests.\(UUID().uuidString)"
    let defaults=try #require(UserDefaults(suiteName:name));defer {defaults.removePersistentDomain(forName:name)}
    defaults.set("0.1.6",forKey:"pendingUpdateVersion")
    let manager=UpdateManager(currentVersion:"0.1.6",defaults:defaults)
    #expect(manager.shouldShowUpdateResult)
    #expect(manager.message.contains("已成功更新"))
    #expect(defaults.string(forKey:"pendingUpdateVersion")==nil)
}

@Test func aManuallyUpgradedAppIsNeverDowngraded() throws {
    let plan=try fixturePlan();defer {cleanup(plan)}
    try fixtureApp(plan.target,version:"9.0.0",marker:"manually-upgraded")
    #expect(throws:InstallationError.self) {try InstallerTransaction.swap(plan)}
    #expect(try marker(plan.target)=="manually-upgraded")
}
