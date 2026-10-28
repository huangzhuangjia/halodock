import AppKit
import SwiftUI

/// Saving to another collection must not change the collection the user is browsing.
@MainActor
final class WorkbenchDestinationPicker: NSObject {
    private let onSelect: (UUID) -> Void
    init(onSelect: @escaping (UUID) -> Void) { self.onSelect = onSelect }
    func menu(store: WorkbenchStore) -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "加入哪个工作台？", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        menu.addItem(.separator())
        for collection in store.collections {
            let item = NSMenuItem(title: collection.name, action: #selector(selectDestination(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = collection.id
            item.state = store.selectedCollection == collection.id ? .on : .off
            item.toolTip = store.selectedCollection == collection.id ? "当前工作台" : "保存到此工作台"
            menu.addItem(item)
        }
        return menu
    }
    @objc private func selectDestination(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onSelect(id) }
    }
    static func show(in view: NSView, at point: CGPoint, store: WorkbenchStore = .shared, selected: @escaping (UUID) -> Void) {
        let picker = WorkbenchDestinationPicker(onSelect: selected)
        let previousLevel = view.window?.level
        // Screenshot overlays use screen-saver level; native menus must sit above them.
        if let level = previousLevel, level.rawValue > NSWindow.Level.floating.rawValue { view.window?.level = .floating }
        defer { if let previousLevel { view.window?.level = previousLevel } }
        _ = withExtendedLifetime(picker) { picker.menu(store: store).popUp(positioning: nil, at: point, in: view) }
    }
}

struct WorkbenchDestinationMenu: View {
    @ObservedObject var store: WorkbenchStore = .shared
    var title = "加入工作台"
    let selected: (UUID) -> Void
    var body: some View {
        Menu {
            Text("选择目标工作台")
            ForEach(store.collections) { collection in
                Button { selected(collection.id) } label: {
                    Label(collection.name, systemImage: collection.id == store.selectedCollection ? "checkmark.circle" : "tray")
                }
            }
        } label: { Text(title) }
        .help("选择保存到哪个工作台；勾选项为当前工作台")
    }
}
