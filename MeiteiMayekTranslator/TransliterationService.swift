//
//  TransliterationService.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation
import UIKit
import Vision

protocol OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String
}

protocol MeiteiRomanizing {
    func romanize(_ text: String) -> String
}

// MARK: - Local transliteration pipeline (no LLM)

/// Scan/type Meitei Mayek → English transliteration using on-device rules.
/// OCR for camera images may use OCR.space (network) or Apple Vision (on-device).
final class TransliterationService {
    enum ServiceError: LocalizedError {
        case ocrFailed(String)
        case transliterationFailed(String)
        case invalidImageData

        var errorDescription: String? {
            switch self {
            case .ocrFailed(let message):
                return "OCR Error: \(message)"
            case .transliterationFailed(let message):
                return "Transliteration Error: \(message)"
            case .invalidImageData:
                return "Could not process image data."
            }
        }
    }

    private let cloudOCR: OCRRecognizing
    private let onDeviceOCR: OCRRecognizing
    private let romanizer: MeiteiRomanizing

    init(
        cloudOCR: OCRRecognizing = OCRSpaceService(),
        onDeviceOCR: OCRRecognizing = VisionOCRService(),
        romanizer: MeiteiRomanizing = MeiteiMayekRomanizer()
    ) {
        self.cloudOCR = cloudOCR
        self.onDeviceOCR = onDeviceOCR
        self.romanizer = romanizer
    }

    func processImage(_ image: UIImage) async throws -> MMTransliterationResult {
        let (rawText, source) = try await recognizeMeiteiText(from: image)
        return try buildResult(from: rawText, ocrSource: source, confidenceBase: 0.85)
    }

    func transliterateText(_ text: String) throws -> MMTransliterationResult {
        try buildResult(from: text, ocrSource: "typed", confidenceBase: 1.0)
    }
    
    func transliterateEnglishToMayek(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServiceError.transliterationFailed("Please enter some text.")
        }
        let mayek = MeiteiMayekReferenceForwardTransliterator.transliterate(trimmed)
        let output = mayek.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw ServiceError.transliterationFailed("Transliteration produced empty output.")
        }
        return output
    }

    // MARK: - OCR (no LLM)

    private func recognizeMeiteiText(from image: UIImage) async throws -> (String, String) {
        var attempts: [(String, String)] = []

        if let text = try? await cloudOCR.recognizeText(from: image) {
            attempts.append((MeiteiTextUtilities.cleanOCRText(text), "OCR.space"))
        }

        if let text = try? await onDeviceOCR.recognizeText(from: image) {
            attempts.append((MeiteiTextUtilities.cleanOCRText(text), "Apple Vision"))
        }

        let ranked = attempts
            .map { normalizeOCRAttempt($0.0, source: $0.1) }
            .filter { !$0.0.isEmpty }

        guard let best = ranked.max(by: { $0.2 < $1.2 }) else {
            throw ServiceError.ocrFailed(
                "No Meitei Mayek text detected. Use a clearer crop, good lighting, or type text manually."
            )
        }

        if best.2 < 2 {
            throw ServiceError.ocrFailed(
                "OCR did not detect Meitei Mayek script. Try a tighter crop or use Type text."
            )
        }

        return (best.0, best.1)
    }

    private func normalizeOCRAttempt(_ raw: String, source: String) -> (String, String, Int) {
        let cleaned = MeiteiTextUtilities.cleanOCRText(raw)
        let extracted = MeiteiTextUtilities.extractMayekScript(from: cleaned)
        let text = extracted.isEmpty ? cleaned : extracted
        let count = MeiteiTextUtilities.mayekCharacterCount(in: text)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), source, count)
    }

    // MARK: - On-device transliteration

    private func buildResult(
        from sourceText: String,
        ocrSource: String,
        confidenceBase: Double
    ) throws -> MMTransliterationResult {
        let trimmed = MeiteiTextUtilities.cleanOCRText(sourceText)
        guard !trimmed.isEmpty else {
            throw ServiceError.transliterationFailed("No text to transliterate.")
        }

        let mayekText = MeiteiTextUtilities.extractMayekScript(from: trimmed)
        let sourceForTransliteration = mayekText.isEmpty ? trimmed : mayekText

        guard MeiteiTextUtilities.containsMayek(sourceForTransliteration) else {
            throw ServiceError.transliterationFailed(
                "Input does not appear to be Meitei Mayek. Paste or scan Meitei Mayek script only."
            )
        }

        let english = romanizer.romanize(sourceForTransliteration)
        guard !english.isEmpty else {
            throw ServiceError.transliterationFailed("Transliteration produced empty output.")
        }
        guard MeiteiTextUtilities.isEnglishAlphabetTransliteration(english) else {
            throw ServiceError.transliterationFailed(
                "Could not convert to English letters. Try typing Meitei Mayek in the Type text screen."
            )
        }

        let mayekRatio = MeiteiTextUtilities.mayekRatio(in: sourceForTransliteration)
        let confidence = min(1.0, confidenceBase * (0.6 + 0.4 * mayekRatio))

        return MMTransliterationResult(
            detectedScript: sourceForTransliteration,
            englishTransliteration: english,
            confidence: confidence,
            ocrSource: ocrSource,
            transliterationEngine: "On-device"
        )
    }
}

