import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let system = SystemState()
    private let screenshots = ScreenshotCoordinator()
    private let closedLid = ClosedLidState.shared
    private var settingsWindow: NSWindow?
    private var wakeObservation: AnyCancellable?
    private var countdownObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        LoginItemState.shared.configureOnLaunch()
        UpdateManager.shared.revealProgress = { [weak self] in self?.showSettings() }
        UpdateManager.shared.canRestart = { [weak self] in
            self?.screenshots.hasActiveSession != true && self?.closedLid.active != true && self?.closedLid.isChanging != true
        }
        UpdateManager.shared.restartBlockMessage = { [weak self] in
            if self?.closedLid.active == true || self?.closedLid.isChanging == true { return "请先关闭合盖模式，恢复睡眠后再重启更新。" }
            return "请先完成或取消当前截图，再重启更新。"
        }
        UpdateManager.shared.startAutomaticChecks()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        wakeObservation = Publishers.CombineLatest(system.$keepAwake, closedLid.$active).map { $0 || $1 }.removeDuplicates().sink { [weak self] enabled in
            Task { @MainActor [weak self] in self?.updateStatusIcon(keepAwake: enabled) }
        }
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: HaloDockView(openSettings: { [weak self] in
            self?.showSettings()
        }, system: system, emptyTrash: { [weak self] in
            self?.confirmEmptyTrash()
        }, takeScreenshot: { [weak self] in
            self?.takeScreenshot()
        }))
        GlobalShortcuts.shared.onAction = { [weak self] action in
            guard let self else { return }
            // Do not steal keys or focus from an active capture editor.
            guard !self.screenshots.hasActiveSession else { return }
            switch action {
            case .panel: self.togglePopover(nil)
            case .screenshot: self.takeScreenshot()
            case .awake:
                if self.closedLid.isChanging { return }
                if self.system.keepAwake || self.closedLid.active {
                    Task { if await self.closedLid.stop() { self.system.setKeepAwake(false) } }
                } else { self.system.startWake(minutes: UserDefaults.standard.integer(forKey: "wakeMinutes")) }
            }
        }
        GlobalShortcuts.shared.configure()
        countdownObservation = system.$wakeRemaining.sink { [weak self] remaining in
            self?.updateWakeTitle(remaining)
        }
        closedLid.configure()
        if UpdateManager.shared.shouldShowUpdateResult { showSettings() }
    }

    private func takeScreenshot() {
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.screenshots.start() }
    }

    private func updateStatusIcon(keepAwake: Bool? = nil) {
        let enabled = keepAwake ?? (system.keepAwake || closedLid.active)
        let coral = NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.20, alpha: 1)
        statusItem.button?.image = HaloDockBrand.image(color: enabled ? coral : nil)
        statusItem.button?.toolTip = closedLid.active ? "HaloDock · 合盖保持运行中" : enabled ? "HaloDock · 保持唤醒已开启" : "HaloDock · 保持唤醒已关闭"
        statusItem.button?.setAccessibilityLabel(enabled ? "HaloDock，保持唤醒已开启" : "HaloDock，保持唤醒已关闭")
        updateWakeTitle(system.wakeRemaining)
    }

    private func updateWakeTitle(_ remaining: String) {
        statusItem.button?.title = remaining.isEmpty ? "" : " " + remaining
        statusItem.button?.imagePosition = remaining.isEmpty ? .imageOnly : .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        if !remaining.isEmpty {
            statusItem.button?.toolTip = "HaloDock · 唤醒剩余 " + remaining
            statusItem.button?.setAccessibilityLabel("HaloDock，唤醒剩余 " + remaining)
        }
    }

    func showSettings() {
        popover.performClose(nil)
        // SwiftUI can create its Settings scene before a menu-bar action arrives.
        // Adopt that window so update progress and every settings entry reuse it.
        if settingsWindow == nil {
            settingsWindow = NSApp.windows.first {
                $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" ||
                $0.identifier?.rawValue == "HaloDockSettings"
            }
        }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: HaloDockSettingsView())
            let window = NSWindow(contentViewController: controller)
            window.identifier = NSUserInterfaceItemIdentifier("HaloDockSettings")
            window.title = "HaloDock 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            settingsWindow = window
        }
        settingsWindow?.isReleasedWhenClosed = false
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if closedLid.isChanging {
            let alert = NSAlert()
            alert.messageText = "正在配置合盖模式"
            alert.informativeText = "请完成或取消当前授权，再退出 HaloDock。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return .terminateCancel
        }
        guard closedLid.active else { return .terminateNow }
        Task { @MainActor in
            var restored = await closedLid.stop()
            if !restored {
                let alert = NSAlert()
                alert.messageText = "退出前需要恢复睡眠"
                alert.informativeText = "合盖模式的睡眠设置尚未恢复。请授权恢复后再退出。"
                alert.addButton(withTitle: "授权恢复并退出")
                alert.addButton(withTitle: "取消退出")
                if alert.runModal() == .alertFirstButtonReturn { restored = closedLid.restoreWithAuthorization() }
            }
            sender.reply(toApplicationShouldTerminate: restored)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcuts.shared.shutdown()
        PinnedScreenshots.shared.closeAll()
        system.shutdown()
    }

    private func confirmEmptyTrash() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "确定清空废纸篓？"
        alert.informativeText = "废纸篓里的项目将被永久删除，无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空废纸篓")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let permission = FinderAutomation.permissionStatus(requestIfNeeded: true)
        guard permission == noErr else {
            FinderAutomation.showFailure(code: Int(permission), detail: nil)
            return
        }
        // Ask Finder to handle all mounted volumes and its usual permission rules.
        guard let script = NSAppleScript(source: "tell application \"Finder\" to empty trash") else {
            FinderAutomation.showFailure(code: -1, detail: "无法创建 Finder 操作。")
            return
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? -1
            let message = error[NSAppleScript.errorMessage] as? String
            FinderAutomation.showFailure(code: code, detail: message)
        } else {
            system.refresh()
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
