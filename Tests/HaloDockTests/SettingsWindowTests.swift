import AppKit
import Testing
@testable import HaloDock

@Test @MainActor func settingsAndUpdateProgressReuseOneWindow() throws {
    _ = NSApplication.shared
    let delegate = AppDelegate()
    defer { delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }

    // Reproduce opening the native SwiftUI settings before starting an update.
    let native = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    native.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
    native.isReleasedWhenClosed = false
    native.orderFront(nil)
    let originalWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
    defer {
        native.close()
        native.identifier = nil
    }

    let settingsWindows = {
        NSApp.windows.filter {
            ["com_apple_SwiftUI_Settings_window", "HaloDockSettings"].contains($0.identifier?.rawValue ?? "")
        }
    }
    delegate.showSettings()
    #expect(NSApp.windows.allSatisfy { originalWindows.contains(ObjectIdentifier($0)) })
    #expect(settingsWindows().count == 1)
    #expect(settingsWindows().first === native)

    // The updater uses this same callback when it begins showing progress.
    let name = "HaloDock.SettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let updates = UpdateManager(currentVersion: "1.0.0", defaults: defaults)
    updates.revealProgress = { delegate.showSettings() }
    for _ in 0..<3 {
        updates.revealProgress?()
        #expect(NSApp.windows.allSatisfy { originalWindows.contains(ObjectIdentifier($0)) })
        #expect(settingsWindows().count == 1)
        #expect(settingsWindows().first === native)
        native.close()
        #expect(!native.isVisible)
        delegate.showSettings()
        #expect(native.isVisible)
        #expect(settingsWindows().count == 1)
    }

    // Fresh launch through the menu-bar path also retains its own window.
    native.close()
    native.identifier = nil
    let fresh = AppDelegate()
    defer { fresh.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
    fresh.showSettings()
    let created = try #require(settingsWindows().first)
    defer {
        created.close()
        created.identifier = nil
    }
    #expect(created !== native)
    created.close()
    fresh.showSettings()
    #expect(created.isVisible)
    #expect(settingsWindows().count == 1)
    #expect(settingsWindows().first === created)
}
