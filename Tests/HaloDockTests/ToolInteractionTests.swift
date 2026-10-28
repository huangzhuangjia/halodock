import AppKit
import Carbon
import SwiftUI
import Testing
@testable import HaloDock

@Suite(.serialized) struct ToolInteractionTests {

@Test @MainActor func registeredHotkeyDispatchesAndRejectsExternalConflict() throws {
    _ = NSApplication.shared
    let name = "HaloDock.HotkeyDispatch.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let keys = GlobalShortcuts(defaults: defaults)
    for action in ShortcutAction.allCases { _ = keys.set(nil, for: action) }
    let combo = Shortcut(keyCode: 101, modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
    #expect(keys.set(combo, for: .panel))
    keys.configure()
    defer { keys.shutdown() }
    var invoked: ShortcutAction?
    keys.onAction = { invoked = $0 }
    var event: EventRef?
    #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeUserEvent), &event) == noErr)
    let sent = try #require(event)
    defer { ReleaseEvent(sent) }
    var id = EventHotKeyID(signature: 0x48414C4F, id: ShortcutAction.panel.rawValue)
    #expect(SetEventParameter(sent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
    #expect(SendEventToEventTarget(sent, GetApplicationEventTarget()) == noErr)
    #expect(invoked == .panel)
    var external: EventHotKeyRef?
    let blocked = Shortcut(keyCode: 109, modifiers: combo.modifiers)
    #expect(RegisterEventHotKey(blocked.keyCode, blocked.modifiers, EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), 0, &external) == noErr)
    defer { if let external { UnregisterEventHotKey(external) } }
    #expect(!keys.set(blocked, for: .panel))
    #expect(keys.bindings[.panel] == combo)
}

@Test @MainActor func shortcutRecorderAcceptsACombinationAndEscapeCancels() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 50), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let recorder = RecorderButton()
    window.contentView = recorder
    defer { window.close() }
    var result: Shortcut?
    recorder.changed = { result = $0 }
    #expect(NSApp.sendAction(try #require(recorder.action), to: recorder.target, from: recorder))
    #expect(recorder.recording)
    let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "J", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: 38))
    #expect(recorder.performKeyEquivalent(with: key))
    #expect(result == Shortcut(keyCode: 38, modifiers: UInt32(cmdKey | shiftKey)))
    #expect(!recorder.recording)
    result = nil
    #expect(NSApp.sendAction(try #require(recorder.action), to: recorder.target, from: recorder))
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    recorder.keyDown(with: escape)
    #expect(result == nil && !recorder.recording)
    #expect(NSApp.sendAction(try #require(recorder.action), to: recorder.target, from: recorder))
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    #expect(result == nil && !recorder.recording)
}

@Test @MainActor func menuBarPopoverKeepsUsableHeightAfterOpeningAndReopening() async throws {
    _ = NSApplication.shared
    let name = "HaloDock.PanelSize.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let board = NSPasteboard(name: .init(name))
    defer { defaults.removePersistentDomain(forName: name); board.releaseGlobally() }
    let system = SystemState(pasteboard: board, defaults: defaults)
    defer { system.shutdown() }
    let anchor = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 80, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
    anchor.isReleasedWhenClosed = false
    let button = NSButton(title: "Panel", target: nil, action: nil)
    anchor.contentView = button
    anchor.orderFront(nil)
    defer { anchor.close() }
    let controller = NSHostingController(rootView: HaloDockView(openSettings: {}, system: system, emptyTrash: {}, takeScreenshot: {}).defaultAppStorage(defaults))
    controller.sizingOptions = [.preferredContentSize]
    let popover = NSPopover()
    popover.animates = false
    popover.behavior = .applicationDefined
    popover.contentViewController = controller
    defer { popover.close() }
    for cycle in 0..<2 {
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = controller.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        try await Task.sleep(for: .milliseconds(150))
        #expect(popover.isShown)
        #expect(popover.contentSize.width == 390)
        #expect(popover.contentSize.height >= min(600, (button.window?.screen?.visibleFrame.height ?? 800) - 100))
        #expect(popover.contentSize.height <= (button.window?.screen?.visibleFrame.height ?? 1000))
        if let directory = ProcessInfo.processInfo.environment["HALODOCK_RENDER_PREVIEWS"] {
            let target = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let view = controller.view
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent("real-popover-\(cycle).png"))
        }
        popover.close()
    }
}

