import AppKit
import SwiftUI

struct ScrollCapturePlacement {
    static func frames(selection: CGRect, visible: CGRect) -> (toolbar: CGRect, preview: CGRect) {
        let previewWidth = min(184, visible.width - 24)
        let height = max(160, min(480, visible.height - 100))
        let rightSpace = visible.maxX - selection.maxX
        let leftSpace = selection.minX - visible.minX
        let x: CGFloat
        if rightSpace >= previewWidth + 20 { x = selection.maxX + 16 }
        else if leftSpace >= previewWidth + 20 { x = selection.minX - previewWidth - 16 }
        else { x = visible.maxX - previewWidth - 12 }
        let previewY = min(max(visible.minY + 12, selection.maxY - height), visible.maxY - height - 12)
        let preview = CGRect(x: x, y: previewY, width: previewWidth, height: height)
        let toolbarWidth = min(370, visible.width - 24), toolbarHeight: CGFloat = 54
        let toolbarX = min(max(visible.minX + 12, selection.midX - toolbarWidth / 2), visible.maxX - toolbarWidth - 12)
        let below = selection.minY - toolbarHeight - 12
        let toolbarY = below >= visible.minY + 12 ? below : min(visible.maxY - toolbarHeight - 12, selection.maxY + 12)
        return (CGRect(x: toolbarX, y: max(visible.minY + 12, toolbarY), width: toolbarWidth, height: toolbarHeight), preview)
    }
}

@MainActor
final class CaptureControlPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

struct ScrollCaptureToolbar: View {
    @ObservedObject var session: ExtendedCaptureSession
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(session.attention == nil ? session.confirmed ? Color.haloGreen : Color.haloOrange : Color.orange).frame(width: 6, height: 6)
            Text(session.confirmed ? session.resultFeedback ?? "已确认" : session.scrollPhase == .preview ? "采集已停止" : session.message)
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            if session.confirmed {
                Button { session.copy() } label: { Image(systemName: "doc.on.doc") }.help("复制长截图").accessibilityLabel("复制长截图")
                Button { session.save() } label: { Image(systemName: "square.and.arrow.down") }.help("保存 PNG").accessibilityLabel("保存长截图")
                WorkbenchDestinationMenu(title: "收集") { session.addToWorkbench(to: $0) }.fixedSize()
            } else {
                Text("\(session.outputImage.height) px").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Divider().frame(height: 22)
                Button { session.confirmScroll() } label: {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.haloOrange, in: RoundedRectangle(cornerRadius: 8))
                }.help("确认完成长截图").accessibilityLabel("确认完成长截图")
            }
            Button { session.close() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 28, height: 32)
            }.help(session.confirmed ? "关闭" : "取消截图（Esc）").accessibilityLabel(session.confirmed ? "关闭长截图" : "取消长截图")
        }
        .buttonStyle(.plain).padding(.horizontal, 12).frame(height: 54)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 1))
        .modifier(HaloDockTheme())
    }
}

struct ScrollCaptureThumbnail: View {
    @ObservedObject var session: ExtendedCaptureSession
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("长图预览").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(session.outputImage.height) px").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                if let image = session.thumbnail {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel("实时长图预览，当前高度 \(session.outputImage.height) 像素")
            if let attention = session.attention {
                Label(attention, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if session.scrollPhase == .paused { Button("重试采集") { session.retryScroll() }.controlSize(.small) }
            } else {
                HStack {
                    Text("\(session.count) 段").foregroundStyle(.secondary)
                    Spacer()
                    Text(session.confirmed ? "已完成" : "\(session.capturedFrames) 帧").foregroundStyle(session.confirmed ? Color.haloGreen : Color.haloOrange)
                }.font(.system(size: 9))
            }
            if !session.confirmed {
                Text("滚动自动采集 · ✓ 确认\nEsc 取消 · 上限 \(session.maximumScrollHeight) px")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).lineSpacing(3)
            }
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 1))
        .modifier(HaloDockTheme())
    }
}
