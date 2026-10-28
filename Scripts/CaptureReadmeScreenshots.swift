import AppKit
import SwiftUI

@main struct ReadmeScreenshots {
    @MainActor static func capture<V: View>(_ view: V, path: String, width: CGFloat, height: CGFloat? = nil) throws {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let size = NSSize(width: width, height: height ?? fitting.height)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        window.display()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Cannot capture view") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let board = NSPasteboard(name: .init("HaloDock.ReadmePreview"))
        let preferences = UserDefaults(suiteName: "HaloDock.ReadmePreview")!
        let state = SystemState(pasteboard: board, defaults: preferences)
        defer { state.shutdown(); board.releaseGlobally() }
        try await Task.sleep(for: .seconds(1))
        try capture(HaloDockView(openSettings: {}, system: state, emptyTrash: {}, takeScreenshot: {}), path: CommandLine.arguments[1]+"/panel.png", width: 390)
        LoginItemState.shared.configureOnLaunch()
        try capture(HaloDockSettingsView(), path: CommandLine.arguments[1]+"/settings.png", width: 460, height: 620)
    }
}
