import SwiftUI

struct HaloDockView: View {
    @ObservedObject var scenes: ScenePanel = .shared
    @ObservedObject var workbench: WorkbenchStore = .shared
    @ObservedObject private var closedLid = ClosedLidState.shared
    @AppStorage("closedLidMinutes") private var closedLidMinutes = 60
    @ObservedObject private var updates = UpdateManager.shared
    let openSettings: () -> Void
    @ObservedObject var system: SystemState
    let emptyTrash: () -> Void
    let takeScreenshot: () -> Void
    @ObservedObject private var shortcuts = GlobalShortcuts.shared
    @AppStorage("showMacStatus") private var showMacStatus = true
    @AppStorage("showQuickActions") private var showQuickActions = true
    @AppStorage("wakeMinutes") private var wakeMinutes = 0
    @AppStorage("showStorage") private var showStorage = true
    @AppStorage("showRecentClipboard") private var showRecentClipboard = true

    @State private var contentHeight: CGFloat = 620
    @State private var chromeHeight: CGFloat = 150
    private var scrollLimit: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        return max(0, min(620, (screen?.visibleFrame.height ?? 800) - chromeHeight - 64))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Picker("场景", selection: Binding(get: { scenes.current.id }, set: scenes.select)) {
                    ForEach(scenes.scenes) { scene in Label(scene.name, systemImage: scene.symbol).tag(scene.id) }
                }.labelsHidden().pickerStyle(.menu).padding(.top, 12)
                if updates.availableRelease != nil || updates.hasPreparedUpdate {
                    Button {
                        openSettings()
                        NotificationCenter.default.post(name: .haloDockShowUpdates, object: nil)
                    } label: {
                        Label(updates.hasPreparedUpdate ? "更新已准备好，点击重启更新" : "发现 \(updates.availableRelease?.tag_name ?? "新版本")，前往更新", systemImage: "arrow.down.circle")
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 14)
                }
                if updates.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(updates.message).lineLimit(2)
                            Spacer()
                            Text("\(Int(updates.progress * 100))%")
                        }.font(.caption)
                        ProgressView(value: updates.progress)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 10)
                }
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: PanelChromeHeight.self, value: geometry.size.height)
            })
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if showMacStatus { statusSummary }
                    if showQuickActions { quickActions }
                    if scenes.current.showWorkbench { workbenchSection }
                    if showRecentClipboard && scenes.current.showClipboard {
                        Divider()
                        ClipboardHistoryView(history: system.history)
                    }
                }
                .padding(.top, showMacStatus ? 0 : 16)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
                })
            }
            .frame(height: min(contentHeight, scrollLimit))
            footer
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PanelChromeHeight.self, value: geometry.size.height)
                })
        }
        .padding(20)
        .frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(PanelContentHeight.self) { contentHeight = $0 }
        .onPreferenceChange(PanelChromeHeight.self) { chromeHeight = $0 }
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
            Button { WorkbenchWindow.shared.show() } label: {
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("打开工作台与文本片段").accessibilityLabel("打开工作台与文本片段")
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

            let widgets = scenes.current.widgets.filter { $0.visible && (showStorage || $0.widget != .storage) }
            VStack(spacing: 8) {
                ForEach(widgetRows(widgets), id: \.first?.id) { row in
                    HStack(alignment: .top, spacing: 8) { ForEach(row) { config in StatusWidgetCard(config: config, system: system) } }
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

    private func widgetRows(_ widgets: [WidgetConfiguration]) -> [[WidgetConfiguration]] {
        var result: [[WidgetConfiguration]] = []
        for widget in widgets {
            if widget.size != .large, let last = result.last, last.count == 1, last[0].size == widget.size { result[result.count - 1].append(widget) }
            else { result.append([widget]) }
        }
        return result
    }

    private var workbenchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("工作台", systemImage: "square.stack.3d.up").font(.callout.weight(.semibold))
                Spacer()
                Button("打开") { WorkbenchWindow.shared.show() }.controlSize(.small)
            }
            Text("\(workbench.currentItems.count) 项收集 · \(workbench.snippets.count) 个文本片段").font(.caption).foregroundStyle(.secondary)
            if !workbench.snippets.isEmpty {
                Menu("复制文本片段") { ForEach(workbench.snippets.prefix(12)) { snippet in Button(snippet.title) { workbench.copySnippet(snippet) } } }.controlSize(.small)
            }
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷操作").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ForEach(scenes.current.actions.compactMap(QuickAction.init(rawValue:))) { action in
                quickAction(action)
                if action == .awake {
                    WakeDurationControl(minutes: Binding(get: { wakeMinutes }, set: { value in
                        wakeMinutes = value
                        if system.keepAwake { system.startWake(minutes: value) }
                    }))
                }
            }
            if closedLid.needsRestore {
                Button("授权恢复睡眠") { closedLid.restoreWithAuthorization() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }

    @ViewBuilder private func quickAction(_ action: QuickAction) -> some View {
        switch action {
        case .awake:
            ActionRow(
                title: "保持唤醒",
                detail: closedLid.active ? "合盖后继续运行" : system.wakeRemaining.isEmpty ? "让屏幕保持点亮" : "剩余 " + system.wakeRemaining,
                symbol: "sun.max",
                tint: .haloOrange,
                trailing: AnyView(
                    Toggle("保持唤醒", isOn: Binding(get: { system.keepAwake || closedLid.active }, set: { enabled in
                        if enabled { system.startWake(minutes: wakeMinutes) }
                        else { Task { if await closedLid.stop() { system.setKeepAwake(false) } } }
                    }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                )
            )
        case .closedLid:
            ActionRow(
                title: "合盖保持运行",
                detail: closedLid.active ? (closedLid.endsAt.map { "运行至 " + $0.formatted(date: .omitted, time: .shortened) } ?? "直到关闭或退出") : (closedLid.authorizationInstalled ? "已授权 · 本次会话使用" : "首次授权 · 本次会话使用"),
                symbol: "laptopcomputer",
                tint: .haloOrange,
                trailing: AnyView(
                    HStack {
                        if closedLid.isChanging { ProgressView().controlSize(.small) }
                        Toggle("合盖保持运行", isOn: Binding(get: { closedLid.active }, set: { enabled in
                            Task { if enabled { await closedLid.enable(minutes: closedLidMinutes) } else { await closedLid.stop() } }
                        }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(closedLid.isChanging)
                    }
                )
            )
        case .screenshot:
            ActionRow(
                title: "截取屏幕",
                detail: "识字 · 贴图 · 标注" + (shortcuts.bindings[.screenshot].map { " · " + $0.display } ?? ""),
                symbol: "rectangle.dashed.and.paperclip",
                tint: .haloBlue,
                trailing: AnyView(
                    Button("截图", action: takeScreenshot)
                        .controlSize(.small)
                )
            )
        case .trash:
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
        case .focus:
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
private struct PanelContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PanelChromeHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}
