import AppKit
import SwiftUI

@MainActor
final class PinnedScreenshots {
    static let shared = PinnedScreenshots()
    private(set) var controllers: [UUID: PinnedScreenshotController] = [:]
    @discardableResult func show(_ image: CGImage, at origin: CGPoint? = nil) -> Bool {
        guard controllers.count < 8 else { return false }
        let id = UUID()
        let controller = PinnedScreenshotController(image: image)
        controller.onClose = { [weak self] in self?.controllers.removeValue(forKey: id) }
        controllers[id] = controller
        if let origin { controller.window?.setFrameTopLeftPoint(origin) }
        else { controller.window?.center() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return true
    }
    func closeAll() { for controller in Array(controllers.values) { controller.close() }; controllers.removeAll() }
}

@MainActor
final class PinnedScreenshotController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let captureDocument: ScreenshotDocument
    init(image: CGImage) {
        captureDocument = ScreenshotDocument(image: image)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 520, height: 380), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "HaloDock 贴图"
        panel.identifier = NSUserInterfaceItemIdentifier("HaloDockPinnedScreenshot")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 320, height: 180)
        super.init(window: panel)
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: PinnedScreenshotView(document: captureDocument, resize: { [weak self] scale in self?.resize(scale) }, opacity: { [weak panel] value in panel?.alphaValue = value }))
        resize(1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }
    private func resize(_ scale: CGFloat) {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? CGSize(width: 1000, height: 700)
        let logical = CGSize(width: captureDocument.size.width / 2 * scale, height: captureDocument.size.height / 2 * scale)
        let factor = min(1, (available.width - 40) / max(1, logical.width), (available.height - 100) / max(1, logical.height))
        window.setContentSize(CGSize(width: max(320, logical.width * factor), height: max(150, logical.height * factor + 54)))
    }
}

private struct PinnedScreenshotView: View {
    @ObservedObject var document: ScreenshotDocument
    let resize: (CGFloat) -> Void
    let opacity: (Double) -> Void
    @State private var alpha = 1.0
    @State private var scale: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSImage(cgImage: document.image, size: document.size))
                .resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("置顶截图，拖动标题栏移动，拖动边缘调整大小")
                .contextMenu {
                    Button("复制截图") { document.copy() }
                    Button("保存 PNG…") { document.save() }
                }
            Divider()
            HStack(spacing: 8) {
                Picker("缩放", selection: $scale) {
                    Text("50%").tag(CGFloat(0.5)); Text("100%").tag(CGFloat(1)); Text("200%").tag(CGFloat(2))
                }.labelsHidden().frame(width: 72).help("调整贴图显示大小")
                    .onChange(of: scale) { resize($0) }
                Image(systemName: "circle.lefthalf.filled").accessibilityHidden(true)
                Slider(value: $alpha, in: 0.3...1).frame(minWidth: 40, maxWidth: 80).accessibilityLabel("贴图不透明度")
                    .onChange(of: alpha) { opacity($0) }
                Spacer(minLength: 0)
                Button { document.copy() } label: { Image(systemName: "doc.on.doc") }.help("复制截图").accessibilityLabel("复制截图")
                Button { document.save() } label: { Image(systemName: "square.and.arrow.down") }.help("保存 PNG").accessibilityLabel("保存 PNG")
            }.controlSize(.small).padding(8)
            if document.status.hasPrefix("保存失败") || document.status.hasPrefix("复制失败") {
                Text(document.status).font(.caption).foregroundStyle(.red).padding(4)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(HaloDockTheme())
    }
}
