import Foundation
import IOKit.ps

public struct ClosedLidSession:Codable,Sendable {
    public let id:UUID
    public let ownerPID:Int32
    public let ownerStarted:Date
    public let bootEpoch:TimeInterval
    public let previousDisabled:Bool
    public let deadlineUptime:TimeInterval?
    public let endsAt:Date?
    public init(id:UUID,ownerPID:Int32,ownerStarted:Date,bootEpoch:TimeInterval,previousDisabled:Bool,deadlineUptime:TimeInterval?,endsAt:Date?) {
        self.id=id;self.ownerPID=ownerPID;self.ownerStarted=ownerStarted;self.bootEpoch=bootEpoch;self.previousDisabled=previousDisabled;self.deadlineUptime=deadlineUptime;self.endsAt=endsAt
    }
}
public struct ClosedLidResult:Codable,Sendable {
    public let phase:String
    public let reason:String
    public init(phase:String,reason:String) {self.phase=phase;self.reason=reason}
}
public enum ClosedLidPolicy {
    public static func parseDisabled(_ text:String) -> Bool? {
        for line in text.split(separator:"\n") {
            let tokens=line.split(whereSeparator:{$0.isWhitespace})
            if tokens.first=="SleepDisabled",tokens.count>=2 {
                if tokens[1]=="0" {return false}
                if tokens[1]=="1" {return true}
                return nil
            }
        }
        // pmset omits an unset global override; its default is normal sleep.
        return text.contains("System-wide power settings:") ? false:nil
    }
    public static func restoreValue(previous:Bool,current:Bool) -> Bool? {
        // Never re-enable an override another application has already cleared.
        current && !previous ? false:nil
    }
    public static func stopReason(ownerAlive:Bool,sameBoot:Bool,uptime:TimeInterval,deadline:TimeInterval?,onBattery:Bool,batteryPercent:Int?,thermal:ProcessInfo.ThermalState,stopRequested:Bool) -> String? {
        if stopRequested {return "已手动关闭合盖模式"}
        if !sameBoot || !ownerAlive {return "应用已退出，恢复原有睡眠设置"}
        if let deadline,uptime>=deadline {return "合盖会话已到期"}
        if onBattery,let batteryPercent,batteryPercent<=20 {return "电量不足 20%，恢复睡眠"}
        if thermal == .serious || thermal == .critical {return "系统温度较高，恢复睡眠"}
        return nil
    }
}
public enum ClosedLidPaths {
    public static var directory:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HaloDock/ClosedLid",isDirectory:true)
    }
    public static var session:URL {directory.appendingPathComponent("session.json")}
    public static func stop(_ id:UUID) -> URL {directory.appendingPathComponent("\(id.uuidString).stop")}
    public static func armed(_ id:UUID) -> URL {directory.appendingPathComponent("\(id.uuidString).armed")}
    public static func result(_ id:UUID) -> URL {directory.appendingPathComponent("\(id.uuidString).status.json")}
    public static func writeResult(_ id:UUID,phase:String,reason:String) {
        try? JSONEncoder().encode(ClosedLidResult(phase:phase,reason:reason)).write(to:result(id),options:.atomic)
    }
}
public enum ClosedLidCommand {
    public static let rulePath="/etc/sudoers.d/halodock-clamshell"
    public static func readDisabled() -> Bool? {
        guard let result=try? run("/usr/bin/pmset",["-g"]),result.status==0 else {return nil}
        return ClosedLidPolicy.parseDisabled(result.output)
    }
    public static func setDisabled(_ disabled:Bool) -> Bool {
        guard let result=try? run("/usr/bin/sudo",["-n","/usr/bin/pmset","disablesleep",disabled ? "1":"0"]),result.status==0 else {return false}
        return readDisabled()==disabled
    }
    public static func restore(_ session:ClosedLidSession) -> Bool {
        guard let current=readDisabled() else {return false}
        guard let value=ClosedLidPolicy.restoreValue(previous:session.previousDisabled,current:current) else {return true}
        return setDisabled(value)
    }
    public static func battery() -> (onBattery:Bool,percent:Int?) {
        guard let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources=IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {return (false,nil)}
        for source in sources {
            guard let data=IOPSGetPowerSourceDescription(info,source)?.takeUnretainedValue() as? [String:Any],
                  data[kIOPSTypeKey] as? String==kIOPSInternalBatteryType,
                  let current=data[kIOPSCurrentCapacityKey] as? Int,let maximum=data[kIOPSMaxCapacityKey] as? Int,maximum>0 else {continue}
            return (data[kIOPSPowerSourceStateKey] as? String==kIOPSBatteryPowerValue,Int(Double(current)*100/Double(maximum)))
        }
        return (false,nil)
    }
    public static func run(_ path:String,_ arguments:[String],timeout:TimeInterval=5) throws -> (status:Int32,output:String) {
        let process=Process(),pipe=Pipe(),finished=DispatchSemaphore(value:0)
        process.executableURL=URL(fileURLWithPath:path);process.arguments=arguments
        process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        process.terminationHandler={_ in finished.signal()}
        try process.run()
        if finished.wait(timeout:.now()+timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout:.now()+1) == .timedOut {kill(process.processIdentifier,SIGKILL);process.waitUntilExit()}
            return (-1,"")
        }
        return (process.terminationStatus,String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self))
    }
}
