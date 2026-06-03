import Foundation

struct MMTransliterationResult: Identifiable, Codable {
    let id: UUID
    let detectedScript: String
    let englishTransliteration: String
    let confidence: Double
    let ocrSource: String?
    let transliterationEngine: String?
    let createdAt: Date

    // UI accessors
    var romanizedText: String { englishTransliteration }
    var englishPronunciation: String { MeiteiMayekEnglishFormatter.format(englishTransliteration) }

    init(
        detectedScript: String,
        englishTransliteration: String,
        confidence: Double,
        ocrSource: String? = nil,
        transliterationEngine: String? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.detectedScript = detectedScript
        self.englishTransliteration = englishTransliteration
        self.confidence = confidence
        self.ocrSource = ocrSource
        self.transliterationEngine = transliterationEngine
        self.createdAt = createdAt
    }
}

