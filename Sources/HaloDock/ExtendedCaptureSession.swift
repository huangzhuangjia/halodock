import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class ExtendedCaptureSession: ObservableObject {
    enum Mode { case scroll, gif }
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    @Published private(set) var recording = false
    @Published private(set) var completed = false
    @Published private(set) var count = 1
    @Published private(set) var elapsed = 0
    @Published private(set) var thumbnail: NSImage?
    let mode: Mode
    let screen: NSScreen
    let selection: CGRect
    private let screenFrame: CGRect
    private let captureFrame: (() async throws -> CGImage)?
    private let countdownSeconds: Int
    private let duration: TimeInterval
    private var result: CGImage
    private var last: CGImage
    private var gif: GIFWriter?
    private var task: Task<Void, Never>?
    private var panel: NSPanel?
    var onClose: (() -> Void)?
    var isWorking: Bool { busy || recording }
    var outputImage: CGImage { result }
    var gifURL: URL? { completed ? gif?.url : nil }

    init(mode: Mode, screen: NSScreen, selection: CGRect, initial: CGImage, captureFrame: (() async throws -> CGImage)? = nil, countdownSeconds: Int = 3, duration: TimeInterval = 15) {
        self.captureFrame = captureFrame; self.countdownSeconds = min(3, max(0, countdownSeconds)); self.duration = min(15, max(0.2, duration))
        self.mode = mode; self.screen = screen; self.selection = selection; screenFrame = screen.frame
        let normalized = CaptureImage.resized(initial, maxWidth: 1600) ?? initial
        result = normalized; last = normalized
        thumbnail = NSImage(cgImage: CaptureImage.resized(normalized, maxWidth: 280) ?? normalized, size: CGSize(width: normalized.width, height: normalized.height))
        message = mode == .scroll ? "在原窗口向下滚动约半屏，再点“添加下一屏”。选区需避开固定工具栏。" : "点击开始，3 秒后录制选区；最长 15 秒、最多 120 帧，不录制声音。"
    }
    func show() {
        let controller = NSHostingController(rootView: ExtendedCaptureControls(session: self))
        let window = NSPanel(contentViewController: controller)
        window.identifier = NSUserInterfaceItemIdentifier("HaloDockCaptureControls")
        window.title = mode == .scroll ? "HaloDock 滚动截图" : "HaloDock GIF"
        window.styleMask = [.titled, .utilityWindow]
        window.isReleasedWhenClosed = false; window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Place controls outside the selected area. They are also excluded by ScreenCaptureKit on 14+.
        let top = screen.frame.maxY - selection.minY
        let rect = window.frame
        let globalBottom = screen.frame.maxY - selection.maxY
        let y = globalBottom > screen.visibleFrame.minY + rect.height + 12 ? globalBottom - rect.height - 12 : min(screen.visibleFrame.maxY - rect.height, top + 12)
        window.setFrameOrigin(CGPoint(x: min(max(screen.visibleFrame.minX, screen.frame.minX + selection.minX), screen.visibleFrame.maxX - rect.width), y: max(screen.visibleFrame.minY, y)))
        panel = window; window.orderFrontRegardless()
    }
    private func frame() async throws -> CGImage {
        if let captureFrame { return try await captureFrame() }
        guard NSScreen.screens.contains(screen), screen.frame == screenFrame else { throw WorkError("显示器布局已变化，请重新选择选区") }
        // On 13 the fallback cannot exclude windows; hide our control strip during capture.
        if #unavailable(macOS 14.0) { panel?.orderOut(nil); try await Task.sleep(for: .milliseconds(100)) }
        defer { if #unavailable(macOS 14.0) { panel?.orderFrontRegardless() } }
        let image = try await DisplayCapture.image(screen: screen, excludingOwnWindows: true)
        guard let pixels = ScreenshotGeometry.pixels(for: selection, viewSize: screen.frame.size, imageSize: CGSize(width: image.width, height: image.height)), let cropped = image.cropping(to: pixels), let normalized = CaptureImage.resized(cropped, maxWidth: 1600) else { throw WorkError("选区捕获失败") }
        return normalized
    }
    func addPage(force: Bool = false) {
        guard mode == .scroll, !busy, !completed, count < 20 else { return }
        busy = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { busy = false }
            do {
                let next = try await frame()
                guard !Task.isCancelled else { return }
                if !force && ScrollStitcher.isDuplicate(last, next) { message = "画面没有变化，请先向下滚动。"; return }
                let overlap: Int
                if force { overlap = 0 }
                else {
                    let lastFrame = last
                    guard let matched = await Task.detached(operation: { ScrollStitcher.overlap(previous: lastFrame, next: next) }).value else {
                        message = "无法可靠匹配，请少滚一点重试，或在确认后使用“直接追加”。"; return
                    }
                    overlap = matched
                }
                let previous = result
                let combined = try await Task.detached { try ScrollStitcher.append(next, to: previous, overlap: overlap) }.value
                guard !Task.isCancelled else { return }
                result = combined; last = next; count += 1
                thumbnail = NSImage(cgImage: CaptureImage.resized(result, maxWidth: 280) ?? result, size: CGSize(width: result.width, height: result.height))
                message = "已拼接 \(count) 屏 · \(result.width) × \(result.height) px"
            } catch { message = error.localizedDescription }
        }
    }
    func startGIF() {
        guard mode == .gif, !busy, !recording, !completed else { return }
        busy = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for n in (0..<countdownSeconds).reversed() { message = "\(n + 1) 秒后开始录制选区…"; try await Task.sleep(for: .seconds(1)); try Task.checkCancellation() }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-\(UUID().uuidString).gif")
                gif = try GIFWriter(url: url)
                recording = true; busy = false; count = 0
                let began = Date()
                var lastTime = began
                while !Task.isCancelled && recording && Date().timeIntervalSince(began) < duration && count < 120 {
                    let image = try await frame()
                    try Task.checkCancellation()
                    let now = Date(), delay = max(0.125, now.timeIntervalSince(lastTime)); lastTime = now
                    try await gif?.add(image, delay: delay)
                    count += 1; elapsed = Int(now.timeIntervalSince(began))
                    message = "录制中 \(elapsed)s / 15s · \(count) 帧"
                    try await Task.sleep(for: .milliseconds(125))
                }
                if !Task.isCancelled { await finishGIF() }
            } catch is CancellationError { }
            catch { message = error.localizedDescription; recording = false; busy = false; cleanupGIF() }
        }
    }
    func stopGIF() { recording = false; busy = true; message = "正在生成 GIF…" }
    private func finishGIF() async {
        busy = true
        do { guard let gif else { throw WorkError("没有可保存的 GIF") }; try await gif.finish(); try Task.checkCancellation(); completed = true; recording = false; busy = false; message = "GIF 已生成 · \(count) 帧，选择保存或加入工作台。" }
        catch { recording = false; busy = false; message = error.localizedDescription; cleanupGIF() }
    }
    func save() {
        guard !busy, !recording else { return }
        if mode == .scroll {
            let doc = ScreenshotDocument(image: result)
            if doc.save() { message = "已保存长图" }
            else { message = doc.status }
        } else if completed, let gif {
            let save = NSSavePanel(); save.allowedContentTypes = [.gif]; save.nameFieldStringValue = "HaloDock-\(Int(Date().timeIntervalSince1970)).gif"
            guard save.runModal() == .OK, let url = save.url else { return }
            do { try Data(contentsOf: gif.url).write(to: url, options: .atomic); message = "GIF 已保存" }
            catch { message = "保存失败：" + error.localizedDescription }
        }
    }
    func copy() {
        guard mode == .scroll, !busy else { return }
        let doc = ScreenshotDocument(image: result); _ = doc.copy(); message = doc.status
    }
    func addToWorkbench() {
        guard !busy, !recording else { return }
        if mode == .scroll { _ = WorkbenchStore.shared.add(image: result, title: "滚动截图 · \(count) 屏") }
        else if completed, let gif, let data = try? Data(contentsOf: gif.url) { _ = WorkbenchStore.shared.addAsset(data, extension: "gif", kind: .gif, title: "GIF · \(count) 帧") }
        message = WorkbenchStore.shared.message ?? "请重试"
    }
    private func cleanupGIF() {
        guard let writer = gif else { return }
        gif = nil
        // The actor drains pending work before removing the temporary output.
        Task { await writer.discard() }
    }
    func close() { task?.cancel(); recording = false; busy = false; cleanupGIF(); panel?.close(); panel = nil; onClose?() }
}

