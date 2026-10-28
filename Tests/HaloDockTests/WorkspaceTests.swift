import AppKit
import Testing
import ImageIO
@testable import HaloDock

private func patternImage(width: Int = 180, height: Int = 900) throws -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    // Deterministic rich texture avoids ambiguous overlap, while preserving row identity.
    for y in 0..<height { for x in 0..<width {
        let value = UInt8((x * 17 + y * 31 + x * y / 7) % 255)
        let index = (y * width + x) * 4
        bytes[index] = value; bytes[index + 1] = value; bytes[index + 2] = value
    } }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}

@Test @MainActor func workbenchPersistsCollectionsAssetsMovesSnippetsAndMarkdown() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-WorkTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkbenchStore(directory: root)
    let inbox = store.selectedCollection
    #expect(!store.addAsset(Data("invalid".utf8), extension: "png", kind: .image, title: "坏图片"))
    #expect(store.add(text: "研究资料 https://example.com", title: "资料"))
    let item = try #require(store.items.first)
    #expect(store.createCollection("发布"))
    let release = store.selectedCollection
    #expect(release != inbox)
    store.move(item, to: release)
    #expect(store.currentItems.count == 1)
    let image = try patternImage()
    #expect(store.add(image: image, title: "设计稿"))
    let asset = try #require(store.items.first { $0.kind == .image })
    let assetURL = try #require(store.assetURL(asset))
    #expect(FileManager.default.fileExists(atPath: assetURL.path))
    let snippet = TextSnippet(title: "回复", body: "{{日期}} {{时间}}：{{剪贴板}}", group: "工作")
    #expect(store.saveSnippet(snippet))
    let board = NSPasteboard(name: .init("HaloDock.Test.\(UUID())"))
    defer { board.releaseGlobally() }
    board.setString("完成", forType: .string)
    store.copySnippet(snippet, board: board)
    #expect(board.string(forType: .string)?.contains("完成") == true)
    #expect(board.string(forType: .string)?.contains("{{") == false)
    let restored = WorkbenchStore(directory: root)
    #expect(restored.selectedCollection == release && restored.currentItems.count == 2)
    #expect(restored.snippets.first == snippet)
    let export = root.appendingPathComponent("export.md")
    try restored.exportMarkdown(to: export)
    let markdown = try String(contentsOf: export, encoding: .utf8)
    #expect(markdown.contains("# 发布") && markdown.contains("资料") && markdown.contains("![附件]"))
    restored.remove(asset)
    #expect(!FileManager.default.fileExists(atPath: assetURL.path))
    restored.removeCollection()
    #expect(restored.collections.count == 1 && restored.items.isEmpty)
    #expect(WorkbenchStore(directory: root).snippets.count == 1)
}

@Test @MainActor func corruptedWorkbenchIndexDoesNotGetOverwritten() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-CorruptTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("index.json")
    let invalid = Data("invalid".utf8); try invalid.write(to: url)
    let store = WorkbenchStore(directory: root)
    #expect(store.readOnly && !store.collections.isEmpty)
    #expect(!store.add(text: "不会覆盖原文件"))
    #expect(try Data(contentsOf: url) == invalid)
}

@Test @MainActor func scenePanelsRestoreCustomSizesVisibilityAndSelectedScene() throws {
    let name = "HaloDock.SceneTests.\(UUID())", defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("trash,screenshot", forKey: "quickActionOrder")
    defaults.set("focus", forKey: "hiddenQuickActions")
    let scenes = ScenePanel(defaults: defaults)
    #expect(scenes.scenes.count == 4)
    #expect(!scenes.current.actions.contains("focus"))
    scenes.select(try #require(scenes.scenes.first { $0.name == "工作" }).id)
    scenes.setSize(.memory, .large); scenes.setVisible(.network, false)
    scenes.duplicate()
    #expect(scenes.current.name.contains("副本"))
    let restored = ScenePanel(defaults: defaults)
    #expect(restored.current == scenes.current)
    #expect(restored.current.widgets.first { $0.widget == .memory }?.size == .large)
    #expect(restored.current.widgets.first { $0.widget == .network }?.visible == false)
    restored.remove(); #expect(restored.scenes.count == 4)
}

@Test func screenshotActionsAcceptOnlyWebLinksAndExportMarkdown() {
    let links = ScreenshotActions.links(in: "https://example.com/a\nhttps://example.com/a\nfile:///etc/passwd javascript:alert(1) https://example.org")
    #expect(links.count == 2)
    #expect(links.allSatisfy { ["http", "https"].contains($0.scheme) })
    #expect(ScreenshotActions.markdown("第一行\n第二行").contains("> 第一行\n> 第二行"))
}

@Test func scrollingOverlapStitchesOnlyNewRowsWithoutInvertingPixels() throws {
    let full = try patternImage()
    let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 500)))
    let next = try #require(full.cropping(to: CGRect(x: 0, y: 300, width: 180, height: 500)))
    let overlap = try #require(ScrollStitcher.overlap(previous: first, next: next))
    #expect(abs(overlap - 200) <= 2)
    let result = try ScrollStitcher.append(next, to: first, overlap: overlap)
    #expect(result.height == 800 && result.width == 180)
    let reference = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 800)))
    let a = try #require(result.dataProvider?.data) as Data
    let b = try #require(reference.dataProvider?.data) as Data
    // Compare visible pixel rows; context may use padded bytes-per-row.
    for row in [0, 10, 499, 500, 790] {
        #expect(a.subdata(in: row * result.bytesPerRow..<row * result.bytesPerRow + 180 * 4) == b.subdata(in: row * reference.bytesPerRow..<row * reference.bytesPerRow + 180 * 4))
    }
    #expect(ScrollStitcher.isDuplicate(first, first))
}

