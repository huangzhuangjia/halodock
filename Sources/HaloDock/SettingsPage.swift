import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, capture, clipboard, awake, panel, workbench, permissions, updates, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "通用"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .capture: "截图与贴图"
        case .clipboard: "剪贴板"
        case .awake: "唤醒与合盖"
        case .panel: "场景与组件"
        case .workbench: "工作台与片段"
        case .permissions: "权限"
        case .updates: "软件更新"
        case .about: "关于 HaloDock"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .shortcuts: "keyboard"
        case .capture: "viewfinder"
        case .clipboard: "doc.on.clipboard"
        case .awake: "sun.max"
        case .panel: "rectangle.3.group"
        case .workbench: "square.stack.3d.up"
        case .permissions: "hand.raised"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
    var summary: String {
        switch self {
        case .general: "设置启动方式，让 HaloDock 随时就位。"
        case .appearance: "选择主题和强调色，让工具融入你的 Mac。"
        case .shortcuts: "用顺手的组合键，快速调用常用操作。"
        case .capture: "选取范围后，直接标注、识字或贴到桌面。"
        case .clipboard: "保留刚才复制的内容，管理固定与清理规则。"
        case .awake: "按需保持运行，明确掌握每一次唤醒会话。"
        case .panel: "场景、组件大小与常用操作，按你的习惯排列。"
        case .workbench: "收集当前任务需要的内容，保存可复用的文字。"
        case .permissions: "查看需要的系统权限，并前往授权。"
        case .updates: "获取新功能和修复，在 App 内完成更新。"
        case .about: "菜单栏里的轻量工具箱。"
        }
    }
}

extension Notification.Name {
    static let haloDockShowUpdates = Notification.Name("HaloDock.ShowUpdates")
}
