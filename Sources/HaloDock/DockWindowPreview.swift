import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI
import Combine

struct DockPreviewPlacement {
    static func frame(anchor: CGRect, panel: CGSize, visible: CGRect, display: CGRect) -> CGRect {
        let dockAtBottom = anchor.midY < display.minY + display.height * 0.25
        let dockAtLeft = !dockAtBottom && anchor.midX < display.midX
        var x = dockAtBottom ? anchor.midX - panel.width / 2 : dockAtLeft ? anchor.maxX + 10 : anchor.minX - panel.width - 10
        var y = dockAtBottom ? anchor.maxY + 10 : anchor.midY - panel.height / 2
        x = min(max(visible.minX + 8, x), max(visible.minX + 8, visible.maxX - panel.width - 8))
        y = min(max(visible.minY + 8, y), max(visible.minY + 8, visible.maxY - panel.height - 8))
        return CGRect(x: x, y: y, width: panel.width, height: panel.height)
    }
}

@MainActor
struct DockWindowThumbnail: Identifiable {
    let id: String
    let title: String
    let image: NSImage?
    let window: AXUIElement?
    let minimized: Bool
}

@MainActor
final class DockWindowPreview: ObservableObject {
    static let shared = DockWindowPreview()
    @Published private(set) var enabled: Bool
    @Published private(set) var message = "默认关闭。开启后，鼠标停在 Dock 的 App 图标上可查看窗口。"
    @Published private(set) var thumbnails: [DockWindowThumbnail] = []
    @Published private(set) var appName = ""
    @Published private(set) var loading = false
    private var monitor: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var permissionObservation: AnyCancellable?
    private var panel: NSPanel?
    private var activeApp: NSRunningApplication?
    private var candidatePID: pid_t?
    private var candidateSince = Date()
    private var lastInside = Date()
    private var generation = UUID()
    private let defaults: UserDefaults
    private var configured = false
    private var suspension: (() -> Bool)?
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var screenGranted: Bool { CGPreflightScreenCaptureAccess() }
    var supported: Bool { if #available(macOS 14.0, *) { return true }; return false }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults; enabled = defaults.bool(forKey: "dockWindowPreview") }
    func configure(suspended: @escaping () -> Bool) {
        guard !configured else { return }; configured = true; suspension = suspended
        permissionObservation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in self?.refreshPermissions() }
        refreshPermissions()
    }
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: "dockWindowPreview")
        refreshPermissions()
    }
    func refreshPermissions() {
        guard enabled else { stopMonitor(); message = "已关闭 Dock 窗口预览。"; return }
        guard supported else { stopMonitor(); message = "Dock 实时预览需要 macOS 14 或更新版本。"; return }
        guard accessibilityGranted && screenGranted else {
            stopMonitor()
            message = "请允许辅助功能和屏幕录制，按系统提示重新打开 App 后生效。"
            return
        }
        message = "已开启 · 悬停 Dock 图标约 0.4 秒显示窗口，点击缩略图切换。"
        guard monitor == nil else { return }
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshPermissions()
    }
    func requestScreenRecording() {
        if screenGranted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
        else { _ = CGRequestScreenCaptureAccess() }
        refreshPermissions()
    }
    func openAccessibilitySettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) } }
    private func poll() {
        guard enabled, accessibilityGranted, screenGranted, suspension?() != true else { hide(); return }
        let mouse = NSEvent.mouseLocation
        if let panel, panel.isVisible && panel.frame.contains(mouse) { lastInside = Date(); return }
        guard let hit = dockItem(at: mouse) else {
            if Date().timeIntervalSince(lastInside) > 0.45 { hide() }
            candidatePID = nil; return
        }
        lastInside = Date()
        if candidatePID != hit.app.processIdentifier {
            hide(); candidatePID = hit.app.processIdentifier; candidateSince = Date(); return
        }
        guard Date().timeIntervalSince(candidateSince) >= 0.36 else { return }
        if activeApp?.processIdentifier == hit.app.processIdentifier { return }
        activeApp = hit.app
        load(app: hit.app, anchor: hit.frame)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func rect(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: point.x, y: top - point.y - extent.height, width: extent.width, height: extent.height)
    }
    private func dockItem(at point: CGPoint) -> (app: NSRunningApplication, frame: CGRect)? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        var element: AXUIElement?
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(top - point.y), &element) == .success else { return nil }
        for _ in 0..<4 {
            guard let current = element else { return nil }
            if attribute(current, kAXRoleAttribute) as? String == "AXDockItem" {
                let subrole = attribute(current, kAXSubroleAttribute) as? String
                guard subrole == "AXApplicationDockItem", let frame = rect(current), frame.contains(point),
                      let url = attribute(current, kAXURLAttribute) as? URL else { return nil }
                let app = NSWorkspace.shared.runningApplications.first { app in
                    app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
                }
                guard let app, !app.isTerminated else { return nil }
                return (app, frame)
            }
            guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = (parent as! AXUIElement)
        }
        return nil
    }
    private func load(app: NSRunningApplication, anchor: CGRect) {
        generation = UUID(); let token = generation; loadTask?.cancel()
        thumbnails = []; loading = true; appName = app.localizedName ?? "App"
        show(anchor: anchor, count: 1)
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard #available(macOS 14.0, *) else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard !Task.isCancelled, generation == token else { return }
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(axApp, 0.08)
                let axWindows = Array((attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []).prefix(12))
                let axMetadata = axWindows.map { window in
                    (frame: rect(window), title: attribute(window, kAXTitleAttribute) as? String ?? "", minimized: attribute(window, kAXMinimizedAttribute) as? Bool ?? false)
                }
                let windows = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.frame.width >= 70 && $0.frame.height >= 60 }
                var previews: [DockWindowThumbnail] = [], used = Set<Int>()
                for window in windows.prefix(6) {
                    try Task.checkCancellation()
                    let match = axWindows.indices.first { i in
                        guard !used.contains(i), let frame = axMetadata[i].frame else { return false }
                        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
                        let converted = CGRect(x: window.frame.minX, y: screenTop - window.frame.maxY, width: window.frame.width, height: window.frame.height)
                        return abs(frame.minX - converted.minX) < 6 && abs(frame.minY - converted.minY) < 6 && abs(frame.width - converted.width) < 6 && abs(frame.height - converted.height) < 6
                    } ?? axWindows.indices.first { !used.contains($0) && !axMetadata[$0].title.isEmpty && axMetadata[$0].title == window.title }
                    let ax = match.map { axWindows[$0] }; if let match { used.insert(match) }
                    let minimized = match.map { axMetadata[$0].minimized } ?? false
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let scale = min(1, 480 / max(window.frame.width, window.frame.height))
                    config.width = max(1, Int(window.frame.width * scale)); config.height = max(1, Int(window.frame.height * scale)); config.showsCursor = false
                    let pixels = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard !Task.isCancelled, generation == token else { return }
                    let image = pixels.map { NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)) }
                    previews.append(.init(id: String(window.windowID), title: window.title?.isEmpty == false ? window.title! : appName, image: image, window: ax, minimized: minimized))
                }
                for i in axWindows.indices where !used.contains(i) && previews.count < 6 {
                    let window = axWindows[i]
                    let title = axMetadata[i].title.isEmpty ? appName : axMetadata[i].title
                    let minimized = axMetadata[i].minimized
                    previews.append(.init(id: "ax-\(i)", title: title, image: nil, window: window, minimized: minimized))
                }
                guard !Task.isCancelled, generation == token else { return }
                loading = false; thumbnails = previews; show(anchor: anchor, count: max(1, min(3, previews.count)))
            } catch {
                guard generation == token else { return }
                thumbnails = []; hide()
                message = "预览暂不可用：" + error.localizedDescription
            }
        }
    }
    private func show(anchor: CGRect, count: Int) {
        if panel == nil {
            let controller = NSHostingController(rootView: DockWindowPreviewPanel(preview: self))
            controller.sizingOptions = []
            let window = NSPanel(contentViewController: controller)
            window.identifier = NSUserInterfaceItemIdentifier("HaloDockDockPreview")
            window.styleMask = [.borderless, .nonactivatingPanel]
            window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
            window.isReleasedWhenClosed = false; window.level = .floating; window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = window
        }
        let width = CGFloat(count * 204 + 24)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        guard let screen, let panel else { return }
        let size = CGSize(width: min(width, screen.visibleFrame.width - 16), height: 206)
        panel.contentView?.setFrameSize(size); panel.setContentSize(size)
        panel.setFrame(DockPreviewPlacement.frame(anchor: anchor, panel: panel.frame.size, visible: screen.visibleFrame, display: screen.frame), display: true)
        panel.orderFrontRegardless()
    }
    func activate(_ thumbnail: DockWindowThumbnail) {
        guard let app = activeApp, !app.isTerminated else { hide(); return }
        if let window = thumbnail.window {
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        app.activate(options: [.activateIgnoringOtherApps])
        hide()
    }
    func activateApp() { activeApp?.activate(options: [.activateIgnoringOtherApps]); hide() }
    func hide() {
        generation = UUID(); loadTask?.cancel(); loadTask = nil
        panel?.orderOut(nil); thumbnails = []; loading = false; activeApp = nil
    }
    private func stopMonitor() { monitor?.cancel(); monitor = nil; candidatePID = nil; hide() }
    func shutdown() { stopMonitor(); permissionObservation = nil; panel?.close(); panel = nil; configured = false }
}

