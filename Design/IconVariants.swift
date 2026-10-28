import AppKit

// All candidates share a 24-point vector coordinate system.
@MainActor
func mascot(_ index: Int, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.scale(by: rect.width / 24)
        transform.concat()
        NSColor.black.setFill()
        NSColor.black.setStroke()
        func stroke(_ path: NSBezierPath, _ width: CGFloat = 1.65) {
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
        func halo() { stroke(NSBezierPath(ovalIn: NSRect(x: 6, y: 19, width: 12, height: 3)), 1.5) }
        func eyes(_ y: CGFloat = 9) {
            for x: CGFloat in [7.2, 14.4] {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 2.4, height: 3), xRadius: 1.2, yRadius: 1.2).fill()
            }
        }
        func smile() {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 10, y: 6.4))
            path.curve(to: NSPoint(x: 14, y: 6.4), controlPoint1: NSPoint(x: 11, y: 5), controlPoint2: NSPoint(x: 13, y: 5))
            stroke(path, 1.3)
        }
        switch index {
        case 0:
            halo()
            stroke(NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 18, height: 13), xRadius: 5, yRadius: 5))
            eyes(); smile()
        case 1:
            halo()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3, y: 8))
            path.line(to: NSPoint(x: 3.6, y: 17))
            path.line(to: NSPoint(x: 8.3, y: 14))
            path.curve(to: NSPoint(x: 15.7, y: 14), controlPoint1: NSPoint(x: 10, y: 15.3), controlPoint2: NSPoint(x: 14, y: 15.3))
            path.line(to: NSPoint(x: 20.4, y: 17))
            path.line(to: NSPoint(x: 21, y: 8))
            path.curve(to: NSPoint(x: 3, y: 8), controlPoint1: NSPoint(x: 21, y: -0.2), controlPoint2: NSPoint(x: 3, y: -0.2))
            path.close(); stroke(path)
            eyes(8)
            NSBezierPath(ovalIn: NSRect(x: 11, y: 5.7, width: 2, height: 1.7)).fill()
        case 2:
            halo()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: 2))
            path.line(to: NSPoint(x: 4, y: 9))
            path.curve(to: NSPoint(x: 20, y: 9), controlPoint1: NSPoint(x: 4, y: 20), controlPoint2: NSPoint(x: 20, y: 20))
            path.line(to: NSPoint(x: 20, y: 2))
            path.line(to: NSPoint(x: 16, y: 4))
            path.line(to: NSPoint(x: 12, y: 2))
            path.line(to: NSPoint(x: 8, y: 4))
            path.close(); stroke(path)
            eyes(); smile()
        default:
            halo()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 6, y: 3))
            path.curve(to: NSPoint(x: 4.5, y: 12), controlPoint1: NSPoint(x: -0.5, y: 3), controlPoint2: NSPoint(x: -0.5, y: 11))
            path.curve(to: NSPoint(x: 15.5, y: 14), controlPoint1: NSPoint(x: 3.7, y: 19), controlPoint2: NSPoint(x: 13.2, y: 20))
            path.curve(to: NSPoint(x: 20, y: 10.5), controlPoint1: NSPoint(x: 18.7, y: 15), controlPoint2: NSPoint(x: 20.5, y: 13))
            path.curve(to: NSPoint(x: 18, y: 3), controlPoint1: NSPoint(x: 25, y: 10), controlPoint2: NSPoint(x: 24, y: 3))
            path.close(); stroke(path)
            eyes(7.8)
        }
        return true
    }
}

@main struct Variants {
    @MainActor static func main() throws {
        let width: CGFloat = 1280
        let height: CGFloat = 570
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.90, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .labelColor, bold: Bool = false) {
            (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color])
        }
        text("HaloDock · 选择你的小伙伴", x: 40, y: 507, size: 29, color: .black, bold: true)
        text("同一形象用于菜单栏和设置页  /  下方为 32pt 与 18pt 图标预览", x: 40, y: 475, size: 14, color: .darkGray)
        let names = ["01  光环机器人", "02  光环猫", "03  小幽灵", "04  云朵精灵"]
        let descriptions = ["友好助手 · 清晰稳重", "好奇陪伴 · 更有个性", "轻巧灵动 · 极简轮廓", "柔和轻盈 · 低存在感"]
        for i in 0..<4 {
            let x = CGFloat(40 + i * 306)
            NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 48, width: 282, height: 395), xRadius: 22, yRadius: 22).fill()
            text(names[i], x: x + 22, y: 400, size: 19, color: .black, bold: true)
            text(descriptions[i], x: x + 22, y: 373, size: 13, color: .darkGray)
            mascot(i, size: 126).draw(in: NSRect(x: x + 78, y: 211, width: 126, height: 126))
            NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
            NSRect(x: x + 22, y: 183, width: 238, height: 1).fill()
            mascot(i, size: 32).draw(in: NSRect(x: x + 26, y: 115, width: 32, height: 32))
            text("设置页", x: x + 70, y: 123, size: 12, color: .darkGray)
            NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 165, y: 111, width: 92, height: 36), xRadius: 9, yRadius: 9).fill()
            mascot(i, size: 18).draw(in: NSRect(x: x + 202, y: 120, width: 18, height: 18))
            text("状态栏 · 18pt", x: x + 170, y: 84, size: 11, color: .darkGray)
        }
        image.unlockFocus()
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
