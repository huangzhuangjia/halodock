import SwiftUI

struct HaloDockSettingsView: View {
    @ObservedObject private var closedLid = ClosedLidState.shared
    @AppStorage("closedLidMinutes") private var closedLidMinutes = 60
    @ObservedObject private var updates = UpdateManager.shared
    @AppStorage("automaticallyCheckUpdates") private var automaticallyCheckUpdates = true
    @ObservedObject private var login = LoginItemState.shared
    @ObservedObject private var shortcuts = GlobalShortcuts.shared
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accent") private var accent = "coral"
    @State private var selection: SettingsPage?
    private var page: SettingsPage { selection ?? .general }

    init(initialPage: SettingsPage = .general) {
        _selection = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.title).font(.title2.bold())
                        Text(page.summary).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(24)
                if updates.isDownloading { updateProgress }
                Divider()
                Form { pageContent }
                    .formStyle(.grouped)
                    .id(page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 800, height: 620)
        .navigationTitle("HaloDock 设置")
        .modifier(HaloDockTheme())
        .onAppear {
            login.refresh()
            if updates.shouldShowUpdateResult || updates.isDownloading { selection = .updates }
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloDockShowUpdates)) { _ in selection = .updates }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandIcon(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HaloDock").font(.headline)
                    Text("偏好设置").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 16)
            List(selection: $selection) {
                Section("个人偏好") {
                    navigationRow(.general)
                    navigationRow(.appearance)
                    navigationRow(.shortcuts)
                }
                Section("工具") {
                    navigationRow(.capture)
                    navigationRow(.clipboard)
                    navigationRow(.awake)
                    navigationRow(.panel)
                    navigationRow(.workbench)
                    navigationRow(.dockPreview)
                }
                Section("应用") {
                    navigationRow(.permissions)
                    navigationRow(.updates)
                    navigationRow(.feedback)
                    navigationRow(.about)
                }
            }.listStyle(.sidebar)
            Text("版本 \(updates.currentVersion)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func navigationRow(_ destination: SettingsPage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: destination.symbol).frame(width: 20)
            Text(destination.title)
            Spacer(minLength: 0)
            if destination == .updates && (updates.availableRelease != nil || updates.hasPreparedUpdate) {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.accentColor)
                    .accessibilityLabel("有可用更新")
            }
        }
        .foregroundStyle(selection == destination ? Color.white : Color.primary)
        .padding(.vertical, 4).tag(destination)
    }

    private var updateProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("正在更新 HaloDock", systemImage: "arrow.down.circle").font(.headline)
                Spacer()
                Text("\(Int(updates.progress * 100))%").font(.callout.monospacedDigit())
            }
            ProgressView(value: updates.progress)
            Text(updates.message).font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.bottom, 20)
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .general:
            Section("启动与运行") {
                Toggle("登录 Mac 时启动 HaloDock", isOn: Binding(
                    get: { login.requested },
                    set: { enabled in Task { await login.setEnabled(enabled) } }
                ))
                .disabled(login.isChanging)
                Text(login.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("系统登录项设置") { login.openSystemSettings() }
                    .controlSize(.small)
                Text("保持唤醒会记住上次选择；定时唤醒只恢复尚未到期的会话。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .appearance:
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Picker("强调色", selection: $accent) {
                    Text("珊瑚橙").tag("coral")
                    Text("蓝色").tag("blue")
                    Text("绿色").tag("green")
                }
            }
        case .shortcuts, .clipboard:
            ToolPreferencesSections(category: page)
        case .panel:
            ScenePanelSettings()
            ToolPreferencesSections(category: .panel)
            Section { Button("恢复默认场景") { ScenePanel.shared.reset() } }
        case .dockPreview:
            DockPreviewSettings()
        case .workbench:
            Section("工作台与片段") {
                Text("按任务收集截图、识别文字和文件，导出 Markdown 或保存为快捷文本片段。所有内容保存在本机。")
                Button("打开工作台") { WorkbenchWindow.shared.show() }
                Text("截图行动卡和最近复制菜单可加入当前工作台；片段支持 {{日期}}、{{时间}}、{{剪贴板}}。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .awake:
            ToolPreferencesSections(category: .awake)
            Section("合盖保持运行") {
                Toggle("本次合盖会话", isOn: Binding(get: { closedLid.active }, set: { enabled in
                    Task { if enabled { await closedLid.enable(minutes: closedLidMinutes) } else { await closedLid.stop() } }
                }))
                .disabled(closedLid.isChanging)
                Picker("开启时长", selection: $closedLidMinutes) {
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                    Text("直到手动关闭").tag(0)
                }.disabled(closedLid.active || closedLid.isChanging)
                Text(closedLid.message)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("合盖模式会阻止系统睡眠；会话到期、退出 App、电池低于 20% 或温度过高时恢复原设置。请保持通风，不与其他合盖工具同时使用。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(closedLid.authorizationInstalled ? "重新配置授权" : "配置合盖授权") { closedLid.authorize() }
                        .disabled(closedLid.active || closedLid.isChanging)
                    if closedLid.authorizationInstalled {
                        Button("撤销合盖授权") { Task { await closedLid.removeAuthorization() } }
                            .disabled(closedLid.isChanging)
                    }
                }
                if closedLid.needsRestore {
                    Button("授权恢复睡眠") { closedLid.restoreWithAuthorization() }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .updates:
            Section("软件更新") {
                LabeledContent("当前版本", value: updates.currentVersion)
                Toggle("自动检查更新", isOn: $automaticallyCheckUpdates)
                HStack {
                    Button(updates.isChecking ? "正在检查…" : "检查更新") {
                        Task { await updates.check(interactive: true) }
                    }
                    .disabled(updates.isChecking || updates.isDownloading || updates.hasPreparedUpdate)
                    if updates.isChecking || updates.isDownloading {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if updates.availableRelease != nil || updates.hasPreparedUpdate {
                        Button(updates.isDownloading ? "正在更新…" : updates.hasPreparedUpdate ? "重启更新" : "立即更新") {
                            Task { await updates.downloadInstaller() }
                        }
                        .disabled(updates.isDownloading)
                    }
                }
                Text(updates.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("查看 GitHub Releases", destination: UpdateManager.releasesURL)
                    .font(.caption)
            }
        case .permissions:
            DockPreviewSettings()
            Section("权限") {
                LabeledContent("截图与标注", value: "需要屏幕录制")
                Button("打开屏幕录制权限设置") {
                    if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {NSWorkspace.shared.open(url)}
                }

                LabeledContent("清空废纸篓", value: "需要控制 Finder")
                Button("打开自动化权限设置") {
                    NSWorkspace.shared.open(FinderAutomation.settingsURL)
                }
                Text("在自动化中展开 HaloDock，允许 Finder。首次确认清空时，系统会请求授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .feedback:
            Section("反馈与跟进") {
                Text("在 GitHub Issues 统一记录问题和功能建议，可查看处理状态和对应的修复版本。")
                Button("填写问题反馈或功能建议") { FeedbackWindow.shared.show() }.buttonStyle(.borderedProminent)
                Link("查看已有问题", destination: FeedbackReport.issuesURL)
                Text("App 会帮你整理反馈草稿，可选择附带版本信息。下一步在 GitHub 登录并确认提交，反馈内容公开可见。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .about:
            Section {
                HStack(spacing: 16) {
                    BrandIcon(size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("HaloDock").font(.title.bold())
                        Text("把 Mac 的日常小事，收进菜单栏。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 10)
            }
            Section("关于当前版本") {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                Text("状态指标来自本机，每 2 秒更新。网络显示连接情况，不代表互联网速度。截图识字在本机处理。普通剪贴板记录退出后清空；主动固定的文字、图片和文件引用保存在本机。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .capture:
            Section("截图工作流") {
                LabeledContent("截图快捷键", value: shortcuts.bindings[.screenshot]?.display ?? "未设置")
                Button("调整截图快捷键") { selection = .shortcuts }
                Text("拖动选区查看像素尺寸，松手后直接使用底部工具栏。拖动边缘可调整范围，无需进入其他编辑页面。")
            }
            Section("原地编辑") {
                Label("画笔、矩形、箭头与文字标注", systemImage: "pencil.tip")
                Label("提取中英文，在当前截图内选择、修改和复制", systemImage: "text.viewfinder")
                Label("将带标注的截图置顶贴到桌面", systemImage: "pin")
                Label("行动卡：加入工作台、复制 Markdown、打开识别链接", systemImage: "square.stack.3d.up")
                Label("滚动截图：开始采集后缓慢滚动，自动拼接，完成后预览", systemImage: "scroll")
                Label("GIF：选区录制，3 秒倒计时，最长 15 秒", systemImage: "record.circle")
                Text("贴图可移动、缩放、调整透明度，最多同时 8 张；关闭窗口或退出 App 后释放。")
            }
            Section("操作提示") {
                Text("1–4 切换标注工具，⌘Z 撤销，⇧⌘Z 重做，⌘C 或回车复制，⌘S 保存，Esc 收起识字结果或取消截图。")
                Text("截图识字通过 Apple Vision 在本机处理，无需联网。首次截图需要屏幕录制权限。")
                Button("查看截图权限") { selection = .permissions }
            }
        }
    }
}
