//
//  TranslatorViewModel.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation
import UIKit
import Combine
import SwiftUI

@MainActor
class TranslatorViewModel: ObservableObject {

    @Published var isLoading: Bool = false
    @Published var currentResult: TransliterationResult? = nil
    @Published var errorMessage: String? = nil
    @Published var history: [TranslationRecord] = []
    @Published var selectedImage: UIImage? = nil
    @Published var typedText: String = ""

    private let service = TransliterationService()
    private let historyKey = "translation_history"

    init() {
        loadHistory()
    }

    func transliterateImage(_ image: UIImage) async {
        isLoading = true
        errorMessage = nil
        currentResult = nil
        selectedImage = image

        do {
            let result = try await service.processImage(image)
            if result.detectedScript.isEmpty {
                errorMessage = "No Meitei Mayek text detected. Try a clearer photo."
            } else {
                currentResult = result
                saveToHistory(result)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func transliterateTypedText() async {
        guard !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter some Meitei Mayek text."
            return
        }

        isLoading = true
        errorMessage = nil
        currentResult = nil

        do {
            let result = try service.transliterateText(typedText)
            currentResult = result
            saveToHistory(result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // Backward-compatible names used by views
    func translateImage(_ image: UIImage) async {
        await transliterateImage(image)
    }

    func translateTypedText() async {
        await transliterateTypedText()
    }

    func reset() {
        currentResult = nil
        errorMessage = nil
        selectedImage = nil
        typedText = ""
    }

    /// Clears input state so the user can transliterate another typed string without leaving the result screen.
    func prepareForAnotherTypedTransliteration(clearText: Bool = true) {
        errorMessage = nil
        if clearText {
            typedText = ""
        }
    }

    private func saveToHistory(_ result: TransliterationResult) {
        guard !result.detectedScript.isEmpty else { return }

        let record = TranslationRecord(
            originalScript: result.detectedScript,
            englishTransliteration: result.englishTransliteration,
            confidence: result.confidence,
            ocrSource: result.ocrSource,
            transliterationEngine: result.transliterationEngine
        )
        history.insert(record, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        persistHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    private func persistHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) {
            history = decoded
        }
    }

    var confidencePercent: String {
        guard let result = currentResult else { return "" }
        return "\(Int(result.confidence * 100))%"
    }

    var confidenceColor: String {
        guard let result = currentResult else { return "gray" }
        switch result.confidence {
        case 0.8...: return "green"
        case 0.5...: return "orange"
        default:     return "red"
        }
    }
}
