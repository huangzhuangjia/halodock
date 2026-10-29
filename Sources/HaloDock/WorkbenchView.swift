import SwiftUI
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class WorkbenchWindow: NSObject, NSWindowDelegate {
    static let shared = WorkbenchWindow()
    private var window: NSWindow?
    var hasPresentedEditor = false
    func show() {
        if window == nil {
            let next = NSWindow(contentViewController: NSHostingController(rootView: WorkbenchView(store: .shared)))
            next.title = "HaloDock 工作台"
            next.identifier = NSUserInterfaceItemIdentifier("HaloDockWorkbench")
            next.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            next.minSize = CGSize(width: 760, height: 540)
            next.isReleasedWhenClosed = false
            next.delegate = self
            next.center(); window = next
        }
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasPresentedEditor else { return true }
        show()
        return false
    }
}

struct WorkbenchView: View {
    @ObservedObject var store: WorkbenchStore
    @State private var mode = 0
    @State private var query = ""
    @State private var name = ""
    @State private var newCollection = false
    @State private var renameCollection = false
    @State private var deletingCollection = false
    @State private var editingSnippet: TextSnippet?
    @State private var note = ""
    @State private var addingNote = false
    @State private var preview: WorkItem?
    @State private var pendingRemoval: WorkItem?
    @State private var pendingSnippetRemoval: TextSnippet?
    private var editorPresented: Bool { newCollection || renameCollection || addingNote || editingSnippet != nil }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("工作台", systemImage: "square.stack.3d.up").font(.title3.bold()).padding(.top, 12)
                Picker("内容", selection: $mode) { Text("收集").tag(0); Text("片段").tag(1) }.pickerStyle(.segmented).labelsHidden()
                if mode == 0 {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(store.collections) { collection in
                                Button { store.select(collection.id) } label: {
                                    HStack {
                                        Image(systemName: "tray")
                                        Text(collection.name).lineLimit(1)
                                        Spacer()
                                        Text("\(store.items.filter { $0.collectionID == collection.id }.count)").font(.caption).foregroundStyle(.secondary)
                                    }.padding(9).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .background(store.selectedCollection == collection.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    Button { name = ""; newCollection = true } label: { Label("新建工作台", systemImage: "plus") }
                } else {
                    Text("保存常用回复、命令和模板。日期、时间、剪贴板变量会在复制时替换。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { editingSnippet = TextSnippet(title: "", body: "") } label: { Label("新建片段", systemImage: "plus") }
                }
            }
            .padding(16).frame(width: 190).frame(maxHeight: .infinity).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == 0 ? store.collections.first { $0.id == store.selectedCollection }?.name ?? "收集箱" : "快捷文本片段").font(.title2.bold())
                        Text(mode == 0 ? "截图、文字、文件，围绕同一件事放在一起。" : "编辑后复制，随时粘贴到需要的地方。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        if mode == 0 {
                            Button("添加文字") { note = ""; addingNote = true }
                            Button("添加文件引用…") { importFiles() }
                            Button("导出 Markdown…") { export() }.disabled(store.currentItems.isEmpty)
                            Button("重命名工作台") { name = store.collections.first { $0.id == store.selectedCollection }?.name ?? ""; renameCollection = true }
                            Button("删除工作台…", role: .destructive) { deletingCollection = true }.disabled(store.collections.count == 1)
                        } else { Button("新建片段") { editingSnippet = TextSnippet(title: "", body: "") } }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).fixedSize().help("更多操作")
                }
                TextField(mode == 0 ? "筛选当前工作台" : "查找标题、分组或内容", text: $query).textFieldStyle(.roundedBorder)
                if mode == 0 { itemList } else { snippetList }
                if let message = store.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("内容仅保存在这台 Mac；文件保存引用，移动原文件后需重新添加。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 540, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor)).modifier(HaloDockTheme())
        .onChange(of: editorPresented) { WorkbenchWindow.shared.hasPresentedEditor = $0 }
        .onChange(of: mode) { _ in query = "" }
        .onChange(of: store.selectedCollection) { _ in query = "" }
        .sheet(isPresented: $newCollection) { nameSheet(title: "新建工作台") { if store.createCollection(name) { newCollection = false } } }
        .sheet(isPresented: $renameCollection) { nameSheet(title: "重命名工作台") { store.renameCollection(name); renameCollection = false } }
        .sheet(isPresented: $addingNote) {
            VStack(alignment: .leading, spacing: 16) {
                Text("添加文字").font(.headline)
                TextEditor(text: $note).frame(width: 440, height: 220).border(Color.secondary.opacity(0.2))
                HStack { Button("取消") { addingNote = false }.keyboardShortcut(.cancelAction); Spacer(); Button("加入工作台") { if store.add(text: note) { addingNote = false } }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction) }
            }.padding(24)
        }
        .sheet(item: $editingSnippet) { snippet in SnippetEditor(store: store, snippet: snippet) }
        .sheet(item: $preview) { item in WorkItemPreview(store: store, item: item) }
        .confirmationDialog("移除这条收集内容？原始引用文件不受影响。", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("移除", role: .destructive) { if let item = pendingRemoval { store.remove(item) }; pendingRemoval = nil }
        }
        .confirmationDialog("删除这个文本片段？", isPresented: Binding(get: { pendingSnippetRemoval != nil }, set: { if !$0 { pendingSnippetRemoval = nil } })) {
            Button("删除", role: .destructive) { if let snippet = pendingSnippetRemoval { store.removeSnippet(snippet) }; pendingSnippetRemoval = nil }
        }
        .confirmationDialog("删除当前工作台及其收集内容？原始引用文件不受影响。", isPresented: $deletingCollection) {
            Button("删除工作台", role: .destructive) { store.removeCollection() }
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.plainText.identifier], isTargeted: nil) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { value, _ in
                        if let url = value { Task { @MainActor in _ = store.add(file: url) } }
                    }
                } else {
                    _ = provider.loadObject(ofClass: String.self) { value, _ in
                        if let text = value { Task { @MainActor in _ = store.add(text: text) } }
                    }
                }
            }
            return !providers.isEmpty
        }
    }
    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                let items = store.currentItems.filter { query.isEmpty || ($0.title + $0.text).localizedCaseInsensitiveContains(query) }
                if items.isEmpty { empty("还没有收集内容", detail: "从截图行动卡、最近复制中加入，或拖入文字和文件。") }
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        if [.image, .gif].contains(item.kind), let url = store.assetURL(item), let image = thumbnail(url) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 72, height: 62).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        } else { Image(systemName: item.kind == .file ? "doc" : "text.alignleft").font(.title2).foregroundStyle(Color.accentColor).frame(width: 48, height: 48) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline).lineLimit(1)
                            Text(item.kind == .text ? String(item.text.prefix(180)) : item.kind == .gif ? "GIF 动图" : item.kind == .file ? "文件引用" : "截图")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            HStack {
                                Button("预览") { preview = item }
                                Button("复制") { store.copy(item) }
                                if item.kind == .text { Button("存为片段") { editingSnippet = TextSnippet(title: item.title, body: item.text) } }
                            }.controlSize(.small)
                        }
                        Spacer(minLength: 0)
                        Menu {
                            ForEach(store.collections.filter { $0.id != item.collectionID }) { c in Button("移到「\(c.name)」") { store.move(item, to: c.id) } }
                            Button("移除…", role: .destructive) { pendingRemoval = item }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
            }
        }
    }
    private var snippetList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                let filtered = store.snippets.filter { query.isEmpty || ($0.title + $0.body + $0.group).localizedCaseInsensitiveContains(query) }
                if filtered.isEmpty { empty("把常用文字变成片段", detail: "支持 {{日期}}、{{时间}}、{{剪贴板}}，在复制时展开。") }
                ForEach(filtered) { snippet in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(snippet.title).font(.headline); Spacer(); Text(snippet.group).font(.caption).foregroundStyle(.secondary) }
                        Text(snippet.body).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        HStack {
                            Button("复制") { store.copySnippet(snippet) }.buttonStyle(.borderedProminent)
                            Button("编辑") { editingSnippet = snippet }
                            Spacer()
                            Button("删除…", role: .destructive) { pendingSnippetRemoval = snippet }
                        }.controlSize(.small)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
            }
        }
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) { Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary); Text(title).font(.headline); Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(40).frame(maxWidth: .infinity)
    }
    private func nameSheet(title: String, save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("名称", text: $name).textFieldStyle(.roundedBorder).frame(width: 300)
            HStack { Button("取消") { newCollection = false; renameCollection = false }.keyboardShortcut(.cancelAction); Spacer(); Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24)
    }
    private func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
    private func importFiles() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; if panel.runModal() == .OK { for url in panel.urls { _ = store.add(file: url) } } }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = "工作台.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportMarkdown(to: url); store.message = "已导出 Markdown 和附件" }
        catch { store.message = "导出失败：" + error.localizedDescription }
    }
}

