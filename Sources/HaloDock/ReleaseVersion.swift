import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let numbers: [Int]
    let prerelease: [String]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") { text.removeFirst() }
        let build = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        if build.count == 2 && build[1].isEmpty { return nil }
        let parts = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numeric = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(numeric.count), numeric.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), numeric.allSatisfy({ Int($0) != nil }) else { return nil }
        numbers = numeric.map { Int($0)! } + Array(repeating: 0, count: 3 - numeric.count)
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard identifiers.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) }) else { return nil }
            prerelease = identifiers.map(String.init)
        } else { prerelease = [] }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            if let x = Int(a), let y = Int(b) { return x < y }
            if Int(a) != nil { return true }
            if Int(b) != nil { return false }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
    }
    let tag_name: String
    let body: String?
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    func installer(architecture: String) -> Asset? {
        assets.first { asset in
            asset.name.hasSuffix("-macos-\(architecture).dmg") &&
            asset.name == (asset.name as NSString).lastPathComponent &&
            asset.browser_download_url.scheme == "https" &&
            asset.browser_download_url.host == "github.com" &&
            asset.browser_download_url.path.hasPrefix("/huangzhuangjia/halodock/releases/download/") &&
            asset.size > 0
        }
    }

    var validPage: Bool {
        html_url.scheme == "https" && html_url.host == "github.com" && html_url.path.hasPrefix("/huangzhuangjia/halodock/releases/tag/")
    }
}