@Test @MainActor func settingsCategoriesSwitchWithinOneWindowAndUpdateSelectsItsPage() async throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: HaloDockSettingsView(initialPage: .clipboard))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(150))
    func renderedPixels() throws -> Data {
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }
    let clipboard = try renderedPixels()
    NotificationCenter.default.post(name: .haloDockShowUpdates, object: nil)
    try await Task.sleep(for: .milliseconds(150))
    let update = try renderedPixels()
    #expect(clipboard != update)
    #expect(host.window === window)
    #expect(host.bounds.width == 800 && host.bounds.height == 620)
}

@MainActor private func buttons(in view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
}

@MainActor private func sampleImage() throws -> CGImage {
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
    ("HaloDock 2026" as NSString).draw(at: CGPoint(x: 100, y: 450), withAttributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black])
    ("截图识字，直接复制文字" as NSString).draw(at: CGPoint(x: 100, y: 350), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    return try #require(rep.cgImage)
}

@Test @MainActor func inlineRecognitionAndPinUseCurrentSelectionWithoutAnotherEditor() async throws {
    _ = NSApplication.shared
    let image = try sampleImage()
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = ScreenshotSelectionView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), image: image)
    window.contentView = view
    window.orderFront(nil)
    defer { view.hideRecognition(); window.close() }
    func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: 800 - point.y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 70, y: 200)))
    view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 900, y: 530)))
    view.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 900, y: 530)))
    let selection = try #require(view.selection)
    let before = Set(NSApp.windows.filter { $0.styleMask.contains(.titled) }.map(ObjectIdentifier.init))
    let recognize = try #require(buttons(in: view).first { $0.toolTip == "提取文字（本机识别）" })
    #expect(NSApp.sendAction(try #require(recognize.action), to: recognize.target, from: recognize))
    for _ in 0..<100 where !recognize.isEnabled { try await Task.sleep(for: .milliseconds(50)) }
    #expect(recognize.isEnabled)
    func texts(_ root: NSView) -> [NSTextView] { (root as? NSTextView).map { [$0] } ?? root.subviews.flatMap(texts) }
    let text = try #require(texts(view).first { $0.string.contains("HaloDock") })
    #expect(text.string.contains("截图识字"))
    #expect(view.window === window)
    #expect(NSApp.windows.filter { $0.styleMask.contains(.titled) }.allSatisfy { before.contains(ObjectIdentifier($0)) })
    if let directory = ProcessInfo.processInfo.environment["HALODOCK_RENDER_PREVIEWS"] {
        let target = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent("inline-tools.png"))
    }
    var pinnedImage: CGImage?
    var closed = false
    view.onPin = { image, _ in pinnedImage = image; return true }
    view.onCancel = { closed = true }
    let pin = try #require(buttons(in: view).first { $0.toolTip == "贴到桌面置顶" })
    #expect(NSApp.sendAction(try #require(pin.action), to: pin.target, from: pin))
    #expect(pinnedImage?.width == Int(selection.width))
    #expect(pinnedImage?.height == Int(selection.height))
    #expect(closed)


}

@Test @MainActor func renderToolPanelsForVisualReview() async throws {
    guard let directory = ProcessInfo.processInfo.environment["HALODOCK_RENDER_PREVIEWS"] else { return }
    _ = NSApplication.shared
    let target = URL(fileURLWithPath: directory)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let name = "HaloDock.Preview.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let board = NSPasteboard(name: .init(name))
    defer { defaults.removePersistentDomain(forName: name); board.releaseGlobally() }
    let system = SystemState(pasteboard: board, defaults: defaults)
    defer { system.shutdown() }
    board.clearContents(); board.setString("这是供预览使用的示例文字", forType: .string); system.history.capture()
    if let item = system.history.items.first { system.history.togglePin(item) }
    for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let root = HaloDockView(openSettings: {}, system: system, emptyTrash: {}, takeScreenshot: {})
            .environment(\.colorScheme, mode == "light" ? .light : .dark)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 390, height: 790), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent("panel-\(mode).png"))
        window.close()
    }
}

}
