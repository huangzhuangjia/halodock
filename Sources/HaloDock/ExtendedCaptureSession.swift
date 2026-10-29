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
    private var unchangedFrames = 0
    private var unmatchedFrames = 0
    private var mismatchSince: Date?
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
    private var previewPanel: NSPanel?
    private var localKeys: Any?
    private var globalKeys: Any?
    private var closed = false
    @Published private(set) var attention: String?
    @Published private(set) var confirmed = false
    @Published private(set) var resultFeedback: String?
    var onConfirmed: ((CGImage) -> Void)?
    var onClose: (() -> Void)?
    var isWorking: Bool { busy || recording || scrollPhase == .capturing }
    var outputImage: CGImage { result }
    var maximumScrollHeight: Int { ScrollCaptureLimits.maximumHeight(width: result.width) }
    var gifURL: URL? { completed ? gif?.url : nil }

    init(mode: Mode, screen: NSScreen, selection: CGRect, initial: CGImage, captureFrame: (() async throws -> CGImage)? = nil, countdownSeconds: Int = 3, duration: TimeInterval = 15) {
        self.captureFrame = captureFrame; self.countdownSeconds = min(3, max(0, countdownSeconds)); self.duration = min(15, max(0.2, duration))
        self.mode = mode; self.screen = screen; self.selection = selection; screenFrame = screen.frame
        let normalized = CaptureImage.resized(initial, maxWidth: 1600) ?? initial
        result = normalized; last = normalized
        thumbnail = NSImage(cgImage: CaptureImage.resized(normalized, maxWidth: 280) ?? normalized, size: CGSize(width: normalized.width, height: normalized.height))
        message = mode == .scroll ? "滚动即采集 · 点击 ✓ 确认 · Esc 取消" : "点击开始，3 秒后录制选区；最长 15 秒、最多 120 帧，不录制声音。"
    }
    func show() {
        guard !closed else { return }
        if mode == .scroll { showScrollInterface(); return }
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
    private func showScrollInterface() {
        let controller = NSHostingController(rootView: ScrollCaptureToolbar(session: self))
        controller.sizingOptions = []
        let controls = CaptureControlPanel(contentViewController: controller)
        controls.identifier = NSUserInterfaceItemIdentifier("HaloDockCaptureControls")
        controls.styleMask = [.borderless, .nonactivatingPanel]
        controls.isReleasedWhenClosed = false; controls.level = .floating
        controls.hidesOnDeactivate = false; controls.isOpaque = false; controls.backgroundColor = .clear
        controls.hasShadow = true; controls.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controls.onEscape = { [weak self] in self?.close() }
        controls.setContentSize(CGSize(width: 370, height: 54))
        panel = controls

        let previewController = NSHostingController(rootView: ScrollCaptureThumbnail(session: self))
        previewController.sizingOptions = []
        let preview = CaptureControlPanel(contentViewController: previewController)
        preview.identifier = NSUserInterfaceItemIdentifier("HaloDockCaptureControls")
        preview.styleMask = [.borderless, .nonactivatingPanel]
        preview.isReleasedWhenClosed = false; preview.level = .floating
        preview.hidesOnDeactivate = false; preview.isOpaque = false; preview.backgroundColor = .clear
        preview.hasShadow = true; preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        preview.onEscape = { [weak self] in self?.close() }
        let area = CGRect(x: screenFrame.minX + selection.minX, y: screenFrame.maxY - selection.maxY, width: selection.width, height: selection.height)
        let placement = ScrollCapturePlacement.frames(selection: area, visible: screen.visibleFrame)
        preview.setContentSize(placement.preview.size)
        preview.setFrame(placement.preview, display: true)
        controls.setFrame(placement.toolbar, display: true)
        previewPanel = preview
        showOutline()
        controls.orderFrontRegardless(); preview.orderFrontRegardless()
        installKeys()
        // Start observing immediately; no button or synthetic scrolling is needed.
        startScroll()
    }
    private func installKeys() {
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.mode == .scroll, !self.closed else { return event }
            if event.keyCode == 53 { self.close(); return nil }
            return event
        }
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close() }
        }
    }
    private func removeKeys() {
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }
        localKeys = nil; globalKeys = nil
    }
    func confirmScroll() {
        guard mode == .scroll, !closed, !confirmed else { return }
        if scrollPhase != .preview { finishScroll() }
        confirmed = true
        message = "长截图已确认"
        onConfirmed?(result)
    }
    func retryScroll() {
        guard !closed, scrollPhase == .paused else { return }
        attention = nil; startScroll()
    }
    private func frame() async throws -> CGImage {
        if let captureFrame { return try await captureFrame() }
        guard NSScreen.screens.contains(screen), screen.frame == screenFrame else { throw WorkError("显示器布局已变化，请重新选择选区") }
        // On 13 the fallback cannot exclude windows; hide our control strip during capture.
        if #unavailable(macOS 14.0) {
            panel?.orderOut(nil); previewPanel?.orderOut(nil); outline?.orderOut(nil)
            try await Task.sleep(for: .milliseconds(100))
        }
        defer { if #unavailable(macOS 14.0), !closed {
            panel?.orderFrontRegardless(); previewPanel?.orderFrontRegardless()
            if scrollPhase == .capturing { outline?.orderFrontRegardless() }
        } }
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
    private func endAtLimit(_ reason: String) {
        scrollPhase = .preview; busy = false; outline?.orderOut(nil)
        attention = reason + "。已停止采集，内容已保留；点击 ✓ 确认后保存，可从当前位置另截一张。"
        message = "已达长度上限"
    }
    func startScroll() {
        guard !closed, mode == .scroll else { return }
        if let reason = ScrollCaptureLimits.stopReason(width: result.width, height: result.height, count: count) { endAtLimit(reason); return }
        mismatchSince = nil
        guard mode == .scroll, !busy, scrollPhase != .capturing, scrollPhase != .preview, count < 120 else { return }
        scrollTask?.cancel()
        let generation = UUID(); scrollGeneration = generation
        scrollPhase = .capturing; attention = nil
        message = "滚动即采集"
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
                    if self.scrollPhase == .preview { return }
                    if let reason = ScrollCaptureLimits.stopReason(width: self.result.width, height: self.result.height, count: self.count) {
                        self.endAtLimit(reason); return
                    }
                    try await Task.sleep(for: .milliseconds(80))
                } catch is CancellationError { return }
                catch {
                    guard generation == self.scrollGeneration else { return }
                    self.busy = false; self.scrollPhase = .paused
                    self.attention = "采集已暂停：" + error.localizedDescription + "。已有内容保留，可重试或点击 ✓ 确认。"
                    self.message = "采集异常"; return
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
        message = "长图已完成 · \(result.width) × \(result.height) px"
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
            unchangedFrames += 1
            if !automatic || unchangedFrames >= 12 { message = count > 1 ? "继续滚动或点 ✓ 完成" : "在选区内滚动即可" }
            return false
        }
        unchangedFrames = 0
        let overlap: Int
        if force { overlap = 0 }
        else {
            let lastFrame = last
            guard let matched = await Task.detached(operation: { ScrollStitcher.overlap(previous: lastFrame, next: next) }).value else {
                if generation == scrollGeneration {
                    unmatchedFrames += 1
                    if mismatchSince == nil { mismatchSince = Date() }
                    message = "等待匹配滚动内容"
                    if Date().timeIntervalSince(mismatchSince ?? Date()) >= 3 {
                        attention = "暂未找到可靠重叠。请向上退一点再下滚，或只框选内层滚动内容；已有长图保留，采集会继续尝试。"
                    }
                }
                return false
            }
            overlap = matched
            // Wait until enough new content accumulates; tiny motion should not consume the frame limit.
            if automatic && next.height - overlap < max(8, next.height / 40) {
                message = "正在采集，滚动位移较小；继续向下滚动即可。"
                return false
            }
        }
        let nextHeight = result.height + next.height - overlap
        if nextHeight > maximumScrollHeight {
            endAtLimit(result.width > 0 && ScrollCaptureLimits.pixels / result.width < 24000
                ? "下一段会超出 4000 万像素容量上限（当前宽度最多 \(maximumScrollHeight) px 高）"
                : "下一段会超出 24000 px 高度上限")
            return false
        }
        let previous = result
        let combined = try await Task.detached { try ScrollStitcher.append(next, to: previous, overlap: overlap) }.value
        guard generation == scrollGeneration, !Task.isCancelled else { return false }
        unmatchedFrames = 0; mismatchSince = nil; attention = nil
        result = combined; last = next; count += 1
        thumbnail = NSImage(cgImage: CaptureImage.resized(result, maxWidth: 280) ?? result, size: CGSize(width: result.width, height: result.height))
        message = "滚动采集中"
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
            if doc.save() { message = "已保存长图"; resultFeedback = "已保存" }
            else if doc.status.hasPrefix("保存失败") || doc.status.hasPrefix("无法生成") { message = doc.status; resultFeedback = "保存失败"; attention = doc.status }
            panel?.orderFrontRegardless()
        } else if completed, let gif {
            let save = NSSavePanel(); save.allowedContentTypes = [.gif]; save.nameFieldStringValue = "HaloDock-\(Int(Date().timeIntervalSince1970)).gif"
            guard save.runModal() == .OK, let url = save.url else { return }
            do { try Data(contentsOf: gif.url).write(to: url, options: .atomic); message = "GIF 已保存" }
            catch { message = "保存失败：" + error.localizedDescription }
        }
    }
    func copy() {
        guard mode == .scroll, !busy, scrollPhase != .capturing else { return }
        let doc = ScreenshotDocument(image: result)
        let success = doc.copy(); message = doc.status
        resultFeedback = success ? "已复制" : "复制失败"
        if !success { attention = doc.status }
    }
    func addToWorkbench(to destination: UUID) {
        guard !busy, !recording, scrollPhase != .capturing else { return }
        if mode == .scroll { _ = WorkbenchStore.shared.add(image: result, title: "滚动截图 · \(count) 屏", to: destination) }
        else if completed, let gif, let data = try? Data(contentsOf: gif.url) { _ = WorkbenchStore.shared.addAsset(data, extension: "gif", kind: .gif, title: "GIF · \(count) 帧", to: destination) }
        message = WorkbenchStore.shared.message ?? "请重试"
        resultFeedback = message.hasPrefix("已加入") ? "已收集" : "收集失败"
        if !message.hasPrefix("已加入") { attention = message }
    }
    private func cleanupGIF() {
        guard let writer = gif else { return }
        gif = nil
        // The actor drains pending work before removing the temporary output.
        Task { await writer.discard() }
    }
    func close() {
        guard !closed else { return }; closed = true
        removeKeys()
        scrollGeneration = UUID(); scrollTask?.cancel(); scrollTask = nil
        task?.cancel(); recording = false; busy = false; scrollPhase = .preview
        cleanupGIF(); outline?.close(); outline = nil; panel?.close(); panel = nil
        previewPanel?.close(); previewPanel = nil
        let callback = onClose; onClose = nil; callback?()
    }
}

private struct ExtendedCaptureControls: View {
    @ObservedObject var session: ExtendedCaptureSession
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("选区 GIF", systemImage: "record.circle").font(.headline)
                Spacer()
                Button { session.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("取消并关闭")
            }
            Text(session.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if session.completed {
                HStack { Button("保存 GIF") { session.save() }.buttonStyle(.borderedProminent); WorkbenchDestinationMenu { session.addToWorkbench(to: $0) } }
            } else {
                HStack {
                    Button(session.recording ? "停止并生成" : session.busy ? "准备中…" : "开始录制") { if session.recording { session.stopGIF() } else { session.startGIF() } }
                        .buttonStyle(.borderedProminent).disabled(session.busy)
                    if session.recording { ProgressView(value: Double(session.elapsed), total: 15).frame(width: 120) }
                }
            }
        }.padding(16).frame(width: 390).modifier(HaloDockTheme())
    }
}
