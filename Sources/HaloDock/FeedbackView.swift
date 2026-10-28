import AppKit
import SwiftUI

struct FeedbackReport {
    enum Kind: String, CaseIterable, Identifiable {
        case bug = "报告问题", suggestion = "功能建议"
        var id: String { rawValue }
    }
    var kind: Kind = .bug
    var title = ""
    var description = ""
    var steps = ""
    var expected = ""
    var includeEnvironment = true
    var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    var system = ProcessInfo.processInfo.operatingSystemVersionString
    var architecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Intel"
        #endif
    }
    static let issuesURL = URL(string: "https://github.com/huangzhuangjia/halodock/issues")!
    var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: String {
        var value = (kind == .bug ? "## 问题描述\n" : "## 使用场景与建议\n") + description + "\n\n"
        if kind == .bug {
            value += "## 复现步骤\n" + (steps.isEmpty ? "请补充" : steps) + "\n\n"
            value += "## 预期表现\n" + (expected.isEmpty ? "请补充" : expected) + "\n\n"
        }
        if includeEnvironment { value += "## 运行环境\n- HaloDock：\(version)\n- 系统：\(system)\n- 芯片：\(architecture)\n\n" }
        value += "## 截图或补充信息\n可在提交前添加已隐藏私人信息的截图。\n"
        return value
    }
    var draftURL: URL? {
        var url = URLComponents(string: "https://github.com/huangzhuangjia/halodock/issues/new")!
        url.queryItems = [
            URLQueryItem(name: "title", value: (kind == .bug ? "[Bug] " : "[建议] ") + String(title.prefix(120))),
            URLQueryItem(name: "body", value: body)
        ]
        return url.url
    }
    var canOpenDraft: Bool { valid && body.utf8.count <= 7000 && (draftURL?.absoluteString.utf8.count ?? Int.max) <= 7000 }
}

@MainActor
final class FeedbackWindow {
    static let shared = FeedbackWindow()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let next = NSWindow(contentViewController: NSHostingController(rootView: FeedbackView()))
            next.title = "HaloDock 问题反馈"
            next.identifier = NSUserInterfaceItemIdentifier("HaloDockFeedback")
            next.styleMask = [.titled, .closable, .miniaturizable]
            next.isReleasedWhenClosed = false; next.center(); window = next
        }
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct FeedbackView: View {
    @State private var report = FeedbackReport()
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.bubble").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("一起让 HaloDock 更好用").font(.title3.bold())
                    Text("问题和功能建议统一在 GitHub Issues 跟进。").font(.callout).foregroundStyle(.secondary)
                }
            }.padding(20)
            Form {
                Section("反馈内容") {
                    Picker("反馈类型", selection: $report.kind) { ForEach(FeedbackReport.Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标题（必填）").font(.callout.weight(.medium))
                        TextField("一句话概括问题或建议", text: $report.title).textFieldStyle(.roundedBorder).labelsHidden()
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.kind == .bug ? "问题描述（必填）" : "使用场景和建议（必填）").font(.callout.weight(.medium))
                        TextEditor(text: $report.description).frame(height: 90).border(Color.secondary.opacity(0.16)).accessibilityLabel("反馈详细描述")
                    }.padding(.vertical, 4)
                    if report.kind == .bug {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("复现步骤").font(.callout.weight(.medium))
                            TextField("例如：打开截图 → 点击识字 → …", text: $report.steps).textFieldStyle(.roundedBorder).labelsHidden()
                        }.padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("预期表现").font(.callout.weight(.medium))
                            TextField("你希望出现什么结果？", text: $report.expected).textFieldStyle(.roundedBorder).labelsHidden()
                        }.padding(.vertical, 4)
                    }
                }
                Section("运行环境") {
                    Toggle("附带 App、系统版本和芯片类型", isOn: $report.includeEnvironment)
                    if report.includeEnvironment { Text("HaloDock \(report.version) · \(report.system) · \(report.architecture)").font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    Text("反馈会公开在 GitHub。下一步打开反馈草稿，需要登录并由你最终确认提交；截图可在 GitHub 页面添加，请先隐藏密钥和私人信息。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { Link("查看已有问题", destination: FeedbackReport.issuesURL); Spacer(); Link("查看版本记录", destination: UpdateManager.releasesURL) }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("复制反馈内容") {
                    let board = NSPasteboard.general; board.clearContents()
                    message = board.setString(report.title + "\n\n" + report.body, forType: .string) ? "已复制，可以手动粘贴到 GitHub" : "复制失败，请重试"
                }
                Spacer()
                Button("打开 GitHub 草稿") {
                    guard report.canOpenDraft, let url = report.draftURL else { return }
                    message = NSWorkspace.shared.open(url) ? "已打开草稿，请在 GitHub 确认提交" : "未能打开浏览器，请复制内容手动反馈"
                }.buttonStyle(.borderedProminent).disabled(!report.canOpenDraft)
            }.padding(.horizontal, 20).padding(.top, 14)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 8) }
            if report.valid && !report.canOpenDraft { Text("内容较长，请复制反馈内容后，在 GitHub 手动粘贴提交。").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 8) }
            Color.clear.frame(height: 16)
        }.frame(width: 600, height: 620).background(Color(nsColor: .windowBackgroundColor)).modifier(HaloDockTheme())
    }
}
