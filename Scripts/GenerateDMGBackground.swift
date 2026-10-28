import AppKit

@main struct GenerateDMGBackground {
    @MainActor static func main() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1360, pixelsHigh: 880, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 680, height: 440)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let ink = NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.18, alpha: 1)
        let coral = NSColor(calibratedRed: 0.95, green: 0.38, blue: 0.26, alpha: 1)
        NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 680, height: 440).fill()
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, bold: Bool = false, color: NSColor = .darkGray) {
            (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color])
        }
        HaloDockBrand.draw(in: NSRect(x: 40, y: 354, width: 38, height: 38))
        text("HaloDock", 92, 362, 26, bold: true, color: ink)
        text("你的 Mac 小助手，准备就绪。", 42, 324, 15)
        for x: CGFloat in [180, 500] {
            NSColor.white.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 88, y: 127, width: 176, height: 158), xRadius: 25, yRadius: 25).fill()
        }
        coral.setStroke()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 294, y: 212)); arrow.line(to: NSPoint(x: 386, y: 212))
        arrow.move(to: NSPoint(x: 372, y: 226)); arrow.line(to: NSPoint(x: 386, y: 212)); arrow.line(to: NSPoint(x: 372, y: 198))
        arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
        text("拖到右侧，开始使用", 255, 84, 17, bold: true, color: ink)
        text("安装后，从“应用程序”打开，在菜单栏找到歪头屏。", 153, 54, 13)
        text("更新前请先退出旧版 HaloDock。", 242, 27, 11, color: .gray)
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
