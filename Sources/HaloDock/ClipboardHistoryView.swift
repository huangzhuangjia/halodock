import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistory
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近复制").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if !history.items.isEmpty {
                    Button("清空未固定") { history.clearRecent() }.font(.caption).buttonStyle(.plain)
                }
            }
            if history.items.isEmpty {
                Text("复制文字、图片或文件后会显示在这里")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(history.orderedItems.prefix(expanded ? ClipboardHistory.itemLimit : 3))) { item in
                HStack(spacing: 8) {
                    Button { history.copy(item) } label: {
                        HStack(spacing: 10) {
                            if let image = item.previewImage {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 38, height: 32)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: item.symbol).foregroundStyle(Color.haloOrange).frame(width: 24)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help(item.imageData == nil ? item.text.isEmpty ? item.title : String(item.text.prefix(1000)) : item.title)
                    Button { history.togglePin(item) } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .foregroundStyle(item.pinned ? Color.haloOrange : Color.secondary)
                    }.buttonStyle(.plain).help(item.pinned ? "取消固定" : "固定，保留到下次启动")
                        .accessibilityLabel(item.pinned ? "取消固定" : "固定记录")
                    Menu {
                        Button("复制") { history.copy(item) }
                        Button(item.pinned ? "取消固定" : "固定") { history.togglePin(item) }
                        Button("删除记录", role: .destructive) { history.remove(item) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().frame(width: 20).help("记录操作")
                }.padding(.vertical, 3)
            }
            if history.items.count > 3 {
                Button(expanded ? "收起记录" : "查看全部 \(history.items.count) 条") { expanded.toggle() }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            if let message = history.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
