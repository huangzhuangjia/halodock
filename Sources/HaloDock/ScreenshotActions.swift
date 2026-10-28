import Foundation

enum ScreenshotActions {
    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var urls: [URL] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, !urls.contains(url) { urls.append(url) }
            if urls.count == 8 { break }
        }
        return urls
    }
    static func markdown(_ text: String) -> String {
        "<!-- HaloDock 截图文字 -->\n\n" + text.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") + "\n"
    }
}
