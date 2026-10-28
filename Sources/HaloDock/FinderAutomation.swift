import AppKit
import Carbon

@MainActor
enum FinderAutomation {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    static func permissionStatus(requestIfNeeded: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        return AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, requestIfNeeded
        )
    }

    static func isPermissionError(_ code: Int) -> Bool {
        code == Int(errAEEventNotPermitted) || code == Int(errAEEventWouldRequireUserConsent)
    }

    static func showFailure(code: Int, detail: String?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if isPermissionError(code) {
            alert.messageText = "需要允许控制 Finder"
            alert.informativeText = "请前往“系统设置 → 隐私与安全性 → 自动化”，展开 HaloDock 并开启 Finder。返回 HaloDock 后重新点击清空；本次没有执行删除。"
            alert.addButton(withTitle: "前往设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(settingsURL)
            }
        } else {
            alert.messageText = "清空未完成"
            alert.informativeText = "Finder 未能完成清空（错误 \(code)）。废纸篓里可能存在正在使用、锁定或受保护的项目。请打开废纸篓，在 Finder 中查看具体提示。\(detail.map { "\n\n系统信息：\($0)" } ?? "")"
            alert.addButton(withTitle: "打开废纸篓")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
            }
        }
    }
}
