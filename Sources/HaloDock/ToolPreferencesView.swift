import SwiftUI

struct ToolPreferencesSections: View {
    var category: SettingsPage? = nil
    @ObservedObject private var shortcuts = GlobalShortcuts.shared
    @AppStorage("showMacStatus") private var showMacStatus = true
    @AppStorage("showQuickActions") private var showQuickActions = true
    @AppStorage("showStorage") private var showStorage = true
    @AppStorage("showRecentClipboard") private var showRecentClipboard = true
    @AppStorage("clipboardRetentionMinutes") private var retention = 60
    @AppStorage("wakeMinutes") private var wakeMinutes = 0

    var body: some View {
        if category == nil || category == .shortcuts {
            Section("全局快捷键") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(value: shortcuts.bindings[action]) { _ = shortcuts.set($0, for: action) }
                            .frame(width: 140, height: 28)
                            .help("点击后按下含 ⌘、⌃ 或 ⌥ 的组合键，Esc 取消")
                        Button { _ = shortcuts.set(nil, for: action) } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).help("停用该快捷键").accessibilityLabel("停用\(action.title)快捷键")
                    }
                }
                Text(shortcuts.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if category == nil || category == .awake {
            Section("唤醒倒计时") {
                Picker("默认唤醒时长", selection: $wakeMinutes) {
                    Text("直到手动关闭").tag(0)
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                }
                Text("下次开启时使用此时长。运行中可在菜单栏面板调整；到期自动关闭，重启 App 继续剩余时间。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if category == nil || category == .clipboard {
            Section("剪贴板") {
                Picker("自动清理未固定记录", selection: $retention) {
                    Text("15 分钟后").tag(15)
                    Text("1 小时后").tag(60)
                    Text("24 小时后").tag(1440)
                    Text("仅退出时清理").tag(0)
                }
                Text("支持文字、图片和文件，最多 50 条。普通记录仅保存在内存；主动固定的最多 10 条会保存在本机，不受自动清理影响。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("图片单张最多 8 MB；固定内容总大小最多 16 MB。密码工具标记为机密的内容会跳过。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if category == nil || category == .panel {
            Section("面板显示") {
                Toggle("显示 Mac 状态", isOn: $showMacStatus)
                Toggle("显示硬盘可用空间", isOn: $showStorage).disabled(!showMacStatus)
                Toggle("显示快捷操作", isOn: $showQuickActions)
                Toggle("显示最近复制", isOn: $showRecentClipboard)
            }
        }
    }
}
