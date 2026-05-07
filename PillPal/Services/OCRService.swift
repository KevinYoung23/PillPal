import Foundation
import UIKit
import Vision

final class OCRService {
    private static let preferredLanguages = [
        "zh-Hans", // Chinese Simplified
        "zh-Hant", // Chinese Traditional
        "en-US"
    ]

    func recognizeText(
        from images: [UIImage],
        progress: @escaping (Double) -> Void
    ) async throws -> String {
        var pages: [String] = []

        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            let pageText = try await recognize(image: image)
            try Task.checkCancellation()
            pages.append("[PAGE \(index + 1)]\n\(pageText)")
            let ratio = Double(index + 1) / Double(max(images.count, 1))
            await MainActor.run {
                progress(ratio)
            }
        }

        try Task.checkCancellation()
        return pages.joined(separator: "\n\n")
    }

    private func recognize(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "OCRService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Unable to process image for OCR."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = supportedLanguages(for: request.revision)

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func supportedLanguages(for revision: Int) -> [String] {
        guard let supported = try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: revision
        ) else {
            return Self.preferredLanguages
        }

        let matched = Self.preferredLanguages.filter { language in
            supported.contains(language)
        }

        return matched.isEmpty ? ["en-US"] : matched
    }
}
