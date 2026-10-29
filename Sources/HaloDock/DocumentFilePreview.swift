import SwiftUI
import Quartz
import PDFKit
import UniformTypeIdentifiers

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable { case heading(Int), paragraph, code(String), quote, list, rule, table }
    let id: Int
    let kind: Kind
    let text: String
}
enum MarkdownDocument {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = [], paragraph: [String] = [], code: [String] = []
        var language: String?, index = 0
        func append(_ kind: MarkdownBlock.Kind, _ text: String) { result.append(.init(id: index, kind: kind, text: text)); index += 1 }
        func flush() { if !paragraph.isEmpty { append(.paragraph, paragraph.joined(separator: "\n")); paragraph = [] } }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let current = language { append(.code(current), code.joined(separator: "\n")); language = nil; code = [] }
                else { flush(); language = String(trimmed.dropFirst(3)) }
                continue
            }
            if language != nil { code.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            if ["---", "***", "___"].contains(trimmed) { flush(); append(.rule, ""); continue }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); append(.heading(hashes), String(trimmed.dropFirst(hashes + 1))); continue
            }
            if trimmed.hasPrefix(">") { flush(); append(.quote, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)); continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { flush(); append(.list, String(trimmed.dropFirst(2))); continue }
            if trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil { flush(); append(.list, trimmed); continue }
            if trimmed.contains("|"), trimmed.hasPrefix("|") || trimmed.hasSuffix("|") {
                flush()
                if !trimmed.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces).isEmpty {
                    if let last = result.last, last.kind == .table {
                        result[result.count - 1] = MarkdownBlock(id: last.id, kind: .table, text: last.text + "\n" + trimmed)
                    } else { append(.table, trimmed) }
                }
                continue
            }
            paragraph.append(line)
        }
        flush()
        if let language { append(.code(language), code.joined(separator: "\n")) }
        return result
    }
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct DocumentFilePreview: View {
    let url: URL
    @State private var text: String?
    @State private var error: String?
    @State private var loading = true
    @State private var source = false
    private var markdown: Bool { ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased()) }
    private var textual: Bool {
        markdown || ["txt", "json", "csv", "log", "swift", "js", "ts", "tsx", "jsx", "py", "sh", "yml", "yaml", "toml", "xml", "css", "html", "sql"].contains(url.pathExtension.lowercased()) || UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(url.pathExtension.isEmpty ? "文件预览" : url.pathExtension.uppercased() + " 预览", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if markdown && text != nil { Toggle("源码", isOn: $source).toggleStyle(.switch).controlSize(.small) }
                Button("用默认应用打开") { NSWorkspace.shared.open(url) }.controlSize(.small)
            }
            if loading { ProgressView("正在加载预览…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error {
                VStack(spacing: 12) { Image(systemName: "doc.badge.ellipsis").font(.largeTitle); Text(error).foregroundStyle(.secondary); Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let text {
                MarkdownTextPreview(text: text, formatted: markdown, showsModePicker: false, source: $source)
            } else if url.pathExtension.lowercased() == "pdf" {
                PDFDocumentPreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { SystemDocumentPreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: url) {
            loading = true; error = nil; text = nil
            do {
                let file = url, isText = textual
                text = try await Task.detached {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true else { throw WorkError("文件夹请在 Finder 中查看") }
                    guard isText else { return nil as String? }
                    guard let size = values.fileSize, size <= 2 * 1024 * 1024 else { throw WorkError("文本超过 2 MB，请用默认应用打开") }
                    let data = try Data(contentsOf: file)
                    guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw WorkError("此文本编码无法预览，请用默认应用打开") }
                    return value
                }.value
            } catch { self.error = "无法预览：" + error.localizedDescription }
            loading = false
        }
        .environment(\.openURL, OpenURLAction { link in
            guard ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
    }
}

/// File previews and collected text use the same renderer and source switch.
struct MarkdownTextPreview: View {
    let text: String
    var formatted = true
    var showsModePicker = true
    @Binding var source: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsModePicker {
                HStack {
                    Label("文本预览", systemImage: "text.alignleft").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("预览方式", selection: $source) {
                        Text("排版").tag(false)
                        Text("源码").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
            }
            ScrollView([.vertical, .horizontal]) {
                if formatted && !source {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(MarkdownDocument.blocks(text)) { block in blockView(block) }
                    }.frame(width: 560, alignment: .leading).padding(16).textSelection(.enabled)
                } else {
                    Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12).frame(minWidth: 560, alignment: .leading)
                }
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .environment(\.openURL, OpenURLAction { link in
            guard ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
    }
    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level): Text(MarkdownDocument.inline(block.text)).font(.system(size: CGFloat(max(15, 29 - level * 3)), weight: .bold)).padding(.top, 6)
        case .paragraph: Text(MarkdownDocument.inline(block.text)).font(.body).fontWeight(.regular).lineSpacing(4)
        case .list: HStack(alignment: .top, spacing: 8) { Text("•").foregroundStyle(.secondary); Text(MarkdownDocument.inline(block.text)).lineSpacing(3) }
        case .quote: HStack(alignment: .top, spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.4)).frame(width: 3); Text(MarkdownDocument.inline(block.text)).foregroundStyle(.secondary).padding(.vertical, 4) }.fixedSize(horizontal: false, vertical: true)
        case .code(let language):
            VStack(alignment: .leading, spacing: 8) {
                if !language.isEmpty { Text(language).font(.caption2).foregroundStyle(.secondary) }
                Text(block.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case .rule: Divider()
        case .table:
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(block.text.components(separatedBy: "\n").enumerated()), id: \.offset) { row, line in
                    GridRow {
                        ForEach(Array(tableCells(line).enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownDocument.inline(cell)).font(.callout.weight(row == 0 ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(row == 0 ? Color.secondary.opacity(0.06) : .clear)
                                .overlay(Rectangle().stroke(Color.secondary.opacity(0.15)))
                        }
                    }
                }
            }
        }
    }
    private func tableCells(_ line: String) -> [String] {
        var cells = line.components(separatedBy: "|")
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct SystemDocumentPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

private struct PDFDocumentPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true; view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
