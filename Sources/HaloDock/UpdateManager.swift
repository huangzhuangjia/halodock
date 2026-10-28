import AppKit
import Combine
import CryptoKit

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    static let releasesURL = URL(string: "https://github.com/huangzhuangjia/halodock/releases/latest")!
    let currentVersion: String
    @Published private(set) var message = "尚未检查更新"
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var availableRelease: GitHubRelease?
    private var automaticTask: Task<Void, Never>?
    private let session: URLSession
    private let defaults: UserDefaults

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0", session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.currentVersion = currentVersion
        self.session = session
        self.defaults = defaults
    }

    func startAutomaticChecks() {
        guard automaticTask == nil else { return }
        automaticTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                if self?.defaults.object(forKey: "automaticallyCheckUpdates") as? Bool ?? true {
                    await self?.check(interactive: false)
                }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func check(interactive: Bool) async {
        guard !isChecking && !isDownloading else { return }
        isChecking = true
        defer { isChecking = false }
        message = "正在连接 GitHub…"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/huangzhuangjia/halodock/releases/latest")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HaloDock/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let data = try await releaseData(primary: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft && !release.prerelease && release.validPage,
                  let newest = ReleaseVersion(release.tag_name), let current = ReleaseVersion(currentVersion) else {
                throw UpdateFailure("无法识别 GitHub 的正式版本信息")
            }
            if newest > current {
                availableRelease = release
                message = "发现新版本 \(release.tag_name)"
                if interactive || defaults.string(forKey: "lastNotifiedRelease") != release.tag_name {
                    defaults.set(release.tag_name, forKey: "lastNotifiedRelease")
                    presentUpdate(release)
                }
            } else {
                availableRelease = nil
                message = "已是最新版本（\(currentVersion)）"
                if interactive { showNotice(title: "无需更新", detail: message) }
            }
        } catch {
            // A failed check must never claim the installed version is current.
            message = error.localizedDescription
            if interactive { showNotice(title: "无法检查更新", detail: message) }
        }
    }

    private func releaseData(primary: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: primary)
            if (response as? HTTPURLResponse)?.statusCode == 200 { return data }
        } catch {
            if Task.isCancelled { throw error }
        }
        // The public website mirrors Releases metadata; no credentials are shipped in the app.
        var fallback = URLRequest(url: URL(string: "https://huangzhuangjia.github.io/halodock/release.json")!)
        fallback.timeoutInterval = 20
        fallback.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: fallback)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateFailure("暂时无法读取 GitHub Releases 或官网版本清单，请稍后重试")
        }
        return data
    }

    private func presentUpdate(_ release: GitHubRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "HaloDock \(release.tag_name) 可用"
        alert.informativeText = "当前版本：\(currentVersion)\n\n\(String((release.body ?? "前往发布页面查看更新说明。").prefix(1400)))"
        let supported = release.installer(architecture: Self.architecture) != nil
        alert.addButton(withTitle: supported ? "下载并打开安装包" : "查看发布页面")
        if supported { alert.addButton(withTitle: "查看版本说明") }
        alert.addButton(withTitle: "稍后")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            if supported { Task { await downloadInstaller() } }
            else { NSWorkspace.shared.open(release.html_url) }
        } else if supported && result == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.html_url)
        }
    }

    func downloadInstaller() async {
        guard !isDownloading, let release = availableRelease,
              let asset = release.installer(architecture: Self.architecture) else { return }
        isDownloading = true
        defer { isDownloading = false }
        message = "正在下载 \(release.tag_name)…"
        do {
            var request = URLRequest(url: asset.browser_download_url)
            request.timeoutInterval = 180
            let (temporary, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateFailure("下载安装包失败，请稍后重试或前往发布页面") }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size.map(Int64.init) == asset.size else { throw UpdateFailure("安装包下载不完整，请重试") }
            if let digest = asset.digest, digest.hasPrefix("sha256:") {
                let expected = String(digest.dropFirst(7)).lowercased()
                let actual = try await Task.detached {
                    let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
                    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }.value
                guard actual == expected else { throw UpdateFailure("安装包校验失败，请重新下载") }
            }
            let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var destination = downloads.appendingPathComponent(asset.name)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = downloads.appendingPathComponent("HaloDock-\(UUID().uuidString.prefix(8))-\(asset.name)")
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            message = "下载完成，安装包已保存在“下载”文件夹"
            guard NSWorkspace.shared.open(destination) else { throw UpdateFailure("已下载到 \(destination.path)，请手动打开安装包") }
            showNotice(title: "安装包已打开", detail: "先退出 HaloDock，再将安装包里的新版拖到“应用程序”替换旧版，最后重新打开。\n\n已保存：\(destination.lastPathComponent)")
        } catch {
            message = error.localizedDescription
            showNotice(title: "下载未完成", detail: message)
        }
    }

    private func showNotice(title: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

private struct UpdateFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
