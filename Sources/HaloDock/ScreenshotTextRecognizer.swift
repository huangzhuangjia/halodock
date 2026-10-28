import Foundation
import Vision

struct RecognizedLine: Sendable {
    let text: String
    let bounds: CGRect
}

enum ScreenshotTextRecognizer {
    static func orderedText(_ lines: [RecognizedLine]) -> String {
        // Vision uses bottom-left coordinates; cluster nearby baselines before
        // ordering left-to-right, so small detection offsets do not scramble rows.
        let sorted = lines.sorted { $0.bounds.midY > $1.bounds.midY }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.bounds.midY - line.bounds.midY) <= min(anchor.bounds.height, line.bounds.height) * 0.45 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        return rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            try Task.checkCancellation()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return RecognizedLine(text: text, bounds: observation.boundingBox)
            }
            return orderedText(lines)
        }.value
    }
}
