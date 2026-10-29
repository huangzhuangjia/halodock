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
    static func presets() -> [PanelScene] { [PanelScene(name: "面板", symbol: "desktopcomputer")] }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let presets = Self.presets()
        data = SceneData(scenes: presets, selected: presets[0].id)
        if let saved = defaults.data(forKey: "scenePanels"), let decoded = try? JSONDecoder().decode(SceneData.self, from: saved),
           !decoded.scenes.isEmpty, decoded.scenes.count <= 12, Set(decoded.scenes.map(\.id)).count == decoded.scenes.count,
           decoded.scenes.allSatisfy({ Set($0.widgets.map(\.widget)).count == $0.widgets.count && $0.widgets.count <= 4 }) {
            // Adopt the selected layout from older multi-scene preferences.
            let chosen = decoded.scenes.first { $0.id == decoded.selected } ?? decoded.scenes[0]
            data = SceneData(scenes: [chosen], selected: chosen.id)
        } else {
            data.scenes[0].actions = QuickAction.ordered(defaults.string(forKey: "quickActionOrder") ?? "").filter { !QuickAction.hidden(defaults.string(forKey: "hiddenQuickActions") ?? "").contains($0.rawValue) }.map(\.rawValue)
        }
    }
    private func commit(_ next: SceneData) {
        do { let bytes = try JSONEncoder().encode(next); defaults.set(bytes, forKey: "scenePanels"); data = next; message = nil }
        catch { message = "面板保存失败：" + error.localizedDescription }
    }
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
    func reset() { let presets = Self.presets(); commit(.init(scenes: presets, selected: presets[0].id)) }
}

struct ScenePanelSettings: View {
    @ObservedObject var scenes: ScenePanel = .shared
    var body: some View {
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
        Section("快捷操作与内容") {
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
    private var detail: String {
        switch config.widget {
        case .battery: fraction == nil ? "电池状态不可用" : "当前电量"
        case .memory: fraction == nil ? "暂不可用" : "已用内存"
        case .network: "网络连接状态"
        case .storage: fraction.map { "剩余 \(Int(($0 * 100).rounded()))% 空间" } ?? "暂不可用"
        }
    }
    private var tint: Color {
        switch config.widget {
        case .battery, .network: .haloGreen
        case .memory: .haloBlue
        case .storage: .haloOrange
        }
    }
    private var progressLabel: String {
        switch config.widget {
        case .memory: "内存已用比例"
        case .storage: "硬盘可用比例"
        default: "电池电量"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: config.widget.symbol).foregroundStyle(tint).frame(width: 15)
                Text(config.widget.title).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if config.size == .small {
                    Text(value).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                }
            }.font(.system(size: 11, weight: .medium))

            if config.size != .small {
                Text(value)
                    .font(.system(size: config.size == .large ? 23 : 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 8)
                Spacer(minLength: 6)
                if let fraction {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(tint.opacity(0.10))
                            Capsule().fill(tint).frame(width: geometry.size.width * min(1, max(0, fraction)))
                        }
                    }
                    .frame(height: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(progressLabel)
                    .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded()))%")
                } else {
                    Color.clear.frame(height: 4).accessibilityHidden(true)
                }
                Text(detail)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).padding(.top, 6)
                if config.size == .large {
                    Text(config.widget == .memory ? "本机实时统计 · 不代表内存压力" : config.widget == .storage ? "可用容量 / 磁盘总容量" : config.widget == .network ? "连接状态不代表互联网速度" : "本机实时电池信息")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).padding(.top, 5)
                }
            }
        }
        .padding(config.size == .small ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: config.size == .small ? 38 : config.size == .medium ? 108 : 140)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
    }
}
