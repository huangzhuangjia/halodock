import AppKit
import Carbon
import Testing
@testable import HaloDock

@Test func panelOrderingKeepsEveryActionOnceAndBoundsMoves() {
    let order = QuickAction.ordered("trash,trash,unknown,screenshot")
    #expect(order.prefix(2) == [.trash, .screenshot])
    #expect(Set(order).count == QuickAction.allCases.count)
    #expect(order.count == QuickAction.allCases.count)
    let moved = QuickAction.moved(.trash, by: 1, in: "trash,screenshot")
    #expect(QuickAction.ordered(moved).prefix(2) == [.screenshot, .trash])
    #expect(QuickAction.ordered(QuickAction.moved(.awake, by: -1, in: "")) == QuickAction.allCases)
}

@Test @MainActor func clipboardProtectsSecretsDeduplicatesPersistsPinsAndExpires() throws {
    let name = "HaloDock.ClipboardTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let board = NSPasteboard(name: .init(name))
    defer { defaults.removePersistentDomain(forName: name); board.releaseGlobally() }
    defaults.set(15, forKey: "clipboardRetentionMinutes")
    let history = ClipboardHistory(board: board, defaults: defaults)
    let now = Date()
    func put(_ text: String, at time: Date = Date()) {
        board.clearContents(); board.setString(text, forType: .string); history.capture(now: time)
    }
    put("常用内容", at: now)
    let pinned = try #require(history.items.first)
    history.togglePin(pinned)
    put("常用内容", at: now)
    #expect(history.items.count == 1 && history.items[0].pinned)
    board.clearContents(); board.setString("secret", forType: .string)
    board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    history.capture(now: now)
    #expect(history.items.count == 1)
    put("临时内容", at: now)
    history.prune(now: now.addingTimeInterval(901))
    #expect(history.items.count == 1 && history.items[0].pinned)
    put("新的临时记录", at: now)
    let restored = ClipboardHistory(board: board, defaults: defaults)
    #expect(restored.items.count == 1 && restored.items[0].text == "常用内容")
    history.clearRecent()
    #expect(history.items.count == 1)
    history.copy(pinned)
    #expect(board.string(forType: .string) == "常用内容")
    history.remove(pinned)
    #expect(ClipboardHistory(board: board, defaults: defaults).items.isEmpty)
}

@MainActor private func textImage() throws -> CGImage {
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 300).fill()
    ("HaloDock 2026" as NSString).draw(at: CGPoint(x: 40, y: 180), withAttributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black])
    ("截图识字" as NSString).draw(at: CGPoint(x: 40, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    return try #require(rep.cgImage)
}

@Test @MainActor func clipboardCapturesAndCopiesImagesAndFilesWithLimits() throws {
    let name = "HaloDock.ImageClipboardTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let board = NSPasteboard(name: .init(name))
    defer { defaults.removePersistentDomain(forName: name); board.releaseGlobally() }
    defaults.set(0, forKey: "clipboardRetentionMinutes")
    let history = ClipboardHistory(board: board, defaults: defaults)
    let data = try #require(NSBitmapImageRep(cgImage: try textImage()).representation(using: .png, properties: [:]))
    board.clearContents(); board.setData(data, forType: .png); history.capture()
    let image = try #require(history.items.first)
    #expect(image.imageData == data)
    let preview = try #require(image.previewImage)
    #expect(preview.size.width <= 128 && preview.size.height <= 128)
    history.copy(image)
    #expect(board.data(forType: .png) == data)
    let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
    board.clearContents(); board.writeObjects(urls.map { $0 as NSURL }); history.capture()
    let files = try #require(history.items.first)
    #expect(files.fileURLs == urls)
    history.copy(files)
    #expect((board.readObjects(forClasses: [NSURL.self]) as? [URL]) == urls)
    for i in 0..<60 {
        board.clearContents(); board.setString("record \(i)", forType: .string); history.capture()
    }
    #expect(history.items.count == ClipboardHistory.itemLimit)
    #expect(history.items.first?.text == "record 59")
}

@Test @MainActor func timedWakeRestoresRemainingTimeAndStopsAtDeadline() throws {
    let name = "HaloDock.WakeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let board = NSPasteboard(name: .init(name))
    defer { defaults.removePersistentDomain(forName: name); board.releaseGlobally() }
    let state = SystemState(pasteboard: board, defaults: defaults)
    defer { state.shutdown() }
    state.startWake(minutes: 30)
    #expect(state.keepAwake)
    let end = try #require(state.wakeEndsAt)
    state.updateWakeCountdown(now: end.addingTimeInterval(-65))
    #expect(state.wakeRemaining == "01:05")
    state.shutdown()
    let resumed = SystemState(pasteboard: board, defaults: defaults)
    defer { resumed.shutdown() }
    #expect(resumed.keepAwake && resumed.wakeEndsAt == end)
    resumed.updateWakeCountdown(now: end)
    #expect(!resumed.keepAwake && resumed.wakeRemaining.isEmpty)
    #expect(!defaults.bool(forKey: "keepAwake"))
    defaults.set(true, forKey: "keepAwake")
    defaults.set(Date.distantPast, forKey: "wakeEndsAt")
    let expired = SystemState(pasteboard: board, defaults: defaults)
    defer { expired.shutdown() }
    #expect(!expired.keepAwake)
}

@Test @MainActor func shortcutsRejectDuplicatesAndPersistDisabledChoices() throws {
    let name = "HaloDock.ShortcutTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let shortcuts = GlobalShortcuts(defaults: defaults)
    #expect(!shortcuts.set(Shortcut(keyCode: 0, modifiers: UInt32(shiftKey)), for: .panel))
    #expect(!shortcuts.set(ShortcutAction.screenshot.fallback, for: .panel))
    let custom = Shortcut(keyCode: 5, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
    #expect(shortcuts.set(custom, for: .panel))
    #expect(shortcuts.set(nil, for: .awake))
    let restored = GlobalShortcuts(defaults: defaults)
    #expect(restored.bindings[.panel] == custom && restored.bindings[.awake] == nil)
    #expect(custom.display == "⌃⌥⇧⌘G")
}

@Test @MainActor func recognizesChineseAndEnglishOnDevice() async throws {
    let image = try textImage()
    let text = try await ScreenshotTextRecognizer.recognize(image)
    #expect(text.contains("HaloDock"))
    #expect(text.contains("2026"))
    #expect(text.contains("截图识字"))
}

@Test func recognitionOrdersNearbyColumnsBeforeNextRow() {
    let lines = [
        RecognizedLine(text: "下行", bounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1)),
        RecognizedLine(text: "右", bounds: CGRect(x: 0.6, y: 0.71, width: 0.2, height: 0.1)),
        RecognizedLine(text: "左", bounds: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1))
    ]
    #expect(ScreenshotTextRecognizer.orderedText(lines) == "左 右\n下行")
}

@Test @MainActor func pinnedScreenshotRetainsPixelsAndReleasesClosedWindows() throws {
    _ = NSApplication.shared
    let pins = PinnedScreenshots()
    defer { pins.closeAll() }
    let image = try textImage()
    #expect(pins.show(image))
    let controller = try #require(pins.controllers.values.first)
    #expect(controller.window?.level == .floating)
    #expect(controller.window?.hidesOnDeactivate == false)
    #expect(controller.captureDocument.image.width == image.width)
    #expect(controller.window?.isVisible == true)
    controller.close()
    #expect(pins.controllers.isEmpty)
}
