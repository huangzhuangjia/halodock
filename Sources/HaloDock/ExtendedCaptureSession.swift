import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class ExtendedCaptureSession: ObservableObject {
    enum Mode { case scroll, gif }
    enum ScrollPhase { case ready, capturing, paused, preview }
    @Published private(set) var scrollPhase: ScrollPhase = .ready
    private var scrollTask: Task<Void, Never>?
    private var scrollGeneration = UUID()
    private var outline: NSWindow?
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    @Published private(set) var recording = false
    @Published private(set) var completed = false
    @Published private(set) var capturedFrames = 0
    @Published private(set) var count = 1
    @Published private(set) var elapsed = 0
    @Published private(set) var thumbnail: NSImage?
    let mode: Mode
    let screen: NSScreen
    let selection: CGRect
    private lazy var displaySource = DisplayCaptureSource(screen: screen)
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
    var isWorking: Bool { busy || recording || scrollPhase == .capturing }
    var outputImage: CGImage { result }
    var gifURL: URL? { completed ? gif?.url : nil }

    init(mode: Mode, screen: NSScreen, selection: CGRect, initial: CGImage, captureFrame: (() async throws -> CGImage)? = nil, countdownSeconds: Int = 3, duration: TimeInterval = 15) {
        self.captureFrame = captureFrame; self.countdownSeconds = min(3, max(0, countdownSeconds)); self.duration = min(15, max(0.2, duration))
        self.mode = mode; self.screen = screen; self.selection = selection; screenFrame = screen.frame
        let normalized = CaptureImage.resized(initial, maxWidth: 1600) ?? initial
        result = normalized; last = normalized
        thumbnail = NSImage(cgImage: CaptureImage.resized(normalized, maxWidth: 280) ?? normalized, size: CGSize(width: normalized.width, height: normalized.height))
        message = mode == .scroll ? "点“开始采集”，回到选区内连续向下滚动；滚动中持续采集拼接，完成时点“完成”。" : "点击开始，3 秒后录制选区；最长 15 秒、最多 120 帧，不录制声音。"
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
        panel = window; window.makeKeyAndOrderFront(nil)
        if mode == .scroll { showOutline() }
    }
    private func frame() async throws -> CGImage {
        if let captureFrame { return try await captureFrame() }
        guard NSScreen.screens.contains(screen), screen.frame == screenFrame else { throw WorkError("显示器布局已变化，请重新选择选区") }
        // On 13 the fallback cannot exclude windows; hide our control strip during capture.
        if #unavailable(macOS 14.0) { panel?.orderOut(nil); try await Task.sleep(for: .milliseconds(100)) }
        defer { if #unavailable(macOS 14.0) { panel?.orderFrontRegardless() } }
        let image = try await displaySource.image()
        guard let pixels = ScreenshotGeometry.pixels(for: selection, viewSize: screen.frame.size, imageSize: CGSize(width: image.width, height: image.height)), let cropped = image.cropping(to: pixels), let normalized = CaptureImage.resized(cropped, maxWidth: 1600) else { throw WorkError("选区捕获失败") }
        return normalized
    }
    private func showOutline() {
        let rect = CGRect(x: screen.frame.minX + selection.minX - 2, y: screen.frame.maxY - selection.maxY - 2, width: selection.width + 4, height: selection.height + 4)
        let border = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        border.identifier = NSUserInterfaceItemIdentifier("HaloDockCaptureControls")
        border.isReleasedWhenClosed = false; border.isOpaque = false; border.backgroundColor = .clear
        border.level = .floating; border.ignoresMouseEvents = true; border.hasShadow = false
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: CGRect(origin: .zero, size: rect.size)); view.wantsLayer = true
        view.layer?.borderWidth = 2; view.layer?.borderColor = NSColor.systemOrange.cgColor
        border.contentView = view; border.orderFrontRegardless(); outline = border
    }
    func startScroll() {
        guard mode == .scroll, !busy, scrollPhase != .capturing, scrollPhase != .preview, count < 120 else { return }
        scrollTask?.cancel()
        let generation = UUID(); scrollGeneration = generation
        scrollPhase = .capturing; message = "采集中 · 在橙色选区内连续向下滚动，滚动中持续采集拼接。"
        outline?.orderFrontRegardless()
        scrollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.scrollPhase == .capturing && generation == self.scrollGeneration {
                do {
                    let next = try await self.frame()
                    try Task.checkCancellation()
                    guard self.scrollPhase == .capturing, generation == self.scrollGeneration else { return }
                    self.capturedFrames += 1
                    self.busy = true
                    _ = try await self.merge(next, force: false, automatic: true, generation: generation)
                    guard generation == self.scrollGeneration, !Task.isCancelled else { return }
                    self.busy = false
                    if self.count >= 120 || self.result.height >= 24000 {
                        self.scrollPhase = .preview; self.outline?.orderOut(nil)
                        self.message = "已达到长图上限，请预览并保存。"; return
                    }
                    try await Task.sleep(for: .milliseconds(80))
                } catch is CancellationError { return }
                catch {
                    guard generation == self.scrollGeneration else { return }
                    self.busy = false; self.scrollPhase = .paused
                    self.message = "采集已暂停：" + error.localizedDescription; return
                }
            }
        }
    }
    func pauseScroll() {
        guard scrollPhase == .capturing else { return }
        scrollGeneration = UUID(); scrollTask?.cancel(); scrollTask = nil
        scrollPhase = .paused; busy = false
        message = "已暂停 · 可以调整页面位置，再继续采集。"
    }
    func finishScroll() {
        guard mode == .scroll else { return }
        scrollGeneration = UUID(); scrollTask?.cancel(); scrollTask = nil
        task?.cancel(); busy = false; scrollPhase = .preview; outline?.orderOut(nil)
        message = "长图已完成 · \(result.width) × \(result.height) px，可以预览、保存或选择工作台。"
    }
    func addPage(force: Bool = false) {
        guard mode == .scroll, !busy, scrollPhase != .capturing, scrollPhase != .preview, count < 120 else { return }
        busy = true
        let generation = scrollGeneration
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == scrollGeneration { busy = false } }
            do {
                let next = try await frame(); try Task.checkCancellation()
                _ = try await merge(next, force: force, automatic: false, generation: generation)
            } catch { if generation == scrollGeneration { message = error.localizedDescription } }
        }
    }
    private func merge(_ next: CGImage, force: Bool, automatic: Bool, generation: UUID) async throws -> Bool {
        guard generation == scrollGeneration, !Task.isCancelled else { return false }
        if !force && ScrollStitcher.isDuplicate(last, next) {
            if !automatic { message = "画面没有变化，请先向下滚动。" }
            return false
        }
        let overlap: Int
        if force { overlap = 0 }
        else {
            let lastFrame = last
            guard let matched = await Task.detached(operation: { ScrollStitcher.overlap(previous: lastFrame, next: next) }).value else {
                if generation == scrollGeneration { message = "尚未拼接：画面有变化，但未找到可靠重叠。请向上退一点，再慢慢下滚；已有长图保留。" }
                return false
            }
            overlap = matched
            // Wait until enough new content accumulates; tiny motion should not consume the frame limit.
            if automatic && next.height - overlap < max(8, next.height / 40) { return false }
        }
        let previous = result
        let combined = try await Task.detached { try ScrollStitcher.append(next, to: previous, overlap: overlap) }.value
        guard generation == scrollGeneration, !Task.isCancelled else { return false }
        result = combined; last = next; count += 1
        thumbnail = NSImage(cgImage: CaptureImage.resized(result, maxWidth: 280) ?? result, size: CGSize(width: result.width, height: result.height))
        message = "已拼接 \(count) 段 · \(result.width) × \(result.height) px · 继续滚动或点完成"
        return true
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
        guard !busy, !recording, scrollPhase != .capturing else { return }
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
        guard mode == .scroll, !busy, scrollPhase != .capturing else { return }
        let doc = ScreenshotDocument(image: result); _ = doc.copy(); message = doc.status
    }
    func addToWorkbench(to destination: UUID) {
        guard !busy, !recording, scrollPhase != .capturing else { return }
        if mode == .scroll { _ = WorkbenchStore.shared.add(image: result, title: "滚动截图 · \(count) 屏", to: destination) }
        else if completed, let gif, let data = try? Data(contentsOf: gif.url) { _ = WorkbenchStore.shared.addAsset(data, extension: "gif", kind: .gif, title: "GIF · \(count) 帧", to: destination) }
        message = WorkbenchStore.shared.message ?? "请重试"
    }
    private func cleanupGIF() {
        guard let writer = gif else { return }
        gif = nil
        // The actor drains pending work before removing the temporary output.
        Task { await writer.discard() }
    }
    func close() {
        scrollGeneration = UUID(); scrollTask?.cancel(); scrollTask = nil
        task?.cancel(); recording = false; busy = false; scrollPhase = .preview
        cleanupGIF(); outline?.close(); outline = nil; panel?.close(); panel = nil; onClose?()
    }
}

