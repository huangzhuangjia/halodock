import AppKit

@main struct GenerateAppIcon {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let transform = NSAffineTransform()
                transform.scale(by: CGFloat(pixels) / 1024)
                transform.concat()
                NSColor(calibratedRed: 0.98, green: 0.53, blue: 0.38, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 210, yRadius: 210).fill()
                let mark = HaloDockBrand.image(size: 690)
                mark.isTemplate = false
                mark.draw(in: NSRect(x: 167, y: 160, width: 690, height: 690))
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
            }
        }
    }
}
