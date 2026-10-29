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
