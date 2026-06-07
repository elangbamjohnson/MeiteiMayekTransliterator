//
//  VisionOCRService.swift
//  MeiteiMayekTranslator
//
//  Extracted from TransliterationService.swift (was 900-line monolith).
//

import Foundation
import UIKit
import Vision

/// On-device OCR using Apple Vision framework.
///
/// Apple Vision does NOT have built-in support for Meetei Mayek, so it runs in
/// script-agnostic mode (`usesLanguageCorrection = false`, no `recognitionLanguages`
/// set). The resulting raw Unicode output is then filtered by `MeiteiMayekTextCleaner`.
nonisolated final class VisionOCRService: OCRDetailedRecognizing {

    // MARK: - OCRRecognizing (simple entry point)

    /// BUG FIX #9: previously returned `cleanedText` — inconsistent with every
    /// other provider's `recognizeText`, which returns the raw / extracted text.
    /// Changed to return `extractedText` so callers of the bare protocol get
    /// the same kind of value regardless of which concrete type they hold.
    func recognizeText(from image: UIImage) async throws -> String {
        try await recognizeDetailed(from: image, source: "Apple Vision", variantName: "direct")
            .extractedText
    }

    // MARK: - OCRDetailedRecognizing

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        guard let cgImage = resolvedCGImage(from: image) else {
            throw TransliterationService.ServiceError.invalidImageData
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel      = .accurate
        request.usesLanguageCorrection = false   // language correction damages Mayek Unicode
        request.minimumTextHeight     = 0.01     // catch small glyphs
        if let latestRevision = VNRecognizeTextRequest.supportedRevisions.max() {
            request.revision = latestRevision
        }

        // Pass the correct EXIF orientation so Vision doesn't mis-interpret rotated
        // camera frames (uses UIImage.cgImagePropertyOrientation from OCRImagePreprocessor).
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
        try handler.perform([request])

        let blocks = OCRService.sortedReadingOrder(
            (request.results ?? []).compactMap { observation in
                let candidates = observation.topCandidates(3).map {
                    OCRTextCandidate(text: $0.string, confidence: $0.confidence)
                }
                guard let best = candidates.first else { return nil }
                return OCRTextBlock(
                    text: best.text,
                    confidence: best.confidence,
                    boundingBox: observation.boundingBox,
                    candidates: candidates
                )
            }
        )

        let acceptedBlocks = OCRService.rejectLowConfidence(blocks)
        let rawText = acceptedBlocks
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed(
                "Apple Vision returned no readable text."
            )
        }

        let avgConfidence: Float = acceptedBlocks.isEmpty
            ? 0
            : acceptedBlocks.map(\.confidence).reduce(0, +) / Float(acceptedBlocks.count)

        return OCRRecognitionResult.fromRawText(
            rawText,
            source: source,
            variantName: variantName,
            confidence: avgConfidence,
            boundingBox: combinedBoundingBox(from: acceptedBlocks),
            blocks: acceptedBlocks
        )
    }

    // MARK: - Helpers

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    private func combinedBoundingBox(from blocks: [OCRTextBlock]) -> CGRect? {
        let boxes = blocks.compactMap(\.boundingBox)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}
