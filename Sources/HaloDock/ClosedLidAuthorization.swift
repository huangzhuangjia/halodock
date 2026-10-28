import AppKit
import ClosedLidSupport

@MainActor
enum ClosedLidAuthorization {
    static func shellLiteral(_ value:String) -> String {"'"+value.replacingOccurrences(of:"'",with:"'\"'\"'")+"'"}
    static func appleScriptLiteral(_ value:String) -> String {"\""+value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\""}
    static func rule(uid: UInt32) -> String {
        "#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1\n"
    }
    static func installationCommand(uid:UInt32,id:UUID) -> String {
        let rule=rule(uid:uid)
        let temporary="/etc/sudoers.d/.halodock-\(id.uuidString)"
        return "set -eu; /bin/mkdir -p /etc/sudoers.d; /usr/bin/printf %s \(shellLiteral(rule)) > \(shellLiteral(temporary)); trap '/bin/rm -f \(temporary)' EXIT; /bin/chmod 0440 \(shellLiteral(temporary)); /usr/sbin/visudo -c -f \(shellLiteral(temporary)); /usr/bin/install -o root -g wheel -m 0440 \(shellLiteral(temporary)) \(ClosedLidCommand.rulePath)"
    }
    static func request(_ command:String,prompt:String) -> Bool {
        NSApp.activate(ignoringOtherApps:true)
        let source="do shell script \(appleScriptLiteral(command)) with administrator privileges with prompt \(appleScriptLiteral(prompt))"
        guard let script=NSAppleScript(source:source) else {return false}
        var error:NSDictionary?
        script.executeAndReturnError(&error)
        return error==nil
    }
}