private struct ExtendedCaptureControls: View {
    @ObservedObject var session: ExtendedCaptureSession
    @State private var confirmAppend = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(session.mode == .scroll ? "滚动截图" : "选区 GIF", systemImage: session.mode == .scroll ? "scroll" : "record.circle").font(.headline)
                Spacer()
                Button { session.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("取消并关闭")
            }
            Text(session.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if session.mode == .scroll {
                if let thumbnail = session.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 70)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("当前拼接长图预览")
                }
                HStack {
                    Button("添加下一屏") { session.addPage() }.disabled(session.busy || session.count >= 20).buttonStyle(.borderedProminent)
                    Button("直接追加…") { confirmAppend = true }.disabled(session.busy || session.count >= 20)
                    if session.busy { ProgressView().controlSize(.small) }
                }
                HStack { Button("复制长图") { session.copy() }; Button("保存 PNG") { session.save() }; Button("加入工作台") { session.addToWorkbench() } }.disabled(session.busy)
                Text("每次保留至少约 1/3 重叠；最多 20 屏、24000 像素高，动态内容可能无法匹配。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if session.completed {
                HStack { Button("保存 GIF") { session.save() }.buttonStyle(.borderedProminent); Button("加入工作台") { session.addToWorkbench() } }
            } else {
                HStack {
                    Button(session.recording ? "停止并生成" : session.busy ? "准备中…" : "开始录制") { if session.recording { session.stopGIF() } else { session.startGIF() } }
                        .buttonStyle(.borderedProminent).disabled(session.busy)
                    if session.recording { ProgressView(value: Double(session.elapsed), total: 15).frame(width: 120) }
                }
            }
        }.padding(16).frame(width: 390).modifier(HaloDockTheme())
        .confirmationDialog("直接追加不会去重，请确认下一屏没有重叠。", isPresented: $confirmAppend) { Button("直接追加") { session.addPage(force: true) } }
    }
}
