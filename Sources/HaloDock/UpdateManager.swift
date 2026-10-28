import AppKit
import Combine
import CryptoKit
import UpdateInstallation

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    static let releasesURL = URL(string: "https://github.com/huangzhuangjia/halodock/releases/latest")!
    let currentVersion: String
    @Published private(set) var message = "尚未检查更新"
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var hasPreparedUpdate = false
    private(set) var shouldShowUpdateResult = false
    var canRestart: (() -> Bool)?
    var revealProgress: (() -> Void)?
    private var prepared: PreparedAppUpdate?
    private var installerProcess: Process?
    @Published private(set) var availableRelease: GitHubRelease?
    private var automaticTask: Task<Void, Never>?
    private let session: URLSession
    private let defaults: UserDefaults

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0", session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.currentVersion = currentVersion
        self.session = session
        self.defaults = defaults
        restoreUpdateState()
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
        guard !isChecking && !isDownloading && !hasPreparedUpdate else { return }
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
                if (interactive || defaults.string(forKey: "lastNotifiedRelease") != release.tag_name) && (interactive || canRestart?() != false) {
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
        var fallback = URLRequest(url: URL(string: "https://huangzhuangjia.github.io/halodock/release.json?check=\(Int(Date().timeIntervalSince1970/300))")!)
        fallback.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
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
        alert.addButton(withTitle: supported ? "立即更新" : "查看发布页面")
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
        if hasPreparedUpdate { await restartPreparedUpdate(); return }
        guard !isDownloading, let release=availableRelease,
              let asset=release.installer(architecture:Self.architecture) else { return }
        isDownloading=true
        revealProgress?()
        progress=0
        defer {isDownloading=false}
        message="正在下载 \(release.tag_name)…"
        do {
            var request=URLRequest(url:asset.browser_download_url)
            request.timeoutInterval=180
            let delegate=UpdateDownloadProgress(expected:asset.size) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self,self.isDownloading else {return}
                    self.progress=max(self.progress,fraction*0.78)
                }
            }
            let (temporary,response)=try await delegate.download(for:request)
            defer {try? FileManager.default.removeItem(at:temporary)}
            guard let http=response as? HTTPURLResponse,http.statusCode==200 else {throw UpdateFailure("下载安装包失败，请稍后重试")}
            message="正在校验安装包…";progress=0.8
            let size=try temporary.resourceValues(forKeys:[.fileSizeKey]).fileSize
            guard size.map(Int64.init)==asset.size else {throw UpdateFailure("安装包下载不完整，请重试")}
            if let digest=asset.digest,digest.hasPrefix("sha256:") {
                let expected=String(digest.dropFirst(7)).lowercased()
                let actual=try await Task.detached {
                    let data=try Data(contentsOf:temporary,options:.mappedIfSafe)
                    return SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
                }.value
                guard actual==expected else {throw UpdateFailure("安装包校验失败，请重新下载")}
            }
            message="正在准备更新，HaloDock 仍可使用…";progress=0.86
            let target=Bundle.main.bundleURL
            let helper=target.appendingPathComponent("Contents/Helpers/HaloDockUpdater")
            var version=release.tag_name
            if version.hasPrefix("v") {version.removeFirst()}
            let next=try await AppUpdatePreparation.prepare(dmg:temporary,version:version,target:target,helper:helper)
            prepared=next
            hasPreparedUpdate=true
            defaults.set(next.manifest.path,forKey:"preparedUpdateManifest")
            progress=0.97
            if canRestart?()==false {
                message="更新已准备好。请先完成当前截图，再点击“重启更新”。"
            } else { await restartPreparedUpdate() }
        } catch {
            message=error.localizedDescription
            showNotice(title:"更新未完成",detail:message+"\n\n当前应用仍可继续使用。")
        }
    }

    func restartPreparedUpdate() async {
        guard let prepared else {return}
        guard canRestart?() != false else {
            message="请先完成或取消当前截图，再重启更新。";return
        }
        isDownloading=true
        message="准备重新启动以应用更新…";progress=0.99
        do {
            try InstallerTransaction.validatePaths(prepared.plan)
            try? FileManager.default.removeItem(at:prepared.plan.statusFile)
            let process=Process()
            installerProcess=process
            process.executableURL=prepared.helper
            process.arguments=[prepared.manifest.path]
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run()
            let deadline=Date().addingTimeInterval(8)
            var ready=false
            while Date()<deadline && process.isRunning {
                if let data=try? Data(contentsOf:prepared.plan.statusFile),let status=try? JSONDecoder().decode(InstallationStatus.self,from:data) {
                    if status.state=="ready" {ready=true;break}
                    if status.state=="failed" {throw UpdateFailure(status.message)}
                }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard ready else {throw UpdateFailure("更新器未能就绪，当前版本保持不变")}
            if canRestart?()==false {
                process.terminate()
                await Task.detached {process.waitUntilExit()}.value
                installerProcess=nil
                isDownloading=false
                message="更新已准备好。请先完成当前截图，再点击“重启更新”。"
                return
            }
            defaults.set(prepared.plan.version,forKey:"pendingUpdateVersion")
            defaults.set(prepared.plan.statusFile.path,forKey:"pendingUpdateStatus")
            defaults.removeObject(forKey:"preparedUpdateManifest")
            progress=1
            NSApp.terminate(nil)
        } catch {
            if let process=installerProcess,process.isRunning {process.terminate()}
            installerProcess=nil
            isDownloading=false
            message=error.localizedDescription
            showNotice(title:"暂时无法安装更新",detail:message)
        }
    }

    private func restoreUpdateState() {
        if let expected=defaults.string(forKey:"pendingUpdateVersion"),
           let version=ReleaseVersion(expected),let current=ReleaseVersion(currentVersion),current>=version {
            message="已成功更新至 \(currentVersion)"
            shouldShowUpdateResult=true
            defaults.removeObject(forKey:"pendingUpdateVersion")
            defaults.removeObject(forKey:"pendingUpdateStatus")
        } else if let path=defaults.string(forKey:"pendingUpdateStatus"),let data=try? Data(contentsOf:URL(fileURLWithPath:path)),
                  let status=try? JSONDecoder().decode(InstallationStatus.self,from:data),status.state=="failed" {
            message="更新未完成：\(status.message)"
            shouldShowUpdateResult=true
            defaults.removeObject(forKey:"pendingUpdateVersion")
            defaults.removeObject(forKey:"pendingUpdateStatus")
        }
        if let path=defaults.string(forKey:"preparedUpdateManifest"),let data=try? Data(contentsOf:URL(fileURLWithPath:path)),
           let plan=try? JSONDecoder().decode(InstallationPlan.self,from:data),
           plan.target.resolvingSymlinksInPath().path==Bundle.main.bundleURL.resolvingSymlinksInPath().path,
           let preparedVersion=ReleaseVersion(plan.version),let current=ReleaseVersion(currentVersion),preparedVersion>current,
           (try? InstallerTransaction.validatePaths(plan)) != nil,
           (try? InstallerTransaction.validateBundle(plan.staged,version:plan.version)) != nil {
            // A fresh PID is required after postponing an update across an app restart.
            let renewed=InstallationPlan(target:plan.target,staged:plan.staged,backup:plan.backup,workDirectory:plan.workDirectory,statusFile:plan.statusFile,oldProcessID:ProcessInfo.processInfo.processIdentifier,version:plan.version)
            try? FileManager.default.removeItem(at:plan.statusFile)
            try? JSONEncoder().encode(renewed).write(to:URL(fileURLWithPath:path),options:.atomic)
            prepared=PreparedAppUpdate(plan:renewed,manifest:URL(fileURLWithPath:path),helper:plan.target.appendingPathComponent("Contents/Helpers/HaloDockUpdater"))
            hasPreparedUpdate=true
            progress=0.97
            message="更新已下载，点击“重启更新”完成安装。"
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