private struct DockWindowPreviewPanel: View {
    @ObservedObject var preview: DockWindowPreview
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(preview.appName).font(.headline); Spacer(); Button("打开应用") { preview.activateApp() }.controlSize(.small) }
            if preview.thumbnails.isEmpty {
                VStack(spacing: 8) {
                    if preview.loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "macwindow").font(.title2).foregroundStyle(.secondary) }
                    Text(preview.loading ? "正在读取窗口…" : "暂无可预览窗口，可直接打开应用。").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(preview.thumbnails) { thumbnail in
                            Button { preview.activate(thumbnail) } label: {
                                VStack(spacing: 7) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                                        if let image = thumbnail.image { Image(nsImage: image).resizable().scaledToFit().padding(4) }
                                        else { Image(systemName: thumbnail.minimized ? "minus.rectangle" : "macwindow").font(.largeTitle).foregroundStyle(.secondary) }
                                    }.frame(width: 192, height: 112)
                                    Text(thumbnail.minimized ? thumbnail.title + " · 已最小化" : thumbnail.title).font(.caption).lineLimit(1).frame(width: 192)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).help("切换到：" + thumbnail.title)
                        }
                    }
                }
            }
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).modifier(HaloDockTheme())
    }
}

struct DockPreviewSettings: View {
    @ObservedObject private var preview = DockWindowPreview.shared
    var body: some View {
        Section("Dock 窗口预览") {
            Toggle("悬停 Dock 图标预览窗口", isOn: Binding(get: { preview.enabled }, set: preview.setEnabled)).disabled(!preview.supported)
            Text(preview.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("支持 App 和 Finder 窗口，最多显示 6 个预览。鼠标移到缩略图可点击切换，移开自动收起；最小化或无法捕获的窗口显示占位卡。窗口画面只在本机临时显示。需要 macOS 14+、辅助功能和屏幕录制权限。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LabeledContent("辅助功能", value: preview.accessibilityGranted ? "已允许" : "未允许")
            LabeledContent("屏幕录制", value: preview.screenGranted ? "已允许" : "未允许")
            HStack {
                Button(preview.accessibilityGranted ? "辅助功能设置" : "授权辅助功能") { if preview.accessibilityGranted { preview.openAccessibilitySettings() } else { preview.requestAccessibility() } }
                Button(preview.screenGranted ? "屏幕录制设置" : "授权屏幕录制") { preview.requestScreenRecording() }
            }
            Button("重新检查权限") { preview.refreshPermissions() }.controlSize(.small)
        }
    }
}
