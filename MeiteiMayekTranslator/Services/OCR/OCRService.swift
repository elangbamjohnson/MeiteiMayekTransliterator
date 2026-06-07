//
//  OCRService.swift
//  MeiteiMayekTranslator
//
//  Changes from original:
//  FIX-5  minimumOnDeviceMayekCount raised from 2 → 3 so Apple Vision cannot
//         short-circuit the pipeline with a 2-char garbage result.
//
//  No other logic changed; all other fixes live in TransliterationService.swift.

import Foundation
import UIKit

nonisolated final class OCRService {

    // MARK: - Provider identity

    enum ProviderKind {
        case appleVision
        case localMayek
        case cloudOCR
    }

    private struct Provider {
        let kind:       ProviderKind
        let source:     String
        let recognizer: OCRRecognizing
    }

    // MARK: - Constants

    private enum Constants {
        // FIX-5: raised from 2 to 3 — Apple Vision frequently returns 1-2 stray
        // Mayek scalars from adjacent Unicode blocks; we need a more robust result
        // before declaring early success.
        static let minimumOnDeviceMayekCount = 3
        static let minimumLocalMayekCount    = 1
        static let verticalLineTolerance: CGFloat = 0.035
        static let minimumBlockConfidence: Float  = 0.05
    }

    // MARK: - Properties

    private let providers:                  [Provider]
    private let imagePreprocessor:          OCRImagePreparing
    private let minimumAcceptedConfidence:  Float

    // MARK: - Init

    init(
        cloudOCR:        OCRRecognizing      = OCRSpaceService(),
        onDeviceOCR:     OCRRecognizing      = VisionOCRService(),
        localImageOCR:   OCRRecognizing      = MeiteiMayekCoreMLOCRService(),
        imagePreprocessor: OCRImagePreparing = DefaultOCRImagePreprocessor(),
        minimumAcceptedConfidence: Float     = 0.08
    ) {
        self.providers = [
            Provider(kind: .localMayek,  source: "Meitei Core ML", recognizer: localImageOCR),
            Provider(kind: .appleVision, source: "Apple Vision", recognizer: onDeviceOCR),
            Provider(kind: .cloudOCR,    source: "OCR.space",    recognizer: cloudOCR),
        ]
        self.imagePreprocessor        = imagePreprocessor
        self.minimumAcceptedConfidence = minimumAcceptedConfidence
    }

    // MARK: - Main recognition entry point

    func recognizeMeiteiText(from image: UIImage) async throws -> OCRRecognitionResult {
        let variants        = imagePreprocessor.variants(for: image)
        var allCandidates:  [OCRRecognitionResult] = []
        var providerErrors: [String]               = []

        OCRDebugLogger.writeImage(image, name: "00-original")

        for provider in providers {
            var providerCandidates: [OCRRecognitionResult] = []

            for variant in variants {
                OCRDebugLogger.writeImage(variant.image, name: "\(provider.source)-\(variant.name)")

                do {
                    let result = try await recognize(
                        provider.recognizer,
                        image: variant.image,
                        source: provider.source,
                        variantName: variant.name
                    )

                    OCRDebugLogger.log(
                        "\(result.source)/\(result.variantName): " +
                        "raw=\(result.cleanedText.prefix(60)) " +
                        "extracted='\(result.extractedText)' " +
                        "mayekCount=\(result.mayekCount) " +
                        "confidence=\(String(format: "%.3f", result.confidence))"
                    )

                    guard result.confidence >= minimumAcceptedConfidence else {
                        providerErrors.append(
                            "\(provider.source)/\(variant.name): rejected low confidence \(result.confidence)"
                        )
                        continue
                    }

                    if !result.cleanedText.isEmpty || !result.extractedText.isEmpty {
                        providerCandidates.append(result)
                    }
                } catch {
                    providerErrors.append("\(provider.source)/\(variant.name): \(error.localizedDescription)")
                }
            }

            allCandidates.append(contentsOf: providerCandidates)

            switch provider.kind {
            case .appleVision:
                if let best = providerCandidates.max(by: isLowerRankedResult),
                   best.mayekCount >= Constants.minimumOnDeviceMayekCount {   // FIX-5
                    OCRDebugLogger.log("Early exit: Apple Vision — mayekCount=\(best.mayekCount)")
                    return best
                }
            case .localMayek:
                if let best = providerCandidates.max(by: isLowerRankedResult),
                   best.mayekCount >= Constants.minimumLocalMayekCount {
                    OCRDebugLogger.log("Early exit: Local Mayek — mayekCount=\(best.mayekCount)")
                    return best
                }
            case .cloudOCR:
                break
            }
        }

        guard let best = allCandidates.max(by: isLowerRankedResult) else {
            let details = providerErrors.isEmpty
                ? ""
                : " Details: \(providerErrors.joined(separator: " | "))"
            throw TransliterationService.ServiceError.ocrFailed(
                "No readable text was returned. Try a clearer crop, brighter lighting, or type text manually.\(details)"
            )
        }

        guard best.mayekCount > 0 else {
            let details = providerErrors.isEmpty
                ? ""
                : " Details: \(providerErrors.joined(separator: " | "))"
            throw TransliterationService.ServiceError.ocrFailed(
                "OCR returned text, but no Meitei Mayek Unicode characters were found. " +
                "Try a tighter crop with only Meitei Mayek text.\(details)"
            )
        }

        return best
    }

    // MARK: - Utilities

    static func sortedReadingOrder(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        blocks.sorted { lhs, rhs in
            guard let lb = lhs.boundingBox, let rb = rhs.boundingBox else {
                return lhs.text < rhs.text
            }
            if abs(lb.midY - rb.midY) > Constants.verticalLineTolerance {
                return lb.midY > rb.midY
            }
            return lb.minX < rb.minX
        }
    }

    static func rejectLowConfidence(
        _ blocks: [OCRTextBlock],
        minimumConfidence: Float = Constants.minimumBlockConfidence
    ) -> [OCRTextBlock] {
        blocks.filter { $0.confidence >= minimumConfidence }
    }

    // MARK: - Private helpers

    private func recognize(
        _ recognizer: OCRRecognizing,
        image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        if let detailed = recognizer as? OCRDetailedRecognizing {
            return try await detailed.recognizeDetailed(from: image, source: source, variantName: variantName)
        }
        let rawText = try await recognizer.recognizeText(from: image)
        return OCRRecognitionResult.fromRawText(
            rawText, source: source, variantName: variantName, confidence: 0.5
        )
    }

    private func isLowerRankedResult(_ lhs: OCRRecognitionResult, _ rhs: OCRRecognitionResult) -> Bool {
        if lhs.mayekCount != rhs.mayekCount   { return lhs.mayekCount  < rhs.mayekCount  }
        if lhs.mayekRatio != rhs.mayekRatio   { return lhs.mayekRatio  < rhs.mayekRatio  }
        if lhs.confidence != rhs.confidence   { return lhs.confidence  < rhs.confidence  }
        return lhs.extractedText.count < rhs.extractedText.count
    }
}
