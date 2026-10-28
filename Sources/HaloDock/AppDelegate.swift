import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let system = SystemState()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        LoginItemState.shared.configureOnLaunch()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = HaloDockBrand.image()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "HaloDock"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: HaloDockView(openSettings: { [weak self] in
            self?.showSettings()
        }, system: system, emptyTrash: { [weak self] in
            self?.confirmEmptyTrash()
        }, takeScreenshot: { [weak self] in
            self?.popover.performClose(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.system.takeScreenshot()
            }
        }))
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: HaloDockSettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "HaloDock 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        // Ask Finder to handle all mounted volumes and its usual permission rules.
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "无法清空废纸篓"
            let failure = NSAlert()
            failure.messageText = "清空未完成"
            failure.informativeText = message
            failure.addButton(withTitle: "好")
            failure.runModal()
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
