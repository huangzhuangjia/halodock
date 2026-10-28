import AppKit
import SwiftUI

@main
struct HaloDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            HaloDockSettingsView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
