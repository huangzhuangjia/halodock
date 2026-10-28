import AppKit

@main struct PreviewUpdateAlert {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出验证", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
        app.finishLaunching()
        let name = "HaloDock.UpdatePromptPreview.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let notes = String(repeating: "## 很长的版本说明\n- 更新内容可在这里滚动阅读。\n- 按钮始终固定在说明区域下方。\n\n", count: 300)
        let json: [String: Any] = [
            "tag_name": "v0.4.1",
            "body": notes,
            "html_url": "https://github.com/huangzhuangjia/halodock/releases/tag/v0.4.1",
            "draft": false, "prerelease": false,
            "assets": [["name": "HaloDock-0.4.1-macos-arm64.dmg", "browser_download_url": "https://github.com/huangzhuangjia/halodock/releases/download/v0.4.1/HaloDock-0.4.1-macos-arm64.dmg", "size": 100]]
        ]
        let release = try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: json))
        let manager = UpdateManager(currentVersion: "0.4.0", defaults: defaults)
        let alert = manager.makeUpdateAlert(release)
        app.activate(ignoringOtherApps: true)
        print("Alert result: \(alert.runModal().rawValue)")
    }
}
