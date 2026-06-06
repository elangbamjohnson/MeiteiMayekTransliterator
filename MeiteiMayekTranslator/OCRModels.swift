//
//  OCRModels.swift
//  MeiteiMayekTranslator
//

import Foundation
import UIKit

// MARK: - Protocols

protocol OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String
}

protocol OCRDetailedRecognizing: OCRRecognizing {
    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult
}

protocol OCRImagePreparing {
    func variants(for image: UIImage) -> [OCRImageVariant]
}

// MARK: - Value types
// BUG FIX #7: mark all structs Sendable so they compile cleanly under Swift 6
// strict concurrency — they cross async task boundaries in OCRService.

struct OCRImageVariant: Sendable {
    let name: String
    let image: UIImage
}

struct OCRTextCandidate: Sendable {
    let text: String
    let confidence: Float
}

struct OCRTextBlock: Sendable {
    let text: String
    let confidence: Float
    /// Vision bounding boxes use normalised coords (0–1, Y=0 at bottom).
    /// Cloud-provider blocks set this to nil since no spatial data is available.
    let boundingBox: CGRect?
    let candidates: [OCRTextCandidate]
}

// MARK: - Recognition result

struct OCRRecognitionResult: Sendable {

    // MARK: Constants

    /// Synthetic confidence assigned to cloud-provider results when the API returns
    /// no per-character score. Named here so callers that build on it can reason
    /// about the assumption.
    static let syntheticCloudConfidence: Float = 0.45

    // MARK: Stored

    let source: String
    let variantName: String
    let extractedText: String
    let cleanedText: String
    let confidence: Float
    let boundingBox: CGRect?
    let rawCandidates: [OCRTextCandidate]
    let textBlocks: [OCRTextBlock]

    // MARK: Computed

    var mayekCount: Int {
        MeiteiTextUtilities.mayekCharacterCount(in: extractedText)
    }

    /// Fraction of scalars in extractedText that fall within a Mayek Unicode block (0–1).
    var mayekRatio: Double {
        MeiteiTextUtilities.mayekRatio(in: extractedText)
    }

    /// Composite ranking score used by OCRService to pick the best candidate.
    ///
    /// BUG FIX #8: the previous formula mixed incompatible scales — a raw character
    /// count, a 0–1 ratio, and a weighted float. A text with 3 Mayek characters could
    /// beat one with 0 characters + confidence 0.99 purely from the count integer.
    ///
    /// Fixed formula normalises all three components to comparable magnitudes:
    ///   • mayekCount  (primary)  — weighted at 1.0 per character, most influential
    ///   • mayekRatio  (secondary) — already 0–1, weight 2.0 to make it meaningful
    ///   • confidence  (tertiary) — Float 0–1, weight 0.5 as a tie-breaker
    var rankScore: Double {
        let countScore   = Double(mayekCount)  * 1.0
        let ratioScore   = mayekRatio          * 2.0
        let confScore    = Double(confidence)  * 0.5
        return countScore + ratioScore + confScore
    }

    // MARK: Factory

    /// Creates a result by running the standard Meitei Mayek cleaning + extraction
    /// pipeline on `rawText`. All providers should use this factory so the pipeline
    /// cannot drift between providers.
    static func fromRawText(
        _ rawText: String,
        source: String,
        variantName: String,
        confidence: Float,
        boundingBox: CGRect? = nil,
        blocks: [OCRTextBlock] = []
    ) -> OCRRecognitionResult {
        let cleaned   = MeiteiMayekTextCleaner.cleanOCRText(rawText)
        let extracted = MeiteiMayekTextCleaner.extractMayekText(from: cleaned)
        let rawCandidate = OCRTextCandidate(text: rawText, confidence: confidence)

        let rawCandidates = blocks.flatMap(\.candidates).isEmpty
            ? [rawCandidate]
            : blocks.flatMap(\.candidates)

        return OCRRecognitionResult(
            source: source,
            variantName: variantName,
            extractedText: extracted.trimmingCharacters(in: .whitespacesAndNewlines),
            cleanedText: cleaned,
            confidence: confidence,
            boundingBox: boundingBox,
            rawCandidates: rawCandidates,
            textBlocks: blocks
        )
    }
}
