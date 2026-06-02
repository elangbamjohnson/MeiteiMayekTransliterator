//
//  TranslationRecord.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

/// Result of scan or typed-input transliteration pipeline.
struct TransliterationResult {
    let detectedScript: String
    let englishTransliteration: String
    let confidence: Double
    let ocrSource: String?
    let transliterationEngine: String
}

/// Backward-compatible alias used across the app target.
typealias OCRTranslationResult = TransliterationResult

struct TranslationRecord: Identifiable, Codable {
    let id: UUID
    let originalScript: String
    let englishTransliteration: String
    let confidence: Double
    let ocrSource: String?
    let transliterationEngine: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        originalScript: String,
        englishTransliteration: String,
        confidence: Double,
        ocrSource: String? = nil,
        transliterationEngine: String = "On-device",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalScript = originalScript
        self.englishTransliteration = englishTransliteration
        self.confidence = confidence
        self.ocrSource = ocrSource
        self.transliterationEngine = transliterationEngine
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case originalScript
        case englishTransliteration
        case latinTransliteration
        case romanizedText
        case englishPronunciation
        case translatedText
        case confidence
        case ocrSource
        case transliterationEngine
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        originalScript = try container.decode(String.self, forKey: .originalScript)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        ocrSource = try container.decodeIfPresent(String.self, forKey: .ocrSource)
        transliterationEngine = try container.decodeIfPresent(String.self, forKey: .transliterationEngine) ?? "On-device"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        if let english = try container.decodeIfPresent(String.self, forKey: .englishTransliteration), !english.isEmpty {
            englishTransliteration = english
        } else if let latin = try container.decodeIfPresent(String.self, forKey: .latinTransliteration), !latin.isEmpty {
            englishTransliteration = latin
        } else if let romanized = try container.decodeIfPresent(String.self, forKey: .romanizedText), !romanized.isEmpty {
            englishTransliteration = romanized
        } else if let pronunciation = try container.decodeIfPresent(String.self, forKey: .englishPronunciation), !pronunciation.isEmpty {
            englishTransliteration = pronunciation
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .translatedText), !legacy.isEmpty {
            englishTransliteration = legacy
        } else {
            englishTransliteration = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalScript, forKey: .originalScript)
        try container.encode(englishTransliteration, forKey: .englishTransliteration)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(ocrSource, forKey: .ocrSource)
        try container.encode(transliterationEngine, forKey: .transliterationEngine)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
