//
//  OCRService.swift
//  MeiteiMayekTranslator
//

import Foundation
import UIKit

final class OCRService {
    private struct Provider {
        let source: String
        let recognizer: OCRRecognizing
    }

    private let providers: [Provider]
    private let imagePreprocessor: OCRImagePreparing
    private let minimumAcceptedConfidence: Float

    init(
        cloudOCR: OCRRecognizing = OCRSpaceService(),
        onDeviceOCR: OCRRecognizing = VisionOCRService(),
        localImageOCR: OCRRecognizing = LocalMayekGlyphRecognizer(),
        imagePreprocessor: OCRImagePreparing = DefaultOCRImagePreprocessor(),
        minimumAcceptedConfidence: Float = 0.08
    ) {
        self.providers = [
            Provider(source: "Apple Vision", recognizer: onDeviceOCR),
            Provider(source: "Local Mayek", recognizer: localImageOCR),
            Provider(source: "OCR.space", recognizer: cloudOCR),
        ]
        self.imagePreprocessor = imagePreprocessor
        self.minimumAcceptedConfidence = minimumAcceptedConfidence
    }

    func recognizeMeiteiText(from image: UIImage) async throws -> OCRRecognitionResult {
        let variants = imagePreprocessor.variants(for: image)
        var candidates: [OCRRecognitionResult] = []
        var providerErrors: [String] = []

        OCRDebugLogger.writeImage(image, name: "00-original")

        for provider in providers {
            for variant in variants {
                OCRDebugLogger.writeImage(variant.image, name: "\(provider.source)-\(variant.name)")

                do {
                    let result = try await recognize(
                        provider.recognizer,
                        image: variant.image,
                        source: provider.source,
                        variantName: variant.name
                    )

                    OCRDebugLogger.log("\(result.source) / \(result.variantName): raw=\(result.cleanedText) extracted=\(result.extractedText) confidence=\(result.confidence)")

                    guard result.confidence >= minimumAcceptedConfidence else {
                        providerErrors.append("\(provider.source) / \(variant.name): rejected low confidence \(result.confidence)")
                        continue
                    }

                    if !result.cleanedText.isEmpty || !result.extractedText.isEmpty {
                        candidates.append(result)
                    }
                } catch {
                    providerErrors.append("\(provider.source) / \(variant.name): \(error.localizedDescription)")
                }
            }

            if provider.source == "Apple Vision",
               let bestOnDevice = candidates.max(by: isLowerRankedResult),
               bestOnDevice.mayekCount >= 2 {
                return bestOnDevice
            }

            if provider.source == "Local Mayek",
               let bestLocal = candidates.max(by: isLowerRankedResult),
               bestLocal.mayekCount > 0 {
                return bestLocal
            }
        }

        guard let best = candidates.max(by: isLowerRankedResult) else {
            let details = providerErrors.isEmpty ? "" : " OCR details: \(providerErrors.joined(separator: " | "))"
            throw TransliterationService.ServiceError.ocrFailed(
                "No readable text was returned. Try a clearer crop, brighter lighting, or type text manually.\(details)"
            )
        }

        guard best.mayekCount > 0 else {
            let details = providerErrors.isEmpty ? "" : " OCR details: \(providerErrors.joined(separator: " | "))"
            throw TransliterationService.ServiceError.ocrFailed(
                "OCR returned text, but no Meitei Mayek Unicode characters were found. Try a tighter crop with only Meitei Mayek text.\(details)"
            )
        }

        return best
    }

    static func sortedReadingOrder(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        blocks.sorted { lhs, rhs in
            guard let lhsBox = lhs.boundingBox, let rhsBox = rhs.boundingBox else {
                return lhs.text < rhs.text
            }

            let verticalTolerance: CGFloat = 0.035
            let lhsMidY = lhsBox.midY
            let rhsMidY = rhsBox.midY
            if abs(lhsMidY - rhsMidY) > verticalTolerance {
                return lhsMidY > rhsMidY
            }
            return lhsBox.minX < rhsBox.minX
        }
    }

    static func rejectLowConfidence(
        _ blocks: [OCRTextBlock],
        minimumConfidence: Float
    ) -> [OCRTextBlock] {
        blocks.filter { $0.confidence >= minimumConfidence }
    }

    private func recognize(
        _ recognizer: OCRRecognizing,
        image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        if let detailedRecognizer = recognizer as? OCRDetailedRecognizing {
            return try await detailedRecognizer.recognizeDetailed(
                from: image,
                source: source,
                variantName: variantName
            )
        }

        let rawText = try await recognizer.recognizeText(from: image)
        return OCRRecognitionResult.fromRawText(
            rawText,
            source: source,
            variantName: variantName,
            confidence: 0.5
        )
    }

    private func isLowerRankedResult(_ lhs: OCRRecognitionResult, _ rhs: OCRRecognitionResult) -> Bool {
        if lhs.mayekCount != rhs.mayekCount {
            return lhs.mayekCount < rhs.mayekCount
        }
        if lhs.mayekRatio != rhs.mayekRatio {
            return lhs.mayekRatio < rhs.mayekRatio
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence < rhs.confidence
        }
        return lhs.extractedText.count < rhs.extractedText.count
    }
}

