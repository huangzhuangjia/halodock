import AppKit
import ImageIO
import Testing
@testable import HaloDock

private func scrollingFixture() throws -> CGImage {
    let width = 160, height = 1300
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        let value = UInt8((x * 19 + y * 13 + x * y / 5) % 255)
        bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
    } }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}

@Test @MainActor func explicitCollectionDestinationDoesNotChangeBrowsingSelection() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-DestinationTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkbenchStore(directory: dir)
    let inbox = store.selectedCollection
    #expect(store.createCollection("目标目录"))
    let target = store.selectedCollection
    store.select(inbox)
    #expect(store.add(text: "文字", to: target))
    let image = try scrollingFixture()
    #expect(store.add(image: image, to: target))
    #expect(store.add(file: URL(fileURLWithPath: "/tmp/document.md"), to: target))
    store.addClipboard(ClipboardItem(text: "剪贴板文字"), to: target)
    #expect(store.items.count == 4 && store.items.allSatisfy { $0.collectionID == target })
    #expect(store.selectedCollection == inbox && store.currentItems.isEmpty)
    #expect(store.message == "已加入「目标目录」")
    let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    #expect(!store.add(image: image, to: UUID()))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == before)
    #expect(store.items.count == 4)
}

@Test @MainActor func collectionMenuMarksCurrentAndWritesOnlyAfterChoosing() throws {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-MenuTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkbenchStore(directory: dir)
    let first = store.selectedCollection
    #expect(store.createCollection("另一工作台"))
    let second = store.selectedCollection
    var chosen: UUID?
    let chooser = WorkbenchDestinationPicker { id in chosen = id; _ = store.add(text: "保存", to: id) }
    let menu = chooser.menu(store: store)
    let entries = menu.items.filter { $0.representedObject is UUID }
    #expect(entries.count == 2)
    #expect(entries.first { $0.representedObject as? UUID == second }?.state == .on)
    #expect(chosen == nil && store.items.isEmpty)
    let destination = try #require(entries.first { $0.representedObject as? UUID == first })
    #expect(NSApp.sendAction(try #require(destination.action), to: destination.target, from: destination))
    #expect(chosen == first && store.items.first?.collectionID == first)
    #expect(store.selectedCollection == second)
}

@Test func markdownBlocksPreserveFormattingAndNeverExecuteSource() {
    let text = "# 标题\n\n正文 **粗体**\n\n- 列表\n> 引用\n\n```swift\nlet x = 1\n```\n\n| 名称 | 数值 |\n| --- | --- |\n| 内存 | 70% |\n\n<script>alert(1)</script>"
    let blocks = MarkdownDocument.blocks(text)
    #expect(blocks.contains { $0.kind == .heading(1) && $0.text == "标题" })
    #expect(blocks.contains { $0.kind == .code("swift") && $0.text == "let x = 1" })
    #expect(blocks.contains { $0.kind == .list && $0.text == "列表" })
    #expect(blocks.filter { $0.kind == .table }.count == 1)
    #expect(blocks.first { $0.kind == .table }?.text.contains("内存") == true)
    #expect(blocks.contains { $0.kind == .paragraph && $0.text.contains("<script>") })
    #expect(Set(blocks.map(\.id)).count == blocks.count)
    #expect(MarkdownDocument.blocks("```\n未关闭代码块").contains { $0.kind == .code("") })
}

@Test @MainActor func automaticScrollingCollectsStableFramesAndStopsAfterFinish() async throws {
    let full = try scrollingFixture(), screen = try #require(NSScreen.main)
    let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 500)))
    let next = try #require(full.cropping(to: CGRect(x: 0, y: 250, width: 160, height: 500)))
    let third = try #require(full.cropping(to: CGRect(x: 0, y: 500, width: 160, height: 500)))
    var calls = 0
    let session = ExtendedCaptureSession(mode: .scroll, screen: screen, selection: CGRect(x: 0, y: 0, width: 160, height: 500), initial: first, captureFrame: {
        calls += 1
        return calls < 4 ? next : third
    })
    defer { session.close() }
    session.startScroll()
    #expect(session.scrollPhase == .capturing)
    for _ in 0..<150 where session.count < 3 { try await Task.sleep(for: .milliseconds(20)) }
    #expect(session.count == 3 && session.outputImage.height == 1000)
    session.pauseScroll()
    #expect(session.scrollPhase == .paused && !session.busy)
    let pausedCalls = calls
    try await Task.sleep(for: .milliseconds(300))
    #expect(calls == pausedCalls)
    session.startScroll(); session.finishScroll()
    let completedCalls = calls, height = session.outputImage.height
    try await Task.sleep(for: .milliseconds(300))
    #expect(session.scrollPhase == .preview && calls == completedCalls && session.outputImage.height == height)
}

@Test func dockPreviewPlacementFitsBottomLeftRightAndSmallDisplays() {
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900), visible = CGRect(x: 0, y: 60, width: 1440, height: 810)
    let panel = CGSize(width: 636, height: 206)
    for anchor in [CGRect(x: 10, y: 0, width: 60, height: 60), CGRect(x: 0, y: 500, width: 60, height: 60), CGRect(x: 1380, y: 400, width: 60, height: 60)] {
        let frame = DockPreviewPlacement.frame(anchor: anchor, panel: panel, visible: visible, display: display)
        #expect(visible.contains(frame))
    }
    let leftDisplay = CGRect(x: -1200, y: -200, width: 1200, height: 800)
    let placement = DockPreviewPlacement.frame(anchor: CGRect(x: -1200, y: 100, width: 50, height: 50), panel: panel, visible: leftDisplay, display: leftDisplay)
    #expect(leftDisplay.contains(placement))
}

@Test @MainActor func scrollingMatchesTextDocumentWithWhiteBackground() throws {
    let width = 720, height = 1800
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    for row in 0..<42 {
        let text = "第 \(row + 1) 项  HaloDock \(row * 37)  工作台资料 \(String(repeating: "内容 ", count: row % 6 + 2))"
        (text as NSString).draw(at: CGPoint(x: 35, y: 20 + row * 41), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = try #require(rep.cgImage)
    let a = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: width, height: 900)))
    let b = try #require(image.cropping(to: CGRect(x: 0, y: 400, width: width, height: 900)))
    let overlap = try #require(ScrollStitcher.overlap(previous: a, next: b))
    #expect(abs(overlap - 500) <= 3)
}

@Test func feedbackDraftEncodesContentAndEnvironmentIsOptional() throws {
    var report = FeedbackReport()
    #expect(!report.valid && !report.canOpenDraft)
    report.title = "截图 & 工作台 + 反馈"
    report.description = "点击保存后没有提示\n第二行"
    report.steps = "打开 App → 截图"
    report.version = "0.4.0"
    #expect(report.valid && report.canOpenDraft)
    let url = try #require(report.draftURL)
    #expect(url.host == "github.com" && url.path == "/huangzhuangjia/halodock/issues/new")
    let queries = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queries.first { $0.name == "title" }?.value == "[Bug] 截图 & 工作台 + 反馈")
    #expect(queries.first { $0.name == "body" }?.value?.contains("0.4.0") == true)
    report.includeEnvironment = false
    #expect(!report.body.contains("运行环境"))
    report.description = String(repeating: "长内容", count: 2000)
    #expect(!report.canOpenDraft)
    #expect(report.body.contains(report.description))
}