typealias FreeTranslationService = TransliterationService

// MARK: - OCR.space (network OCR, not an LLM)

final class OCRSpaceService: OCRRecognizing {
    private let ocrAPIKey = "K84627195888957"
    private let ocrURL = URL(string: "https://api.ocr.space/parse/image")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    func recognizeText(from image: UIImage) async throws -> String {
        guard let primaryData = compressImage(image, toMaxBytes: Int(1.0 * 1024 * 1024)) else {
            throw TransliterationService.ServiceError.invalidImageData
        }

        do {
            return try await submitOCRRequest(imageData: primaryData)
        } catch let error as URLError where error.code == .timedOut {
            guard let retryData = compressImage(image, toMaxBytes: Int(600 * 1024)) else {
                throw TransliterationService.ServiceError.ocrFailed("OCR timed out and retry preparation failed.")
            }
            return try await submitOCRRequest(imageData: retryData)
        }
    }

    private func submitOCRRequest(imageData: Data) async throws -> String {
        let dataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        var request = URLRequest(url: ocrURL, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(ocrAPIKey, forHTTPHeaderField: "apikey")
        request.httpBody = formURLEncoded([
            "base64image": dataURL,
            "OCREngine": "2",
            "isOverlayRequired": "false",
            "scale": "true",
        ]).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? "No details"
            throw TransliterationService.ServiceError.ocrFailed("OCR.space error \(code): \(message)")
        }

        let result = try JSONDecoder().decode(OCRSpaceResponse.self, from: data)
        if result.IsErroredOnProcessing {
            throw TransliterationService.ServiceError.ocrFailed(result.ErrorMessage?.first ?? "OCR processing failed.")
        }

        let parsed = result.ParsedResults?
            .compactMap(\.ParsedText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !parsed.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed("OCR.space returned empty text.")
        }
        return parsed
    }

    private func compressImage(_ image: UIImage, toMaxBytes maxBytes: Int) -> Data? {
        var workingImage = normalizedImage(image)
        workingImage = downscaledImage(workingImage, maxDimension: 1600)
        var compression: CGFloat = 0.75
        var data = workingImage.jpegData(compressionQuality: compression)

        while (data?.count ?? 0) > maxBytes && compression > 0.2 {
            compression -= 0.1
            data = workingImage.jpegData(compressionQuality: compression)
        }

        while (data?.count ?? 0) > maxBytes {
            let newSize = CGSize(width: workingImage.size.width * 0.8, height: workingImage.size.height * 0.8)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            workingImage.draw(in: CGRect(origin: .zero, size: newSize))
            workingImage = UIGraphicsGetImageFromCurrentImageContext() ?? workingImage
            UIGraphicsEndImageContext()
            data = workingImage.jpegData(compressionQuality: 0.45)
        }
        return data
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }

    private func downscaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized ?? image
    }

    private func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters.map { "\(formEncode($0.key))=\(formEncode($0.value))" }.joined(separator: "&")
    }

    private func formEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - Apple Vision OCR (on-device)

final class VisionOCRService: OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String {
        var cgImage = image.cgImage
        if cgImage == nil, let ci = CIImage(image: image) {
            cgImage = CIContext().createCGImage(ci, from: ci.extent)
        }
        guard let cgImage else {
            throw TransliterationService.ServiceError.invalidImageData
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OCRSpaceResponse: Codable {
    let ParsedResults: [ParsedResult]?
    let IsErroredOnProcessing: Bool
    let ErrorMessage: [String]?

    struct ParsedResult: Codable {
        let ParsedText: String?
    }
}
