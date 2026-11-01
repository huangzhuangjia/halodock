import AppKit
import Testing
import ClosedLidSupport
@testable import HaloDock

@Test func readsOnlyTheGlobalSleepOverride() {
    #expect(ClosedLidPolicy.parseDisabled("System-wide power settings:\n SleepDisabled\t1\n sleep 0")==true)
    #expect(ClosedLidPolicy.parseDisabled("System-wide power settings:\n SleepDisabled 0\n sleep 1")==false)
    #expect(ClosedLidPolicy.parseDisabled("System-wide power settings:\nCurrently in use:\n sleep 0")==false)
    #expect(ClosedLidPolicy.parseDisabled("permission denied")==nil)
    #expect(ClosedLidPolicy.parseDisabled("SleepDisabled unknown")==nil)
}

@Test func restoringDoesNotReenableAnotherAppsClearedOverride() {
    #expect(ClosedLidPolicy.restoreValue(previous:false,current:true)==false)
    #expect(ClosedLidPolicy.restoreValue(previous:true,current:true)==nil)
    #expect(ClosedLidPolicy.restoreValue(previous:true,current:false)==nil)
    #expect(ClosedLidPolicy.restoreValue(previous:false,current:false)==nil)
}

@Test func lidSessionStopsForOwnerExpiryPowerAndThermals() {
    func reason(alive:Bool=true,boot:Bool=true,uptime:Double=10,deadline:Double?=100,battery:Bool=false,percent:Int?=80,thermal:ProcessInfo.ThermalState = .nominal,stop:Bool=false) -> String? {
        ClosedLidPolicy.stopReason(ownerAlive:alive,sameBoot:boot,uptime:uptime,deadline:deadline,onBattery:battery,batteryPercent:percent,thermal:thermal,stopRequested:stop)
    }
    #expect(reason()==nil)
    #expect(reason(alive:false) != nil)
    #expect(reason(boot:false) != nil)
    #expect(reason(uptime:100) != nil)
    #expect(reason(uptime:1_000_000,deadline:nil)==nil)
    #expect(reason(battery:true,percent:20) != nil)
    #expect(reason(battery:false,percent:10)==nil)
    #expect(reason(thermal:.serious) != nil)
    #expect(reason(thermal:.critical) != nil)
    #expect(reason(stop:true) != nil)
}

@Test func lidBootIdentitySurvivesSleepAndWallClockChanges() {
    let bootID=UUID().uuidString
    let initialWall=1_800_000_000.0,initialUptime=10_000.0
    let oldBootEpoch=initialWall-initialUptime
    for clockChange in [-3600.0,0,3600] {
        let resumedWall=initialWall+600+clockChange
        let resumedUptime=initialUptime+10
        // Reproduce the previous false reboot after 590 seconds asleep.
        #expect(abs(resumedWall-resumedUptime-oldBootEpoch)>30)
        let sameBoot=ClosedLidPolicy.isSameBoot(storedID:bootID,currentID:bootID)
        #expect(ClosedLidPolicy.stopReason(ownerAlive:true,sameBoot:sameBoot,uptime:resumedUptime,deadline:nil,onBattery:false,batteryPercent:100,thermal:.nominal,stopRequested:false)==nil)
    }
    #expect(!ClosedLidPolicy.isSameBoot(storedID:bootID,currentID:UUID().uuidString))
    #expect(ClosedLidPolicy.stopReason(ownerAlive:true,sameBoot:false,uptime:10,deadline:nil,onBattery:false,batteryPercent:100,thermal:.nominal,stopRequested:false)=="系统已重启，结束旧合盖会话")
}

@Test func legacyLidSessionsStillRequireTheirOriginalOwner() throws {
    let legacy="""
    {"id":"5138C34A-F45E-4FC9-8163-6D1CFB6C7E28","ownerPID":42,"ownerStarted":0,"bootEpoch":1,"previousDisabled":false}
    """
    let session=try JSONDecoder().decode(ClosedLidSession.self,from:Data(legacy.utf8))
    #expect(session.bootSessionID==nil)
    #expect(ClosedLidPolicy.isSameBoot(storedID:session.bootSessionID,currentID:UUID().uuidString))
    #expect(ClosedLidPolicy.stopReason(ownerAlive:false,sameBoot:true,uptime:10,deadline:nil,onBattery:false,batteryPercent:100,thermal:.nominal,stopRequested:false) != nil)
    // An unavailable boot identifier never pretends the original owner exited.
    #expect(ClosedLidPolicy.isSameBoot(storedID:UUID().uuidString,currentID:nil))
    let id=try #require(ClosedLidPolicy.readBootSessionID())
    #expect(UUID(uuidString:id) != nil)
    #expect(ClosedLidPolicy.readBootSessionID()==id)
    let next=ClosedLidSession(id:session.id,ownerPID:42,ownerStarted:session.ownerStarted,bootEpoch:1,previousDisabled:false,deadlineUptime:nil,endsAt:nil,bootSessionID:id)
    #expect(try JSONDecoder().decode(ClosedLidSession.self,from:JSONEncoder().encode(next)).bootSessionID==id)
}

@Test @MainActor func adminScriptCompilesAndLimitsAuthorization() throws {
    let rule=ClosedLidAuthorization.rule(uid:501)
    #expect(rule.hasPrefix("#501 ALL=(root) NOPASSWD:"))
    #expect(rule.components(separatedBy:"/usr/bin/pmset").count==3)
    #expect(!rule.contains("*"))
    #expect(!rule.contains("/bin/sh"))
    let command=ClosedLidAuthorization.installationCommand(uid:501,id:UUID())
    #expect(command.contains("visudo -c -f"))
    #expect(command.contains("-m 0440"))
    let source="do shell script \(ClosedLidAuthorization.appleScriptLiteral(command)) with administrator privileges"
    let script=try #require(NSAppleScript(source:source))
    var error:NSDictionary?
    #expect(script.compileAndReturnError(&error))
    // Syntax validation only: neither the script nor any privileged command is executed.
}