private struct SnippetEditor: View {
    @ObservedObject var store: WorkbenchStore
    @State var snippet: TextSnippet
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑文本片段").font(.title3.bold())
            TextField("标题", text: $snippet.title).textFieldStyle(.roundedBorder)
            TextField("分组", text: $snippet.group).textFieldStyle(.roundedBorder)
            TextEditor(text: $snippet.body).font(.system(.body, design: .monospaced)).frame(width: 480, height: 240).border(Color.secondary.opacity(0.2))
            Text("可用变量：{{日期}}、{{时间}}、{{剪贴板}}。复制时替换，源内容保持不变。")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存") { if store.saveSnippet(snippet) { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24)
    }
}

struct WorkItemPreview: View {
    @ObservedObject var store: WorkbenchStore
    let item: WorkItem
    @State private var source = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(item.title).font(.headline).lineLimit(1); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            if item.kind == .text { MarkdownTextPreview(text: item.text, source: $source) }
            else if let url = store.assetURL(item), item.kind == .file {
                DocumentFilePreview(url: url)
                HStack {
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(url.path)
                    Spacer()
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            } else if let url = store.assetURL(item) {
                ScrollView([.vertical, .horizontal]) {
                    if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().frame(width: 580) }
                }
                HStack {
                    Button("预览原文件") { if let url = store.assetURL(item) { NSWorkspace.shared.open(url) } }
                    Button("贴到桌面") {
                        if let url = store.assetURL(item), let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) { _ = PinnedScreenshots.shared.show(image) }
                    }
                }
            }
            HStack { Button("复制") { store.copy(item) }; if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary) } }
        }.padding(20).frame(width: 640, height: 520).background(Color(nsColor: .windowBackgroundColor)).modifier(HaloDockTheme())
    }
}
