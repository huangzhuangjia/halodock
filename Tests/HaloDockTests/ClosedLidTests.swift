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
