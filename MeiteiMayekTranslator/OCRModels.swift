//
//  OCRModels.swift
//  MeiteiMayekTranslator
//

import Foundation
import UIKit

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

struct OCRImageVariant {
    let name: String
    let image: UIImage
}

struct OCRTextCandidate {
    let text: String
    let confidence: Float
}

struct OCRTextBlock {
    let text: String
    let confidence: Float
    let boundingBox: CGRect?
    let candidates: [OCRTextCandidate]
}

struct OCRRecognitionResult {
    let source: String
    let variantName: String
    let extractedText: String
    let cleanedText: String
    let confidence: Float
    let boundingBox: CGRect?
    let rawCandidates: [OCRTextCandidate]
    let textBlocks: [OCRTextBlock]

    var mayekCount: Int {
        MeiteiTextUtilities.mayekCharacterCount(in: extractedText)
    }

    var mayekRatio: Double {
        MeiteiTextUtilities.mayekRatio(in: extractedText)
    }

    var rankScore: Double {
        Double(mayekCount) + mayekRatio + Double(confidence) * 0.25
    }

    static func fromRawText(
        _ rawText: String,
        source: String,
        variantName: String,
        confidence: Float,
        boundingBox: CGRect? = nil,
        blocks: [OCRTextBlock] = []
    ) -> OCRRecognitionResult {
        let cleaned = MeiteiMayekTextCleaner.cleanOCRText(rawText)
        let extracted = MeiteiMayekTextCleaner.extractMayekText(from: cleaned)
        let rawCandidate = OCRTextCandidate(text: rawText, confidence: confidence)
        return OCRRecognitionResult(
            source: source,
            variantName: variantName,
            extractedText: extracted.trimmingCharacters(in: .whitespacesAndNewlines),
            cleanedText: cleaned,
            confidence: confidence,
            boundingBox: boundingBox,
            rawCandidates: blocks.flatMap(\.candidates).isEmpty ? [rawCandidate] : blocks.flatMap(\.candidates),
            textBlocks: blocks
        )
    }
}