private struct ExtendedCaptureControls: View {
    @ObservedObject var session: ExtendedCaptureSession
    @State private var confirmAppend = false
    @State private var expandedPreview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(session.mode == .scroll ? "滚动截图" : "选区 GIF", systemImage: session.mode == .scroll ? "scroll" : "record.circle").font(.headline)
                Spacer()
                Button { session.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("取消并关闭")
            }
            Text(session.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if session.mode == .scroll {
                if session.scrollPhase == .preview {
                    Button { expandedPreview = true } label: {
                        HStack {
                            if let thumbnail = session.thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 65, height: 90) }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("预览完整长图").fontWeight(.medium)
                                Text("\(session.outputImage.width) × \(session.outputImage.height) px · \(session.count) 段").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }.padding(10)
                    }.buttonStyle(.plain).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("复制") { session.copy() }
                        Button("保存 PNG") { session.save() }.buttonStyle(.borderedProminent)
                        WorkbenchDestinationMenu { session.addToWorkbench(to: $0) }
                    }.disabled(session.busy)
                } else {
                    HStack(spacing: 12) {
                        if let thumbnail = session.thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 48, height: 64) }
                        VStack(alignment: .leading, spacing: 5) {
                            Label(session.scrollPhase == .capturing ? "正在自动拼接" : session.scrollPhase == .paused ? "采集已暂停" : "准备开始", systemImage: session.scrollPhase == .capturing ? "record.circle" : "scroll")
                            Text("\(session.outputImage.height) px 高 · \(session.count) 段 · 已读取 \(session.capturedFrames) 帧").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        if session.scrollPhase == .capturing {
                            Button("暂停") { session.pauseScroll() }
                            Button("完成") { session.finishScroll() }.buttonStyle(.borderedProminent)
                        } else {
                            Button(session.scrollPhase == .paused ? "继续采集" : "开始采集") { session.startScroll() }.buttonStyle(.borderedProminent)
                            Button("完成") { session.finishScroll() }
                            Menu("更多") {
                                Button("手动补一屏") { session.addPage() }
                                Button("不去重追加…") { confirmAppend = true }
                            }.disabled(session.busy)
                        }
                    }
                    Text("在原窗口连续向下滚动，无需逐屏停顿或点击。可随时暂停；最多 120 段、24000 像素高。").font(.caption2).foregroundStyle(.secondary)
                }
            } else if session.completed {
                HStack { Button("保存 GIF") { session.save() }.buttonStyle(.borderedProminent); WorkbenchDestinationMenu { session.addToWorkbench(to: $0) } }
            } else {
                HStack {
                    Button(session.recording ? "停止并生成" : session.busy ? "准备中…" : "开始录制") { if session.recording { session.stopGIF() } else { session.startGIF() } }
                        .buttonStyle(.borderedProminent).disabled(session.busy)
                    if session.recording { ProgressView(value: Double(session.elapsed), total: 15).frame(width: 120) }
                }
            }
        }.padding(16).frame(width: 390).modifier(HaloDockTheme())
        .confirmationDialog("直接追加不会去重，请确认下一屏没有重叠。", isPresented: $confirmAppend) { Button("直接追加") { session.addPage(force: true) } }
        .sheet(isPresented: $expandedPreview) {
            VStack(spacing: 12) {
                HStack { Text("长图预览").font(.headline); Spacer(); Button("完成") { expandedPreview = false } }
                ScrollView { Image(nsImage: NSImage(cgImage: session.outputImage, size: CGSize(width: session.outputImage.width, height: session.outputImage.height))).resizable().scaledToFit().frame(width: 580) }
            }.padding(16).frame(width: 620, height: 540).modifier(HaloDockTheme())
        }
    }
}
