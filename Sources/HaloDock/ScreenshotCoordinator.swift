import AppKit
import ScreenCaptureKit
import ImageIO

@MainActor
final class ScreenshotCoordinator {
    private var overlays: [NSWindow] = []
    private var capturing=false
    private var extended: ExtendedCaptureSession?
    var hasActiveSession: Bool { capturing || !overlays.isEmpty || extended != nil }

    func start() {
        guard !hasActiveSession else {return}
        capturing=true
        Task { @MainActor in
            defer {capturing=false}
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                showPermissionHelp();return
            }
            do {
                let screens=NSScreen.screens
                var frames: [(NSScreen,CGImage)] = []
                if #available(macOS 14.0, *) {
                    let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                    for screen in screens {
                        guard let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                              let display=content.displays.first(where:{$0.displayID==id}) else {continue}
                        let filter=SCContentFilter(display:display,excludingWindows:[])
                        let configuration=SCStreamConfiguration()
                        configuration.width=Int(screen.frame.width*screen.backingScaleFactor)
                        configuration.height=Int(screen.frame.height*screen.backingScaleFactor)
                        configuration.showsCursor=false
                        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
                        frames.append((screen,image))
                    }
                } else {
                    for (index,screen) in screens.enumerated() {
                        let image=try await Self.legacyCapture(displayIndex:index+1)
                        frames.append((screen,image))
                    }
                }
                guard !frames.isEmpty else {throw CaptureFailure("未找到可截图的屏幕")}
                showSelection(frames)
            } catch {
                if !CGPreflightScreenCaptureAccess() {showPermissionHelp()}
                else {showError(error.localizedDescription)}
            }
        }
    }

    private static func legacyCapture(displayIndex:Int) async throws -> CGImage {
        try await Task.detached {
            let file=FileManager.default.temporaryDirectory.appendingPathComponent("HaloDock-\(UUID().uuidString).png")
            defer {try? FileManager.default.removeItem(at:file)}
            let process=Process()
            process.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture")
            process.arguments=["-x","-D",String(displayIndex),file.path]
            process.standardError=FileHandle.nullDevice
            try process.run();process.waitUntilExit()
            guard process.terminationStatus==0,
                  let source=CGImageSourceCreateWithURL(file as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {throw CaptureFailure("屏幕捕获失败，请检查屏幕录制权限")}
            return image
        }.value
    }

    private func showSelection(_ frames:[(NSScreen,CGImage)]) {
        for (screen,image) in frames {
            let window=ScreenshotOverlayWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            window.level = .screenSaver
            window.isOpaque=true
            window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            let selection=ScreenshotSelectionView(frame:CGRect(origin:.zero,size:screen.frame.size),image:image)
            selection.onExtendedCapture = { [weak self] mode, rect, image in
                guard let self else { return }
                self.closeSelection()
                let session = ExtendedCaptureSession(mode: mode, screen: screen, selection: rect, initial: image)
                session.onClose = { [weak self] in self?.extended = nil }
                self.extended = session
                session.show()
            }
            selection.onPin = { image, point in PinnedScreenshots.shared.show(image, at: point) }
            selection.onCancel={ [weak self] in self?.closeSelection() }
            window.contentView=selection
            overlays.append(window)
            window.orderFrontRegardless()
        }
        let point=NSEvent.mouseLocation
        let active=overlays.first(where:{$0.frame.contains(point)}) ?? overlays.first
        active?.makeKeyAndOrderFront(nil)
        if let view=active?.contentView {active?.makeFirstResponder(view)}
        NSApp.activate(ignoringOtherApps:true)
    }
    private func closeSelection() {
        for window in overlays {
            (window.contentView as? ScreenshotSelectionView)?.hideRecognition()
            window.orderOut(nil);window.close()
        }
        overlays.removeAll()
    }
    func shutdown() {
        extended?.close(); extended = nil
        closeSelection()
    }
    private func showPermissionHelp() {
        let alert=NSAlert()
        alert.messageText="需要屏幕录制权限"
        alert.informativeText="请在“系统设置 → 隐私与安全性 → 屏幕录制”中允许 HaloDock，按系统提示重新打开 App 后再截图。截图仅在本机处理。"
        alert.addButton(withTitle:"前往设置");alert.addButton(withTitle:"取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {NSWorkspace.shared.open(url)}
    }
    private func showError(_ message:String) {
        let alert=NSAlert();alert.messageText="无法截图";alert.informativeText=message;alert.addButton(withTitle:"好");alert.runModal()
    }
}

private final class ScreenshotOverlayWindow:NSWindow {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {true}
}
private struct CaptureFailure:LocalizedError {
    let errorDescription:String?
    init(_ message:String) {errorDescription=message}
}
