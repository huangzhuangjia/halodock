import AppKit
import SwiftUI
import ImageIO

@MainActor
struct InteractionPreviewView: View {
    @ObservedObject var store: WorkbenchStore
    @ObservedObject var scroll: ExtendedCaptureSession
    let markdown: URL
    let pdf: URL
    let image: CGImage
    @State private var section = 0
    @State private var saved = "请选择保存目标"
    var body: some View {
        VStack(spacing: 14) {
            Picker("演示", selection: $section) {
                Text("收集目标").tag(0); Text("Markdown").tag(1); Text("PDF").tag(2); Text("滚动截图").tag(3); Text("工作台").tag(4)
            }.pickerStyle(.segmented)
            if section == 0 {
                VStack(spacing: 20) {
                    Text("加入工作台时明确选择目标").font(.title2.bold())
                    WorkbenchDestinationMenu(store: store) { id in
                        _ = store.add(text: "这是专用交互验证资料", to: id)
                        saved = store.message ?? ""
                    }
                    Text(saved).foregroundStyle(.secondary)
                    Text("正在浏览：" + (store.collections.first { $0.id == store.selectedCollection }?.name ?? ""))
                    Button("截图内原生选择菜单") {
                        let picker = WorkbenchDestinationPicker { id in _ = store.add(text: "截图演示资料", to: id); saved = store.message ?? "" }
                        _ = withExtendedLifetime(picker) { picker.menu(store: store).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if section == 1 { DocumentFilePreview(url: markdown) }
            else if section == 2 { DocumentFilePreview(url: pdf) }
            else if section == 3 {
                VStack(spacing: 16) {
                    Text("滚动截图自动拼接验证").font(.title2.bold())
                    Text("使用两幅具有重叠区域的测试画面，点击开始后自动累积，未读取私人屏幕。")
                    Button("显示滚动采集控制条") { scroll.show() }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { WorkbenchView(store: store) }
        }.padding(18).frame(width: 860, height: 620).modifier(HaloDockTheme())
    }
}

@main struct InteractionPreviews {
    @MainActor static func render<V: View>(_ view: V, path: URL, size: CGSize = CGSize(width: 860, height: 620)) async throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep); try rep.representation(using: .png, properties: [:])?.write(to: path) }
        window.close()
    }
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-InteractionPreview-\(UUID())")
        let store = WorkbenchStore(directory: temporary.appendingPathComponent("Workbench"))
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = store.createCollection("产品迭代")
        _ = store.createCollection("发布资料")
        let md = temporary.appendingPathComponent("使用说明.md")
        try """
        # HaloDock 工作台

        在当前窗口阅读 **Markdown**，也可以切换到 `源码`。

        ## 截图与资料收集

        - 先选择目标工作台
        - 保存后显示所在目录
        - 原来的浏览位置保持不变

        > 所有演示内容均为专用测试资料。

        ```swift
        let destination = "产品迭代"
        print("已加入：", destination)
        ```

        | 格式 | 预览方式 |
        | --- | --- |
        | Markdown | 排版 / 源码 |
        | PDF、Office | 系统快速查看 |

        [功能说明](https://example.com)
        """.write(to: md, atomically: true, encoding: .utf8)
        let pdf = temporary.appendingPathComponent("示例文档.pdf")
        var media = CGRect(x: 0, y: 0, width: 500, height: 650)
        if let context = CGContext(pdf as CFURL, mediaBox: &media, nil) {
            context.beginPDFPage(nil); context.setFillColor(NSColor.white.cgColor); context.fill(media)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ("HaloDock PDF Preview" as NSString).draw(at: CGPoint(x: 40, y: 550), withAttributes: [.font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage(); context.closePDF()
        }
        _ = store.add(file: md); _ = store.add(file: pdf)

        let width = 200, height = 1100
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width { let i = (y * width + x) * 4; let v = UInt8((x * 19 + y * 13 + x * y / 5) % 255); bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let first = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: 600))!
        let second = image.cropping(to: CGRect(x: 0, y: 300, width: width, height: 600))!
        let scroll = ExtendedCaptureSession(mode: .scroll, screen: NSScreen.main!, selection: CGRect(x: 100, y: 100, width: width, height: 600), initial: first, captureFrame: { second })
        if ProcessInfo.processInfo.environment["HALODOCK_INTERACTIVE_PREVIEW"] != "1" {
            Task { @MainActor in
                do {
                    try await render(DocumentFilePreview(url: md).padding(20).background(Color(nsColor: .windowBackgroundColor)).modifier(HaloDockTheme()), path: directory.appendingPathComponent("markdown.png"))
                    try await render(DocumentFilePreview(url: pdf).padding(20).background(Color(nsColor: .windowBackgroundColor)).modifier(HaloDockTheme()), path: directory.appendingPathComponent("pdf.png"))
                    try await render(FeedbackView(), path: directory.appendingPathComponent("feedback.png"), size: CGSize(width: 600, height: 620))
                    let copiedText = try String(contentsOf: md, encoding: .utf8)
                    _ = store.add(text: copiedText, title: "收集的 Markdown 文本")
                    if let item = store.currentItems.first(where: { $0.kind == .text }) {
                        try await render(WorkItemPreview(store: store, item: item), path: directory.appendingPathComponent("collected-markdown.png"), size: CGSize(width: 640, height: 520))
                    }
                } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)) }
                try? FileManager.default.removeItem(at: temporary)
                app.terminate(nil)
            }
            app.run()
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: InteractionPreviewView(store: store, scroll: scroll, markdown: md, pdf: pdf, image: image)))
        window.title = "HaloDock 交互验证 · 专用测试资料"; window.isReleasedWhenClosed = false; window.center(); window.makeKeyAndOrderFront(nil)
        app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出验证", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")); item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
        app.run()
    }
}
