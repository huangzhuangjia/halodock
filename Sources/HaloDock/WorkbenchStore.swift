import AppKit
import Combine
import UniformTypeIdentifiers
import ImageIO

struct WorkCollection: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}
struct WorkItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image, file, gif }
    var id = UUID()
    var collectionID: UUID
    var title: String
    var kind: Kind
    var text = ""
    var asset: String?
    var fileURL: URL?
    var createdAt = Date()
}
struct TextSnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var group = "常用"
    func expanded(at date: Date = Date(), clipboard: String = "") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH:mm"
        return body.replacingOccurrences(of: "{{日期}}", with: day)
            .replacingOccurrences(of: "{{时间}}", with: formatter.string(from: date))
            .replacingOccurrences(of: "{{剪贴板}}", with: clipboard)
    }
}
private struct WorkbenchData: Codable {
    var collections = [WorkCollection(name: "收集箱")]
    var items: [WorkItem] = []
    var snippets: [TextSnippet] = []
    var selectedCollection: UUID?
}

@MainActor
final class WorkbenchStore: ObservableObject {
    static let shared = WorkbenchStore()
    @Published private var data = WorkbenchData()
    @Published var message: String?
    let directory: URL
    private let fm = FileManager.default
    var collections: [WorkCollection] { data.collections }
    var items: [WorkItem] { data.items }
    var snippets: [TextSnippet] { data.snippets }
    var selectedCollection: UUID { data.selectedCollection ?? data.collections[0].id }
    var currentItems: [WorkItem] { data.items.filter { $0.collectionID == selectedCollection }.sorted { $0.createdAt > $1.createdAt } }
    private var index: URL { directory.appendingPathComponent("index.json") }
    private(set) var readOnly = false

