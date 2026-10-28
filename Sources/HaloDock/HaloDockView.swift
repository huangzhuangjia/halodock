import SwiftUI

struct HaloDockView: View {
    let openSettings: () -> Void
    @ObservedObject var system: SystemState
    let emptyTrash: () -> Void
    let takeScreenshot: () -> Void
    @AppStorage("showStorage") private var showStorage = true
    @AppStorage("showRecentClipboard") private var showRecentClipboard = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            statusSummary
            Divider().padding(.vertical, 16)
            quickActions
            if showRecentClipboard {
                Divider().padding(.vertical, 16)
                clipboardSection
            }
            footer
        }
        .padding(20)
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(HaloDockTheme())
        .onAppear { system.refresh() }
        .alert("操作未完成", isPresented: Binding(get: { system.actionError != nil }, set: { if !$0 { system.actionError = nil } })) {
            Button("好") { system.actionError = nil }
        } message: { Text(system.actionError ?? "") }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    BrandIcon(size: 24)
                    Text("HaloDock")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                Label("正常运行", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.haloGreen)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多设置")
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.haloGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac 实时状态")
                        .font(.title2.weight(.bold))
                    Text("每 2 秒更新 · 网络为连接状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatusMetric(symbol: "battery.75percent", label: "电池", value: system.battery, tint: .haloGreen)
                StatusMetric(symbol: "memorychip", label: "内存", value: system.memory, tint: .haloBlue)
                StatusMetric(symbol: "wifi", label: "网络", value: system.network, tint: .haloOrange)
                if showStorage {
                    StatusMetric(symbol: "internaldrive", label: "硬盘可用", value: system.storage, tint: .haloBlue)
                }
            }
        }
        .padding(14)
        .background(Color.haloGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.haloGreen.opacity(0.16), lineWidth: 1)
        }
        .padding(.top, 18)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷操作")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ActionRow(
                title: "保持唤醒",
                detail: "让屏幕保持点亮",
                symbol: "sun.max",
                tint: .haloOrange,
                trailing: AnyView(
                    Toggle("", isOn: Binding(get: { system.keepAwake }, set: { system.setKeepAwake($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                )
            )

            ActionRow(
                title: "截取屏幕",
                detail: "按钮：选区复制 · 系统快捷键：⌃⌘⇧4",
                symbol: "rectangle.dashed.and.paperclip",
                tint: .haloBlue,
                trailing: AnyView(
                    Button("截图", action: takeScreenshot)
                        .controlSize(.small)
                )
            )

            ActionRow(
                title: "清空废纸篓",
                detail: "永久删除废纸篓内容，操作前会确认",
                symbol: "trash",
                tint: .haloOrange,
                trailing: AnyView(
                    Button("清空", action: emptyTrash)
                        .controlSize(.small)
                        .help("确认后永久清空废纸篓")
                )
            )

            ActionRow(
                title: "专注模式",
                detail: "打开系统专注模式设置",
                symbol: "moon",
                tint: .haloGreen,
                trailing: AnyView(
                    Button("设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                )
            )
        }
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近复制")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if system.clipboard.isEmpty {
                Text("暂无记录，复制文本或文件后会显示在这里")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(system.clipboard.prefix(3)) { item in
                Button {
                    system.copy(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.symbol == "doc" ? Color.haloBlue : Color.haloOrange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openSettings) {
                Label("打开设置", systemImage: "gearshape")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .help("打开 HaloDock 设置")

            Button { NSApp.terminate(nil) } label: {
                Label("退出", systemImage: "power")
                    .font(.callout.weight(.medium))
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .help("退出 HaloDock；下次启动恢复保持唤醒的选择")
        }
        .controlSize(.large)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 18)
    }

}

private struct ActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var background: Color = .clear
    let trailing: AnyView

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatusMetric: View {
    let symbol: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.callout.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
    }
}

private extension Color {
    static let haloOrange = Color(red: 0.95, green: 0.33, blue: 0.20)
    static let haloGreen = Color(red: 0.12, green: 0.58, blue: 0.38)
    static let haloBlue = Color(red: 0.18, green: 0.40, blue: 0.85)
}