@Test func gifEncoderProducesAnimatedFileWithDelaysAndBoundedDimensions() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-Test-\(UUID()).gif")
    defer { try? FileManager.default.removeItem(at: url) }
    let encoder = try GIFEncoder(url: url)
    let image = try patternImage(width: 1200, height: 300)
    try encoder.add(image, delay: 0.2)
    try encoder.add(image, delay: 0.3)
    try encoder.finish()
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    #expect(CGImageSourceGetCount(source) == 2)
    let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(frame.width == 900 && frame.height == 225)
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any])
    let gif = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
    #expect(gif[kCGImagePropertyGIFDelayTime] as? Double == 0.3)
}

@Test @MainActor func extendedCaptureFlowCombinesPagesRecordsGifAndCleansTemporaryFile() async throws {
    let screen = try #require(NSScreen.main)
    let full = try patternImage()
    let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 500)))
    let next = try #require(full.cropping(to: CGRect(x: 0, y: 300, width: 180, height: 500)))
    let scroll = ExtendedCaptureSession(mode: .scroll, screen: screen, selection: .init(x: 0, y: 0, width: 180, height: 500), initial: first, captureFrame: { next })
    scroll.addPage()
    for _ in 0..<100 where scroll.busy { try await Task.sleep(for: .milliseconds(20)) }
    #expect(scroll.count == 2 && scroll.outputImage.height == 800)
    scroll.close()
    let gif = ExtendedCaptureSession(mode: .gif, screen: screen, selection: .init(x: 0, y: 0, width: 180, height: 500), initial: first, captureFrame: { first }, countdownSeconds: 0, duration: 0.3)
    gif.startGIF()
    for _ in 0..<100 where !gif.completed { try await Task.sleep(for: .milliseconds(20)) }
    #expect(gif.completed && gif.count > 1)
    let url = try #require(gif.gifURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    gif.close()
    for _ in 0..<50 where FileManager.default.fileExists(atPath: url.path) { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func scrollingRejectsBlankOrNonmatchingFramesAndBoundsOutput() throws {
    let full = try patternImage()
    let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 200)))
    let different = try #require(full.cropping(to: CGRect(x: 0, y: 500, width: 180, height: 200)))
    #expect(ScrollStitcher.overlap(previous: first, next: different) == nil)
    let ctx = try #require(CaptureImage.context(width: 180, height: 200))
    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 200))
    let blank = try #require(ctx.makeImage())
    #expect(ScrollStitcher.overlap(previous: blank, next: blank) == nil)
    #expect(throws: WorkError.self) { try ScrollStitcher.append(first, to: first, overlap: first.height) }
}

@Test @MainActor func cancelledGifCountdownDoesNotContinueRecording() async throws {
    let screen = try #require(NSScreen.main)
    let image = try patternImage(width: 100, height: 100)
    var called = false
    let session = ExtendedCaptureSession(mode: .gif, screen: screen, selection: .init(x: 0, y: 0, width: 100, height: 100), initial: image, captureFrame: { called = true; return image }, countdownSeconds: 1)
    session.startGIF()
    session.close()
    try await Task.sleep(for: .milliseconds(80))
    #expect(!session.recording && !session.completed && !called)
}
