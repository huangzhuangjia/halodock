import AppKit
import SwiftUI
import ImageIO

@main struct FeaturePreviews {
    @MainActor static func render<V: View>(_ view: V, name: String, size: CGSize, directory: URL) async throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw WorkError("预览失败") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-FeaturePreview-\(UUID())")
        let name = "HaloDock.FeaturePreview.\(UUID())"
        let preferences = UserDefaults(suiteName: name)!
        preferences.set("coral", forKey: "accent")
        let board = NSPasteboard(name: .init(name))
        let system = SystemState(pasteboard: board, defaults: preferences)
        defer { system.shutdown(); board.releaseGlobally(); preferences.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let scenes = ScenePanel(defaults: preferences)
        let store = WorkbenchStore(directory: root)
        _ = store.createCollection("产品迭代")
        _ = store.add(text: "本周目标\n完成滚动截图、GIF 和工作台。\n所有演示内容均为专用测试资料。", title: "迭代清单")
        _ = store.add(text: "https://example.com/release", title: "发布链接")
        _ = store.saveSnippet(TextSnippet(title: "进度回复", body: "{{日期}} 更新：\n已完成：{{剪贴板}}\n下一步：", group: "工作"))
        let image = NSImage(size: CGSize(width: 1000, height: 600), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("HaloDock 工作台" as NSString).draw(at: CGPoint(x: 60, y: 420), withAttributes: [.font: NSFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: NSColor.black])
            ("截图 → 识字 → 收集 → 复用" as NSString).draw(at: CGPoint(x: 60, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.systemOrange])
            ("https://example.com" as NSString).draw(at: CGPoint(x: 60, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
            return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        _ = store.add(image: image, title: "截图行动卡演示")
        try await render(WorkbenchView(store: store).defaultAppStorage(preferences), name: "workbench", size: CGSize(width: 860, height: 620), directory: directory)
        try await render(Form { ScenePanelSettings(scenes: scenes) }.formStyle(.grouped).frame(width: 600, height: 620).modifier(HaloDockTheme()).defaultAppStorage(preferences), name: "scenes", size: CGSize(width: 600, height: 620), directory: directory)
        try await render(HaloDockView(scenes: scenes, workbench: store, openSettings: {}, system: system, emptyTrash: {}, takeScreenshot: {}).defaultAppStorage(preferences), name: "panel", size: CGSize(width: 390, height: 780), directory: directory)
        app.appearance = NSAppearance(named: .darkAqua)
        try await render(HaloDockView(scenes: scenes, workbench: store, openSettings: {}, system: system, emptyTrash: {}, takeScreenshot: {}).environment(\.colorScheme, .dark).defaultAppStorage(preferences), name: "panel-dark", size: CGSize(width: 390, height: 780), directory: directory)
        try await render(WorkbenchView(store: store).environment(\.colorScheme, .dark).defaultAppStorage(preferences), name: "workbench-dark", size: CGSize(width: 860, height: 620), directory: directory)
        if ProcessInfo.processInfo.environment["HALODOCK_INTERACTIVE_PREVIEW"] == "1" {
            app.appearance = NSAppearance(named: .aqua)
            let window = NSWindow(contentViewController: NSHostingController(rootView: WorkbenchView(store: store).defaultAppStorage(preferences)))
            window.title = "HaloDock 功能验证 · 专用测试资料"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center(); window.makeKeyAndOrderFront(nil)
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
            let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
            appMenu.addItem(NSMenuItem(title: "退出预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in app.run() }
        }
    }
}
