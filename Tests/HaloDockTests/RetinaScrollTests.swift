import AppKit
import Testing
import ImageIO
@testable import HaloDock

@Test @MainActor func retinaWebpageOverlapSurvivesNonIntegralVerticalReduction() throws {
    let width = 1840, height = 3400
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    for row in 0..<65 {
        ("第 \(row) 行 · 网页连续滚动资料 \(row * 719) — Hello HaloDock" as NSString).draw(at: CGPoint(x: 160, y: row * 49 + 20), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let full = try #require(rep.cgImage)
    for offset in [26, 53, 97, 141, 237] {
        let a = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: width, height: 1500)))
        let b = try #require(full.cropping(to: CGRect(x: 0, y: offset, width: width, height: 1500)))
        let match = ScrollStitcher.overlap(previous: a, next: b)
        #expect(match.map { abs((1500 - $0) - offset) <= 1 } == true, "Offset \(offset), got \(String(describing: match))")
    }
}

@Test @MainActor func sparseWebpageTextWithWideMarginsStillMatchesWhileScrolling() throws {
    let width = 1600, height = 2600
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    for row in 0..<80 {
        ("网页段落 \(row) · \(row * 719) · 正文内容" as NSString).draw(at: CGPoint(x: 530, y: row * 31 + 15), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray])
    }
    NSGraphicsContext.restoreGraphicsState()
    let full = try #require(rep.cgImage)
    for offset in [31, 93, 157, 271] {
        let a = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: width, height: 1100)))
        let b = try #require(full.cropping(to: CGRect(x: 0, y: offset, width: width, height: 1100)))
        #expect(!ScrollStitcher.isDuplicate(a, b), "Moving sparse text must not be discarded as duplicate")
        let match = ScrollStitcher.overlap(previous: a, next: b)
        #expect(match.map { abs((1100 - $0) - offset) <= 1 } == true, "Sparse offset \(offset), got \(String(describing: match))")
    }
}

@Test func browserRenderedPageFramesMatchMeasuredScrollOffsets() throws {
    guard let path = ProcessInfo.processInfo.environment["HALODOCK_BROWSER_SCROLL_FRAMES"] else { return }
    let directory = URL(fileURLWithPath: path)
    struct Position: Decodable { let y: Double; let width: Double; let height: Double }
    let positions = try JSONDecoder().decode([Position].self, from: Data(contentsOf: directory.appendingPathComponent("positions.json")))
    var images: [CGImage] = []
    for i in positions.indices {
        let source = try #require(CGImageSourceCreateWithURL(directory.appendingPathComponent("frame-\(i).png") as CFURL, nil))
        images.append(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
    }
    var output = try #require(images.first)
    for i in 1..<images.count {
        let previous = images[i - 1], next = images[i]
        let match = try #require(ScrollStitcher.overlap(previous: previous, next: next))
        let delta = Int(((positions[i].y - positions[i - 1].y) * Double(next.height) / positions[i].height).rounded())
        #expect(abs((next.height - match) - delta) <= 1, "Measured scroll \(delta), matcher \(next.height - match)")
        output = try ScrollStitcher.append(next, to: output, overlap: match)
    }
    let totalDelta = Int(((positions.last!.y - positions[0].y) * Double(images[0].height) / positions[0].height).rounded())
    #expect(abs(output.height - images[0].height - totalDelta) <= 3)
    let data = try #require(NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]))
    try data.write(to: directory.appendingPathComponent("stitched.png"))
}

@Test @MainActor func sparseMovingWebpageIsNotDiscardedBySessionDeduplication() async throws {
    let width = 1600, pageHeight = 1700, frameHeight = 1100
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: pageHeight, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: pageHeight).fill()
    for row in 0..<50 {
        ("网页正文 \(row) · \(row * 719)" as NSString).draw(at: CGPoint(x: 530, y: row * 31 + 15), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray])
    }
    NSGraphicsContext.restoreGraphicsState()
    let full = try #require(rep.cgImage)
    let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: width, height: frameHeight)))
    let next = try #require(full.cropping(to: CGRect(x: 0, y: 271, width: width, height: frameHeight)))
    let session = ExtendedCaptureSession(mode: .scroll, screen: try #require(NSScreen.main), selection: CGRect(x: 0, y: 0, width: width, height: frameHeight), initial: first, captureFrame: { next })
    defer { session.close() }
    session.startScroll()
    for _ in 0..<250 where session.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
    session.pauseScroll()
    #expect(session.capturedFrames > 0)
    #expect(session.count == 2 && session.outputImage.height == frameHeight + 271)
}

