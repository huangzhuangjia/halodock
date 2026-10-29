import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

/// Shared display capture excludes HaloDock controls during scroll/GIF sessions.
@MainActor
enum DisplayCapture {
    static func image(screen: NSScreen, excludingOwnWindows: Bool = false) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let display = content.displays.first(where: { $0.displayID == id }) else { throw WorkError("显示器已断开，请重新选择") }
            let controlIDs = Set(NSApp.windows.filter { $0.identifier?.rawValue == "HaloDockCaptureControls" }.map { CGWindowID($0.windowNumber) })
            let own = excludingOwnWindows ? content.windows.filter { controlIDs.contains($0.windowID) } : []
            let filter = SCContentFilter(display: display, excludingWindows: own)
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        guard let index = NSScreen.screens.firstIndex(of: screen) else { throw WorkError("显示器已断开") }
        return try await Task.detached {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-Capture-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-D", String(index + 1), file.path]; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0, let source = CGImageSourceCreateWithURL(file as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw WorkError("捕获失败，请检查屏幕录制权限") }
            return image
        }.value
    }
}

/// Reuse display discovery and filters across successive frames instead of querying every sample.
@MainActor
final class DisplayCaptureSource {
    let screen: NSScreen
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    init(screen: NSScreen) { self.screen = screen }
    func image() async throws -> CGImage {
        guard #available(macOS 14.0, *) else { return try await DisplayCapture.image(screen: screen, excludingOwnWindows: true) }
        if filter == nil {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let display = content.displays.first(where: { $0.displayID == id }) else { throw WorkError("显示器已断开，请重新选择") }
            let controls = Set(NSApp.windows.filter { $0.identifier?.rawValue == "HaloDockCaptureControls" }.map { CGWindowID($0.windowNumber) })
            filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { controls.contains($0.windowID) })
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            configuration = config
        }
        guard let filter, let configuration else { throw WorkError("无法准备屏幕采集") }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

enum CaptureImage {
    static func resized(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let height = max(1, Int(Double(image.height) * Double(maxWidth) / Double(image.width)))
        guard let ctx = context(width: maxWidth, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height)); return ctx.makeImage()
    }
    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, Double(width) * Double(height) <= 40_000_000 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

/// Match bottom/top overlap using a small grayscale raster. Never silently append an unmatchable page.
enum ScrollStitcher {
    static func overlap(previous: CGImage, next: CGImage) -> Int? {
        guard previous.width == next.width, previous.height == next.height,
              previous.height >= 64, previous.height <= 10000 else { return nil }
        // Preserve vertical pixel coordinates. Reducing both axes independently
        // loses text alignment and lets blank margins dominate the match score.
        let height = previous.height, width = 128
        func raster(_ image: CGImage) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: width * height)
            let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
            }
            return ok ? bytes : nil
        }
        guard let first = raster(previous), let second = raster(next),
              Int(first.max() ?? 0) - Int(first.min() ?? 0) > 12 else { return nil }
        var best: (rows: Int, error: Double)?
        for rows in max(24, height / 10)...(height - 4) {
            var sum = 0, samples = 0, texturedRows = 0
            let step = max(1, rows / 90)
            for y in Swift.stride(from: 0, to: rows, by: step) {
                var contentOnRow = 0
                for x in Swift.stride(from: 4, to: width - 4, by: 2) {
                    let ai = (height - rows + y) * width + x, bi = y * width + x
                    let a = Int(first[ai]), b = Int(second[bi])
                    let edgeA = abs(a - Int(first[ai - 2])), edgeB = abs(b - Int(second[bi - 2]))
                    // Only compare informative content, rather than vast uniform margins.
                    guard edgeA > 3 || edgeB > 3 else { continue }
                    sum += abs(a - b); samples += 1; contentOnRow += 1
                }
                if contentOnRow > 0 { texturedRows += 1 }
            }
            guard samples >= 30, texturedRows >= 4 else { continue }
            let error = Double(sum) / Double(samples)
            if best == nil || error < best!.error { best = (rows, error) }
        }
        guard let best, best.error < 18 else { return nil }
        return best.rows
    }
    static func append(_ next: CGImage, to result: CGImage, overlap: Int) throws -> CGImage {
        guard next.width == result.width, overlap >= 0, overlap < next.height else { throw WorkError("拼接尺寸不一致") }
        let height = result.height + next.height - overlap
        guard height <= 24000, let ctx = CaptureImage.context(width: result.width, height: height) else { throw WorkError("长图已达上限，请完成当前截图") }
        ctx.draw(result, in: CGRect(x: 0, y: height - result.height, width: result.width, height: result.height))
        guard let bottom = next.cropping(to: CGRect(x: 0, y: overlap, width: next.width, height: next.height - overlap)) else { throw WorkError("无法裁切下一屏") }
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height))
        guard let image = ctx.makeImage() else { throw WorkError("无法生成长图") }
        return image
    }
    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return 255 }
        let width = 128, height = min(6000, a.height)
        func raster(_ image: CGImage) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: width * height)
            let ok = bytes.withUnsafeMutableBytes { ptr -> Bool in
                guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
            }
            return ok ? bytes : nil
        }
        guard let first = raster(a), let second = raster(b) else { return 255 }
        var error = 0, content = 0
        for y in Swift.stride(from: 0, to: height, by: max(1, height / 500)) {
            for x in 2..<(width - 2) {
                let index = y * width + x
                let va = Int(first[index]), vb = Int(second[index])
                // Uniform backgrounds must not hide moving foreground text.
                guard abs(va - Int(first[index - 1])) > 2 || abs(vb - Int(second[index - 1])) > 2 || abs(va - vb) > 4 else { continue }
                error += abs(va - vb); content += 1
            }
        }
        return content == 0 ? 0 : Double(error) / Double(content)
    }
    static func isDuplicate(_ a: CGImage, _ b: CGImage) -> Bool { difference(a, b) < 0.8 }

}

final class GIFEncoder {
    let url: URL
    private let destination: CGImageDestination
    private(set) var frames = 0
    private var closed = false
    init(url: URL) throws {
        self.url = url
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 0, nil) else { throw WorkError("无法创建 GIF") }
        self.destination = destination
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    }
    func add(_ image: CGImage, delay: Double) throws {
        let longestSideWidth = min(900, max(1, Int(900 * Double(image.width) / Double(max(image.width, image.height)))))
        guard !closed, frames < 120, let small = CaptureImage.resized(image, maxWidth: longestSideWidth) else { throw WorkError("GIF 已达到帧数或尺寸限制") }
        CGImageDestinationAddImage(destination, small, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: max(0.08, delay), kCGImagePropertyGIFUnclampedDelayTime: max(0.08, delay)]] as CFDictionary)
        frames += 1
    }
    func finish() throws {
        guard !closed, frames > 0 else { throw WorkError("没有可保存的 GIF 帧") }
        closed = true
        guard CGImageDestinationFinalize(destination) else { throw WorkError("GIF 编码失败") }
    }
}

/// A serial worker keeps GIF compression off the UI thread.
actor GIFWriter {
    nonisolated let url: URL
    private let encoder: GIFEncoder
    init(url: URL) throws { self.url = url; encoder = try GIFEncoder(url: url) }
    func add(_ image: CGImage, delay: Double) throws { try encoder.add(image, delay: delay) }
    func finish() throws { try encoder.finish() }
    func discard() { try? FileManager.default.removeItem(at: url) }
}
