import Foundation
import Testing
@testable import HaloDock

@Test func releaseVersionOrdering() throws {
    let ordered = ["1.0.0-alpha", "1.0.0-beta.2", "1.0.0-beta.10", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.0.10"]
    for (a, b) in zip(ordered, ordered.dropFirst()) {
        #expect(try #require(ReleaseVersion(a)) < #require(ReleaseVersion(b)))
    }
    #expect(ReleaseVersion("v1.0") == ReleaseVersion("1.0.0+build"))
    for invalid in ["", "v", "latest", "1..2", "1.2.3.4", "1.0-"] { #expect(ReleaseVersion(invalid) == nil) }
}

private final class ReleaseProtocol: URLProtocol, @unchecked Sendable {
    static let data = Data(#"{"tag_name":"v1.2.3","body":"Update notes","html_url":"https://github.com/huangzhuangjia/halodock/releases/tag/v1.2.3","draft":false,"prerelease":false,"assets":[{"name":"HaloDock-1.2.3-macos-arm64.dmg","browser_download_url":"https://github.com/huangzhuangjia/halodock/releases/download/v1.2.3/HaloDock-1.2.3-macos-arm64.dmg","size":100}]}"#.utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let offline = request.value(forHTTPHeaderField: "X-Test-Mode") == "offline"
        let status = offline ? 503 : request.url!.host == "api.github.com" ? 403 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? Self.data : Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func selectsOnlyTrustedCompatibleInstaller() throws {
    let release = try JSONDecoder().decode(GitHubRelease.self, from: ReleaseProtocol.data)
    #expect(release.validPage)
    #expect(release.installer(architecture: "arm64") != nil)
    #expect(release.installer(architecture: "x86_64") == nil)
    let external = ReleaseProtocol.data.replacingOccurrences(of: "https://github.com/huangzhuangjia/halodock/releases/download/", with: "https://example.com/huangzhuangjia/halodock/releases/download/")
    #expect(try JSONDecoder().decode(GitHubRelease.self, from: external).installer(architecture: "arm64") == nil)
}

@Test @MainActor func updateStatesAndRateLimitFallback() async throws {
    let name = "HaloDock.UpdateTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("v1.2.3", forKey: "lastNotifiedRelease")
    func session(offline: Bool = false) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        if offline { config.httpAdditionalHeaders = ["X-Test-Mode": "offline"] }
        return URLSession(configuration: config)
    }
    let newer = UpdateManager(currentVersion: "1.0.0", session: session(), defaults: defaults)
    await newer.check(interactive: false)
    #expect(newer.availableRelease?.tag_name == "v1.2.3")
    #expect(!newer.isChecking)
    let current = UpdateManager(currentVersion: "1.2.3", session: session(), defaults: defaults)
    await current.check(interactive: false)
    #expect(current.availableRelease == nil)
    #expect(current.message.hasPrefix("已是最新版本"))
    let failed = UpdateManager(currentVersion: "1.0.0", session: session(offline: true), defaults: defaults)
    await failed.check(interactive: false)
    #expect(failed.availableRelease == nil)
    #expect(!failed.message.hasPrefix("已是最新版本"))
}

private extension Data {
    func replacingOccurrences(of old: String, with new: String) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8)
    }
}