@Test @MainActor func webpageWithFixedNavigationStillMatchesScrolledBody() throws {
    let width = 1000, pageHeight = 2400, frameHeight = 1000
    func document() throws -> CGImage {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: pageHeight, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: pageHeight).fill()
        for i in 0..<60 {
            ("段落 \(i) · 网页内容 \(i * 917) 正文随页面滚动" as NSString).draw(at: CGPoint(x: 220, y: i * 39 + 10), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState(); return try #require(rep.cgImage)
    }
    let page = try document()
    func frame(_ offset: Int) throws -> CGImage {
        let crop = try #require(page.cropping(to: CGRect(x: 0, y: offset, width: width, height: frameHeight)))
        let rep = NSBitmapImageRep(cgImage: crop)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.darkGray.setFill(); NSRect(x: 0, y: frameHeight - 110, width: width, height: 110).fill()
        ("固定导航 HOME  /  FEATURES  /  ABOUT  /  DOWNLOAD" as NSString).draw(at: CGPoint(x: 60, y: frameHeight - 70), withAttributes: [.font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState(); return try #require(rep.cgImage)
    }
    for delta in [75, 160, 290] {
        let previous = try frame(0), next = try frame(delta)
        let matched = ScrollStitcher.overlap(previous: previous, next: next)
        #expect(matched.map { abs((frameHeight - $0) - delta) <= 1 } == true, "Fixed navigation, actual shift \(delta), got overlap \(String(describing: matched))")
    }
}

@Test func scrollLimitsExplainHeightPixelAndSegmentCaps() {
    #expect(ScrollCaptureLimits.maximumHeight(width: 1600) == 24000)
    #expect(ScrollCaptureLimits.maximumHeight(width: 2200) == 18181)
    #expect(ScrollCaptureLimits.stopReason(width: 1600, height: 24000, count: 30)?.contains("高度上限") == true)
    #expect(ScrollCaptureLimits.stopReason(width: 2200, height: 18181, count: 30)?.contains("4000 万像素") == true)
    #expect(ScrollCaptureLimits.stopReason(width: 1600, height: 8000, count: 120)?.contains("120 段") == true)
    #expect(ScrollCaptureLimits.stopReason(width: 1600, height: 8000, count: 30) == nil)
}

@Test @MainActor func innerScrollContainerIgnoresFixedSidebarAndHeader() throws {
    let width = 1000, height = 1000
    func frame(_ scroll: Int) throws -> CGImage {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        let clip = NSBezierPath(rect: NSRect(x: 300, y: 0, width: 700, height: 900)); clip.addClip()
        for i in 0..<60 {
            ("内层正文 \(i) 标识 \(i * 719) 内容区域独立滚动" as NSString).draw(at: CGPoint(x: 340, y: height - i * 37 - 130 + scroll), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.darkGray.setFill(); NSRect(x: 0, y: 900, width: width, height: 100).fill()
        NSColor.lightGray.setFill(); NSRect(x: 0, y: 0, width: 300, height: 900).fill()
        for i in 0..<20 {
            ("固定侧栏项目 \(i)" as NSString).draw(at: CGPoint(x: 30, y: 30 + i * 40), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState(); return try #require(rep.cgImage)
    }
    let a = try frame(0), b = try frame(180)
    #expect(!ScrollStitcher.isDuplicate(a, b))
    let overlap = try #require(ScrollStitcher.overlap(previous: a, next: b))
    #expect(abs(height - overlap - 180) <= 1)
}

@Test func scrollToolbarAndPreviewStayWithinSmallAndSecondaryDisplays() {
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1200, y: -200, width: 1200, height: 800), CGRect(x: 0, y: 0, width: 640, height: 480)]
    for visible in screens {
        for selection in [visible.insetBy(dx: 15, dy: 15), CGRect(x: visible.minX + 50, y: visible.minY + 100, width: 280, height: 180)] {
            let frames = ScrollCapturePlacement.frames(selection: selection, visible: visible)
            #expect(visible.contains(frames.toolbar))
            #expect(visible.contains(frames.preview))
            #expect(frames.toolbar.height == 54)
        }
    }
}

@Test @MainActor func reachingLengthCapKeepsImageAndProvidesExplicitStopReason() throws {
    let ctx = try #require(CaptureImage.context(width: 100, height: 24000))
    let image = try #require(ctx.makeImage())
    let session = ExtendedCaptureSession(mode: .scroll, screen: try #require(NSScreen.main), selection: CGRect(x: 0, y: 0, width: 100, height: 100), initial: image, captureFrame: { image })
    defer { session.close() }
    session.startScroll()
    #expect(session.scrollPhase == .preview && !session.isWorking)
    #expect(session.attention?.contains("24000") == true)
    #expect(session.outputImage.height == 24000)
    session.confirmScroll()
    #expect(session.confirmed && session.outputImage.height == 24000)
}