    init(directory: URL? = nil) {
        self.directory = directory ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HaloDock/Workbench", isDirectory: true)
        do {
            try fm.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if fm.fileExists(atPath: index.path) {
                data = try JSONDecoder().decode(WorkbenchData.self, from: Data(contentsOf: index))
                guard !data.collections.isEmpty, Set(data.collections.map(\.id)).count == data.collections.count,
                      data.items.allSatisfy({ item in data.collections.contains { $0.id == item.collectionID } && (item.asset.map { $0 == URL(fileURLWithPath: $0).lastPathComponent && !$0.hasPrefix(".") } ?? true) }) else { throw WorkError("工作台索引无效") }
                if !data.collections.contains(where: { $0.id == data.selectedCollection }) { data.selectedCollection = data.collections[0].id }
            }
        } catch { data = WorkbenchData(); readOnly = true; message = "无法读取工作台，保留原文件：" + error.localizedDescription }
    }
    private func commit(_ next: WorkbenchData) -> Bool {
        guard !readOnly else { return false }
        do {
            try JSONEncoder().encode(next).write(to: index, options: .atomic)
            data = next
            message = nil
            return true
        } catch { message = "保存失败：" + error.localizedDescription; return false }
    }
    func select(_ id: UUID) {
        guard data.collections.contains(where: { $0.id == id }) else { return }
        var next = data; next.selectedCollection = id; _ = commit(next)
    }
    @discardableResult func createCollection(_ name: String) -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty, collections.count < 30 else { message = "请输入名称，最多创建 30 个工作台"; return false }
        var next = data; let collection = WorkCollection(name: name)
        next.collections.append(collection); next.selectedCollection = collection.id
        return commit(next)
    }
    func renameCollection(_ name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty, let i = data.collections.firstIndex(where: { $0.id == selectedCollection }) else { return }
        var next = data; next.collections[i].name = name; _ = commit(next)
    }
    func removeCollection() {
        guard data.collections.count > 1 else { message = "至少保留一个工作台"; return }
        let id = selectedCollection, assets = currentItems.compactMap(\.asset)
        var next = data; next.items.removeAll { $0.collectionID == id }; next.collections.removeAll { $0.id == id }; next.selectedCollection = next.collections[0].id
        if commit(next) { for asset in assets { try? fm.removeItem(at: directory.appendingPathComponent(asset)) } }
    }
    @discardableResult func add(text: String, title: String? = nil) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 1_000_000 else { message = "文字不能为空或超过 1 MB"; return false }
        return addItem(WorkItem(collectionID: selectedCollection, title: title ?? String(text.prefix(60)), kind: .text, text: text))
    }
    @discardableResult func add(image: CGImage, title: String = "截图") -> Bool {
        guard Double(image.width) * Double(image.height) <= 40_000_000,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { message = "图片过大或无法编码"; return false }
        return addAsset(png, extension: "png", kind: .image, title: title)
    }
    @discardableResult func addAsset(_ bytes: Data, extension ext: String, kind: WorkItem.Kind, title: String) -> Bool {
        guard (ext == "png" && kind == .image) || (ext == "gif" && kind == .gif), bytes.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) > 0,
              items.count < 300 else { message = "工作台最多 300 项，单个附件最多 40 MB"; return false }
        let used = items.compactMap(\.asset).reduce(0) { total, name in total + ((try? directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard used + bytes.count <= 300 * 1024 * 1024 else { message = "工作台附件达到 300 MB，请先清理"; return false }
        let filename = UUID().uuidString + "." + ext, url = directory.appendingPathComponent(filename)
        do { try bytes.write(to: url, options: .atomic) }
        catch { message = "附件保存失败：" + error.localizedDescription; return false }
        if addItem(WorkItem(collectionID: selectedCollection, title: title, kind: kind, asset: filename)) { return true }
        try? fm.removeItem(at: url); return false
    }
    @discardableResult func add(file: URL) -> Bool {
        guard file.isFileURL else { return false }
        return addItem(WorkItem(collectionID: selectedCollection, title: file.lastPathComponent, kind: .file, fileURL: file))
    }
    @discardableResult private func addItem(_ item: WorkItem) -> Bool {
        guard items.count < 300 else { message = "最多保存 300 项，请先清理"; return false }
        var next = data; next.items.insert(item, at: 0)
        if commit(next) { message = "已加入「" + (collections.first { $0.id == selectedCollection }?.name ?? "工作台") + "」"; return true }
        return false
    }
    func addClipboard(_ item: ClipboardItem) {
        if let image = item.imageData {
            if let decoded = NSImage(data: image)?.cgImage(forProposedRect: nil, context: nil, hints: nil) { _ = add(image: decoded, title: item.title) }
        } else if !item.fileURLs.isEmpty { for file in item.fileURLs { _ = add(file: file) } }
        else { _ = add(text: item.text) }
    }
    func assetURL(_ item: WorkItem) -> URL? { item.asset.map { directory.appendingPathComponent($0) } ?? item.fileURL }
    func remove(_ item: WorkItem) {
        var next = data; next.items.removeAll { $0.id == item.id }
        if commit(next), let asset = item.asset { try? fm.removeItem(at: directory.appendingPathComponent(asset)) }
    }
    func move(_ item: WorkItem, to collection: UUID) {
        guard collections.contains(where: { $0.id == collection }), let i = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        var next = data; next.items[i].collectionID = collection; _ = commit(next)
    }
    func copy(_ item: WorkItem, board: NSPasteboard = .general) {
        board.clearContents()
        let success: Bool
        if item.kind == .text { success = board.setString(item.text, forType: .string) }
        else if let url = assetURL(item), item.kind == .file { success = fm.fileExists(atPath: url.path) && board.writeObjects([url as NSURL]) }
        else if let url = assetURL(item), let bytes = try? Data(contentsOf: url) { success = board.setData(bytes, forType: item.kind == .gif ? .init("com.compuserve.gif") : .png) }
        else { success = false }
        message = success ? "已复制" : "无法复制，文件可能已移动"
    }
    func saveSnippet(_ snippet: TextSnippet) -> Bool {
        guard !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !snippet.body.isEmpty,
              snippet.body.utf8.count <= 100_000 else { message = "请填写标题和内容，内容最多 100 KB"; return false }
        var next = data
        if let i = next.snippets.firstIndex(where: { $0.id == snippet.id }) { next.snippets[i] = snippet }
        else {
            guard next.snippets.count < 200 else { message = "最多保存 200 个片段"; return false }
            next.snippets.append(snippet)
        }
        return commit(next)
    }
    func removeSnippet(_ snippet: TextSnippet) { var next = data; next.snippets.removeAll { $0.id == snippet.id }; _ = commit(next) }
    func copySnippet(_ snippet: TextSnippet, board: NSPasteboard = .general) {
        let result = snippet.expanded(clipboard: board.string(forType: .string) ?? "")
        board.clearContents(); message = board.setString(result, forType: .string) ? "已复制片段" : "复制失败"
    }
    func exportMarkdown(to url: URL) throws {
        let collection = collections.first { $0.id == selectedCollection }?.name ?? "工作台"
        let assetsName = url.deletingPathExtension().lastPathComponent + "-附件"
        let assetsDir = url.deletingLastPathComponent().appendingPathComponent(assetsName)
        var result = "# " + collection + "\n\n"
        for item in currentItems.reversed() {
            result += "## " + item.title.replacingOccurrences(of: "\n", with: " ") + "\n\n"
            if item.kind == .text { result += item.text + "\n\n" }
            else if let source = assetURL(item) {
                if let name = item.asset {
                    try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                    let target = assetsDir.appendingPathComponent(name)
                    if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: source, to: target) }
                    let relative = (assetsName + "/" + name).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    result += "![附件](" + relative + ")\n\n"
                } else { result += "[文件](" + source.absoluteString + ")\n\n" }
            }
        }
        try result.write(to: url, atomically: true, encoding: .utf8)
    }
}
struct WorkError: LocalizedError { var errorDescription: String?; init(_ message: String) { errorDescription = message } }
