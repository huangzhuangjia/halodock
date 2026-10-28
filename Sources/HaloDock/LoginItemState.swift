import AppKit
import Combine
import ServiceManagement

@MainActor
final class LoginItemState: ObservableObject {
    static let shared = LoginItemState()
    @Published private(set) var requested: Bool
    @Published private(set) var message = ""
    @Published private(set) var isChanging = false
    private let defaults = UserDefaults.standard

    private init() {
        requested = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
    }

    private var installed: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let locations = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
        return locations.contains { path.hasPrefix($0) }
    }

    func configureOnLaunch() {
        guard installed else {
            message = "默认开启；安装到“应用程序”并启动后生效。"
            return
        }
        if defaults.bool(forKey: "loginItemConfigured") {
            refresh()
        } else {
            Task { await setEnabled(requested) }
        }
    }

    func refresh() {
        guard installed else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            requested = true
            message = "已开启，登录 Mac 后自动运行。"
        case .requiresApproval:
            requested = true
            message = "请在系统“登录项”中允许 HaloDock。"
        case .notRegistered:
            requested = false
            message = "已关闭开机启动。"
        case .notFound:
            message = "未找到登录项，请从“应用程序”重新打开。"
        @unknown default:
            message = "无法读取登录项状态。"
        }
        defaults.set(requested, forKey: "launchAtLogin")
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        guard installed else {
            requested = enabled
            defaults.set(enabled, forKey: "launchAtLogin")
            message = enabled ? "安装到“应用程序”并启动后自动开启。" : "已关闭开机启动。"
            return
        }
        isChanging = true
        defer { isChanging = false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else {
                try await SMAppService.mainApp.unregister()
            }
            defaults.set(true, forKey: "loginItemConfigured")
            refresh()
        } catch {
            message = "无法更新开机启动：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
