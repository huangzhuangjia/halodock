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
        guard previous.width == next.width, previous.height == next.height, previous.height >= 64 else { return nil }
        let height = min(700, previous.height), width = 48
        func raster(_ image: CGImage) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: width * height)
            let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
            }
            return success ? bytes : nil
        }
        guard let first = raster(previous), let second = raster(next) else { return nil }
        // CG bitmap rows are top-to-bottom for the supplied image; fixture tests verify this convention.
        let variance = first.max().map { Int($0) - Int(first.min() ?? 0) } ?? 0
        guard variance > 12 else { return nil }
        var best: (rows: Int, error: Double)?
        let minOverlap = max(24, height / 10)
        for rows in minOverlap...(height - 8) {
            let strideY = max(1, rows / 55)
            var sum = 0, samples = 0, variation = 0
            for y in Swift.stride(from: 0, to: rows, by: strideY) {
                for x in Swift.stride(from: 3, to: width - 3, by: 2) {
                    let a = Int(first[(height - rows + y) * width + x]), b = Int(second[y * width + x])
                    sum += abs(a - b); samples += 1
                    if x > 3 { variation += abs(a - Int(first[(height - rows + y) * width + x - 2])) }
                }
            }
            guard samples > 0, Double(variation) / Double(samples) > 1.2 else { continue }
            let error = Double(sum) / Double(samples)
            if best == nil || error < best!.error { best = (rows, error) }
        }
        guard let best, best.error < 12 else { return nil }
        return Int((Double(best.rows) / Double(height) * Double(previous.height)).rounded())
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
    static func isDuplicate(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let smallA = CaptureImage.resized(a, maxWidth: 64), let smallB = CaptureImage.resized(b, maxWidth: 64),
              let da = smallA.dataProvider?.data, let db = smallB.dataProvider?.data else { return false }
        return (da as Data) == (db as Data)
    }
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
