import SwiftUI
import Combine

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { switch self { case .small: "小"; case .medium: "中"; case .large: "大" } }
}
enum StatusWidget: String, Codable, CaseIterable, Identifiable {
    case battery, memory, network, storage
    var id: String { rawValue }
    var title: String { switch self { case .battery: "电池"; case .memory: "内存"; case .network: "网络"; case .storage: "硬盘可用" } }
    var symbol: String { switch self { case .battery: "battery.75percent"; case .memory: "memorychip"; case .network: "wifi"; case .storage: "internaldrive" } }
}
struct WidgetConfiguration: Codable, Identifiable, Equatable {
    var widget: StatusWidget
    var size: WidgetSize = .medium
    var visible = true
    var id: String { widget.rawValue }
}
struct PanelScene: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var widgets = StatusWidget.allCases.map { WidgetConfiguration(widget: $0) }
    var actions = QuickAction.allCases.map(\.rawValue)
    var showClipboard = true
    var showWorkbench = true
}
private struct SceneData: Codable {
    var scenes: [PanelScene]
    var selected: UUID
}

@MainActor
final class ScenePanel: ObservableObject {
    static let shared = ScenePanel()
    @Published private var data: SceneData
    @Published var message: String?
    private let defaults: UserDefaults
    var scenes: [PanelScene] { data.scenes }
    var current: PanelScene { data.scenes.first { $0.id == data.selected } ?? data.scenes[0] }
    static func presets() -> [PanelScene] {
        let daily = PanelScene(name: "日常", symbol: "sun.max")
        var work = PanelScene(name: "工作", symbol: "desktopcomputer")
        work.widgets = [.init(widget: .memory, size: .large), .init(widget: .storage, size: .large), .init(widget: .network, size: .small), .init(widget: .battery, size: .small)]
        work.actions = ["screenshot", "awake", "closedLid", "focus"]
        var meeting = PanelScene(name: "会议", symbol: "person.2")
        meeting.widgets = [.init(widget: .battery, size: .small), .init(widget: .network, size: .small)]
        meeting.actions = ["focus", "awake", "screenshot"]; meeting.showClipboard = false
        var download = PanelScene(name: "下载", symbol: "arrow.down.circle")
        download.widgets = [.init(widget: .storage, size: .large), .init(widget: .network), .init(widget: .battery)]
        download.actions = ["awake", "closedLid"]; download.showClipboard = false
        return [daily, work, meeting, download]
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let presets = Self.presets()
        data = SceneData(scenes: presets, selected: presets[0].id)
        if let saved = defaults.data(forKey: "scenePanels"), let decoded = try? JSONDecoder().decode(SceneData.self, from: saved),
           !decoded.scenes.isEmpty, decoded.scenes.count <= 12, Set(decoded.scenes.map(\.id)).count == decoded.scenes.count,
           decoded.scenes.allSatisfy({ Set($0.widgets.map(\.widget)).count == $0.widgets.count && $0.widgets.count <= 4 }) {
            data = decoded
        } else {
            data.scenes[0].actions = QuickAction.ordered(defaults.string(forKey: "quickActionOrder") ?? "").filter { !QuickAction.hidden(defaults.string(forKey: "hiddenQuickActions") ?? "").contains($0.rawValue) }.map(\.rawValue)
        }
    }
    private func commit(_ next: SceneData) {
        do { let bytes = try JSONEncoder().encode(next); defaults.set(bytes, forKey: "scenePanels"); data = next; message = nil }
        catch { message = "场景保存失败：" + error.localizedDescription }
    }
    func select(_ id: UUID) { guard scenes.contains(where: { $0.id == id }) else { return }; var next = data; next.selected = id; commit(next) }
    func update(_ scene: PanelScene) {
        guard let index = data.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        var next = data; next.scenes[index] = scene; commit(next)
    }
    func setSize(_ widget: StatusWidget, _ size: WidgetSize) { var scene = current; if let i = scene.widgets.firstIndex(where: { $0.widget == widget }) { scene.widgets[i].size = size } else { scene.widgets.append(.init(widget: widget, size: size, visible: false)) }; update(scene) }
    func setVisible(_ widget: StatusWidget, _ value: Bool) {
        var scene = current
        if let i = scene.widgets.firstIndex(where: { $0.widget == widget }) { scene.widgets[i].visible = value }
        else { scene.widgets.append(.init(widget: widget, visible: value)) }
        update(scene)
    }
    func duplicate() {
        guard scenes.count < 12 else { message = "最多 12 个场景"; return }
        var copy = current; copy.id = UUID(); copy.name = String(copy.name.prefix(20)) + " 副本"
        var next = data; next.scenes.append(copy); next.selected = copy.id; commit(next)
    }
    func remove() { guard scenes.count > 1 else { return }; var next = data; next.scenes.removeAll { $0.id == next.selected }; next.selected = next.scenes[0].id; commit(next) }
    func reset() { let presets = Self.presets(); commit(.init(scenes: presets, selected: presets[0].id)) }
}

