import Foundation

enum QuickAction: String, CaseIterable, Identifiable {
    case awake, closedLid, screenshot, trash, focus
    var id: String { rawValue }
    var title: String {
        switch self {
        case .awake: "保持唤醒"
        case .closedLid: "合盖保持运行"
        case .screenshot: "截取屏幕"
        case .trash: "清空废纸篓"
        case .focus: "专注模式"
        }
    }
    static func ordered(_ value: String) -> [QuickAction] {
        var result: [QuickAction] = []
        for raw in value.split(separator: ",") {
            if let action = QuickAction(rawValue: String(raw)), !result.contains(action) { result.append(action) }
        }
        return result + allCases.filter { !result.contains($0) }
    }
    static func moved(_ action: QuickAction, by offset: Int, in value: String) -> String {
        var actions = ordered(value)
        guard let index = actions.firstIndex(of: action), actions.indices.contains(index + offset) else { return actions.map(\.rawValue).joined(separator: ",") }
        actions.swapAt(index, index + offset)
        return actions.map(\.rawValue).joined(separator: ",")
    }
    static func hidden(_ value: String) -> Set<String> { Set(value.split(separator: ",").map(String.init)) }
}
