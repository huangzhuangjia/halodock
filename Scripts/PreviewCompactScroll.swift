import AppKit
import SwiftUI

@main struct PreviewCompactScroll {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出验证", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
        let width = 700, height = 2200
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        for i in 0..<40 {
            ("第 \(i + 1) 段 · 长截图交互验证 \(i * 719)" as NSString).draw(at: CGPoint(x: 45, y: i * 53 + 15), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let full = rep.cgImage!
        let initial = full.cropping(to: CGRect(x: 0, y: 0, width: width, height: 650))!
        var offset = 0
        let screen = NSScreen.main!
        let region = CGRect(x: 100, y: 160, width: 700, height: 420)
        let source = NSWindow(contentRect: CGRect(x: screen.frame.minX + region.minX, y: screen.frame.maxY - region.maxY, width: region.width, height: region.height), styleMask: [.titled], backing: .buffered, defer: false)
        source.title = "HaloDock 专用测试画面（非私人屏幕）"
        source.isReleasedWhenClosed = false
        source.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 20) {
            Text("连续长截图 · 原生交互验证").font(.title.bold())
            Text("此处使用生成的文字画面验证自动采集、确认与取消，不读取其他窗口。")
            Text("预览实时增长，点击底部 ✓ 完成。").foregroundStyle(.secondary)
            Spacer()
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white))
        source.orderFrontRegardless()
        let session = ExtendedCaptureSession(mode: .scroll, screen: screen, selection: region, initial: initial, captureFrame: {
            offset = min(offset + 70, 1260)
            return full.cropping(to: CGRect(x: 0, y: offset, width: width, height: 650))!
        })
        session.onClose = { source.close(); app.terminate(nil) }
        app.finishLaunching()
        session.show()
        app.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "HaloDockCaptureControls" && abs($0.frame.height - 54) < 1 }?.makeKeyAndOrderFront(nil)
        withExtendedLifetime(session) { app.run() }
    }
}
