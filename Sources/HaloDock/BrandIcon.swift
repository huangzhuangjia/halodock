import AppKit
import SwiftUI

/// A single vector master shared by the menu bar and all in-app brand marks.
@MainActor
enum HaloDockBrand {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by: rect.width / 24)
            transform.concat()
            NSColor.black.setStroke()
            NSColor.black.setFill()

            func stroke(_ path: NSBezierPath, width: CGFloat = 1.8) {
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            let screen = NSBezierPath()
            screen.move(to: NSPoint(x: 3, y: 8))
            screen.line(to: NSPoint(x: 3, y: 19))
            screen.curve(to: NSPoint(x: 6, y: 22), controlPoint1: NSPoint(x: 3, y: 21), controlPoint2: NSPoint(x: 4, y: 22))
            screen.line(to: NSPoint(x: 20, y: 20))
            screen.curve(to: NSPoint(x: 22, y: 17), controlPoint1: NSPoint(x: 22, y: 20), controlPoint2: NSPoint(x: 22, y: 19))
            screen.line(to: NSPoint(x: 22, y: 7))
            screen.curve(to: NSPoint(x: 19, y: 5), controlPoint1: NSPoint(x: 22, y: 5), controlPoint2: NSPoint(x: 21, y: 5))
            screen.line(to: NSPoint(x: 5, y: 6))
            screen.curve(to: NSPoint(x: 3, y: 8), controlPoint1: NSPoint(x: 3, y: 6), controlPoint2: NSPoint(x: 3, y: 7))
            screen.close()
            stroke(screen)

            NSBezierPath(roundedRect: NSRect(x: 7.5, y: 13, width: 2.2, height: 3.5), xRadius: 1.1, yRadius: 1.1).fill()
            let wink = NSBezierPath()
            wink.move(to: NSPoint(x: 14, y: 14))
            wink.line(to: NSPoint(x: 17, y: 14.8))
            stroke(wink, width: 1.6)

            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 10, y: 10))
            smile.curve(to: NSPoint(x: 15, y: 10.5), controlPoint1: NSPoint(x: 11, y: 8.5), controlPoint2: NSPoint(x: 14, y: 8.5))
            stroke(smile, width: 1.3)

            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 11, y: 5.5))
            stand.line(to: NSPoint(x: 10, y: 2))
            stand.line(to: NSPoint(x: 16, y: 2))
            stroke(stand, width: 1.7)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "HaloDock 歪头屏"
        return image
    }
}

struct BrandIcon: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: HaloDockBrand.image(size: size))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityLabel("HaloDock 歪头屏")
    }
}
