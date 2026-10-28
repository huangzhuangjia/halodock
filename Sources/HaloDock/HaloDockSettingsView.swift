import SwiftUI

struct HaloDockSettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @AppStorage("automaticallyCheckUpdates") private var automaticallyCheckUpdates = true
    @ObservedObject private var login = LoginItemState.shared
    @AppStorage("showStorage") private var showStorage = true
    @AppStorage("showRecentClipboard") private var showRecentClipboard = true
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accent") private var accent = "coral"

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    BrandIcon(size: 32)
                    Text("HaloDock").font(.title2.bold())
                }
                Text("菜单栏里的轻量工具箱")
                    .foregroundStyle(.secondary)
            }
            Section("软件更新") {
                LabeledContent("当前版本", value: updates.currentVersion)
                Toggle("自动检查更新", isOn: $automaticallyCheckUpdates)
                HStack {
                    Button(updates.isChecking ? "正在检查…" : "检查更新") {
                        Task { await updates.check(interactive: true) }
                    }
                    .disabled(updates.isChecking || updates.isDownloading)
                    if updates.isChecking || updates.isDownloading {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if updates.availableRelease != nil {
                        Button(updates.isDownloading ? "正在下载…" : "下载安装") {
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
                Text("保持唤醒会记住上次选择，并在下次启动时恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            Section("面板显示") {
                Toggle("显示硬盘可用空间", isOn: $showStorage)
                Toggle("显示最近复制", isOn: $showRecentClipboard)
                Text("修改自动保存，重新打开菜单栏面板即可查看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("权限") {
                LabeledContent("清空废纸篓", value: "需要控制 Finder")
                Button("打开自动化权限设置") {
                    NSWorkspace.shared.open(FinderAutomation.settingsURL)
                }
                Text("在自动化中展开 HaloDock，允许 Finder。首次确认清空时，系统会请求授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("关于当前版本") {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                Text("状态指标来自本机，每 2 秒更新。网络显示连接情况，不代表互联网速度。剪贴板仅记录运行期间复制的文本或文件，保存在内存中，退出后清空。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .navigationTitle("HaloDock 设置")
        .modifier(HaloDockTheme())
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}
