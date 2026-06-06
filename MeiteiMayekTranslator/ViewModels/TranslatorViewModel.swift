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
import AVFoundation

@MainActor
class TranslatorViewModel: ObservableObject {
    
    private let synthesizer = AVSpeechSynthesizer()

    @Published var isLoading: Bool = false
    @Published var currentResult: MMTransliterationResult? = nil
    @Published var errorMessage: String? = nil
    @Published var history: [TranslationRecord] = []
    @Published var selectedImage: UIImage? = nil
    @Published var mayekTypedText: String = ""
    @Published var englishTypedText: String = ""

    enum TransliterationMode: String, CaseIterable {
        case mayekToEnglish
        case englishToMayek
    }

    @Published var mode: TransliterationMode = .mayekToEnglish
    @Published var forwardOutput: String? = nil

    private var activeInput: String {
        mode == .mayekToEnglish ? mayekTypedText : englishTypedText
    }

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
        let input = activeInput
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter some Meitei Mayek text."
            return
        }

        isLoading = true
        errorMessage = nil
        currentResult = nil

        do {
            let result = try service.transliterateText(input)
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
        let input = activeInput
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter some text."
            return
        }

        isLoading = true
        errorMessage = nil
        
        // Only clear the result for the current mode
        if mode == .mayekToEnglish {
            currentResult = nil
        } else {
            forwardOutput = nil
        }

        do {
            switch mode {
            case .mayekToEnglish:
                let result = try service.transliterateText(input)
                currentResult = result
                saveToHistory(result)
            case .englishToMayek:
                let output = try service.transliterateEnglishToMayek(input)
                forwardOutput = output
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reset() {
        currentResult = nil
        errorMessage = nil
        selectedImage = nil
        mayekTypedText = ""
        englishTypedText = ""
        forwardOutput = nil
    }

    /// Clears input state so the user can transliterate another typed string without leaving the result screen.
    func prepareForAnotherTypedTransliteration(clearText: Bool = true) {
        errorMessage = nil
        if clearText {
            if mode == .mayekToEnglish {
                mayekTypedText = ""
            } else {
                englishTypedText = ""
            }
        }
    }

    private func saveToHistory(_ result: MMTransliterationResult) {
        guard !result.detectedScript.isEmpty else { return }

        let record = TranslationRecord(from: result)
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

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        // Ensure audio plays even if the silent switch is on
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        synthesizer.speak(utterance)
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