struct ScenePanelSettings: View {
    @ObservedObject var scenes: ScenePanel = .shared
    var body: some View {
        Section("当前场景") {
            Picker("场景", selection: Binding(get: { scenes.current.id }, set: scenes.select)) { ForEach(scenes.scenes) { Text($0.name).tag($0.id) } }
            TextField("名称", text: Binding(get: { scenes.current.name }, set: { var next = scenes.current; next.name = String($0.prefix(30)); scenes.update(next) }))
            HStack { Button("复制场景") { scenes.duplicate() }; Button("删除场景", role: .destructive) { scenes.remove() }.disabled(scenes.scenes.count == 1) }
            Text("切换场景只调整面板内容，不会自动开启唤醒或修改系统设置。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("状态组件") {
            ForEach(StatusWidget.allCases) { widget in
                HStack {
                    Toggle(widget.title, isOn: Binding(get: { scenes.current.widgets.first { $0.widget == widget }?.visible ?? false }, set: { scenes.setVisible(widget, $0) }))
                    Spacer()
                    Picker("\(widget.title)尺寸", selection: Binding(get: { scenes.current.widgets.first { $0.widget == widget }?.size ?? .medium }, set: { scenes.setSize(widget, $0) })) {
                        ForEach(WidgetSize.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 120).labelsHidden()
                }
            }
            Text("小：紧凑数值；中：图标、数值与进度条；大：占满一行并显示更多说明。网络表示连接状态。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("场景内容") {
            Toggle("显示最近复制", isOn: Binding(get: { scenes.current.showClipboard }, set: { var next = scenes.current; next.showClipboard = $0; scenes.update(next) }))
            Toggle("显示工作台和文本片段", isOn: Binding(get: { scenes.current.showWorkbench }, set: { var next = scenes.current; next.showWorkbench = $0; scenes.update(next) }))
            ForEach(QuickAction.allCases) { action in
                HStack {
                    Toggle(action.title, isOn: Binding(get: { scenes.current.actions.contains(action.rawValue) }, set: { enabled in
                        var next = scenes.current
                        if enabled { if !next.actions.contains(action.rawValue) { next.actions.append(action.rawValue) } }
                        else { next.actions.removeAll { $0 == action.rawValue } }
                        scenes.update(next)
                    }))
                    Spacer()
                    Button { move(action, -1) } label: { Image(systemName: "chevron.up") }.disabled(scenes.current.actions.first == action.rawValue || !scenes.current.actions.contains(action.rawValue)).help("上移")
                    Button { move(action, 1) } label: { Image(systemName: "chevron.down") }.disabled(scenes.current.actions.last == action.rawValue || !scenes.current.actions.contains(action.rawValue)).help("下移")
                }.controlSize(.small)
            }
            if let message = scenes.message { Text(message).foregroundStyle(.secondary) }
        }
    }
    private func move(_ action: QuickAction, _ offset: Int) {
        var next = scenes.current
        guard let i = next.actions.firstIndex(of: action.rawValue), next.actions.indices.contains(i + offset) else { return }
        next.actions.swapAt(i, i + offset); scenes.update(next)
    }
}

struct StatusWidgetCard: View {
    let config: WidgetConfiguration
    @ObservedObject var system: SystemState
    private var value: String {
        switch config.widget { case .battery: system.battery; case .memory: system.memory; case .network: system.network; case .storage: system.storage }
    }
    private var fraction: Double? {
        switch config.widget { case .memory: system.memoryFraction; case .storage: system.storageFreeFraction; case .battery: Double(system.battery.replacingOccurrences(of: "%", with: "")).map { $0 / 100 }; case .network: nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: config.size == .small ? 4 : 8) {
            HStack {
                Image(systemName: config.widget.symbol).foregroundStyle(Color.accentColor)
                Text(config.widget.title).foregroundStyle(.secondary)
                if config.size == .small { Spacer(minLength: 0); Text(value).fontWeight(.semibold).foregroundStyle(.primary) }
            }.font(.caption)
            if config.size != .small {
                HStack { Text(value).font(config.size == .large ? .title3.bold() : .callout.bold()); Spacer(); if config.widget == .storage, let fraction { Text("\(Int((fraction * 100).rounded()))% 可用").font(.caption).foregroundStyle(.secondary) } }
                if let fraction { ProgressView(value: min(1, max(0, fraction))).tint(config.widget == .storage ? .haloGreen : .accentColor).accessibilityLabel(config.widget == .memory ? "内存已用比例" : config.widget == .storage ? "硬盘可用比例" : "电池电量") }
                if config.size == .large { Text(config.widget == .memory ? "已用内存比例 · 不代表内存压力" : config.widget == .storage ? "剩余可用空间 / 磁盘总容量" : config.widget == .network ? "系统网络连接状态" : "当前电池电量").font(.caption2).foregroundStyle(.secondary) }
            }
        }.padding(config.size == .small ? 8 : 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
