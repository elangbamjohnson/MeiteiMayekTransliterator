//
//  OCRSpaceService.swift
//  MeiteiMayekTranslator
//
//  Extracted from TransliterationService.swift (was 900-line monolith).
//

import Foundation
import UIKit

/// Cloud OCR via OCR.space (Engine 2 — best for non-Latin scripts).
///
/// OCR.space does not natively support Meetei Mayek, so results are filtered
/// by `MeiteiMayekTextCleaner` after the call. Because the API returns no
/// per-character confidence score, all results use `OCRRecognitionResult.syntheticCloudConfidence`.
final class OCRSpaceService: OCRDetailedRecognizing {

    // MARK: - Configuration

    private let ocrAPIKey = "K84627195888957"
    private let ocrURL    = URL(string: "https://api.ocr.space/parse/image")!

    /// Upload cap: OCR.space free tier rejects payloads above ~1 MB.
    private let primaryUploadByteCap  = Int(1.0 * 1_024 * 1_024)
    /// Retry cap after a timeout — smaller payload = faster round-trip.
    private let retryUploadByteCap    = Int(600 * 1_024)
    /// Downscale before compressing; avoids sending 4K images to a free-tier API.
    private let maximumUploadDimension: CGFloat = 1_600

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 45
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity       = true
        return URLSession(configuration: config)
    }()

    // MARK: - OCRRecognizing

    func recognizeText(from image: UIImage) async throws -> String {
        try await recognizeDetailed(from: image, source: "OCR.space", variantName: "direct")
            .cleanedText
    }

    // MARK: - OCRDetailedRecognizing

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        guard let primaryData = compressImage(image, toMaxBytes: primaryUploadByteCap) else {
            throw TransliterationService.ServiceError.invalidImageData
        }

        let text: String
        do {
            text = try await submitOCRRequest(imageData: primaryData.data, mimeType: primaryData.mimeType)
        } catch let error as URLError where error.code == .timedOut {
            guard let retryData = compressImage(image, toMaxBytes: retryUploadByteCap) else {
                throw TransliterationService.ServiceError.ocrFailed(
                    "OCR timed out and retry preparation failed."
                )
            }
            text = try await submitOCRRequest(imageData: retryData.data, mimeType: retryData.mimeType)
        }

        // BUG FIX #10: use the named constant so the synthetic confidence is visible
        // and searchable rather than a bare 0.45 literal.
        return OCRRecognitionResult.fromRawText(
            text,
            source: source,
            variantName: variantName,
            confidence: OCRRecognitionResult.syntheticCloudConfidence
        )
    }

    // MARK: - Network

    private func submitOCRRequest(imageData: Data, mimeType: String) async throws -> String {
        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        var request = URLRequest(url: ocrURL, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(ocrAPIKey, forHTTPHeaderField: "apikey")
        request.httpBody = formURLEncoded([
            "base64image":       dataURL,
            "OCREngine":         "2",
            "isOverlayRequired": "false",
            "scale":             "true",
        ]).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code    = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? "No details"
            throw TransliterationService.ServiceError.ocrFailed("OCR.space error \(code): \(message)")
        }

        let result = try JSONDecoder().decode(OCRSpaceResponse.self, from: data)
        if result.IsErroredOnProcessing {
            throw TransliterationService.ServiceError.ocrFailed(
                result.ErrorMessage?.first ?? "OCR processing failed."
            )
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

    // MARK: - Image compression

    private func compressImage(_ image: UIImage, toMaxBytes maxBytes: Int) -> (data: Data, mimeType: String)? {
        // Normalise orientation first, then downscale.
        var working = normalizedImage(image)
        working     = downscaledImage(working, maxDimension: maximumUploadDimension)

        // Prefer PNG (lossless) when it fits.
        if let png = working.pngData(), png.count <= maxBytes {
            return (png, "image/png")
        }

        // Progressively lower JPEG quality.
        var compression: CGFloat = 0.75
        while compression > 0.2 {
            if let jpeg = working.jpegData(compressionQuality: compression),
               jpeg.count <= maxBytes {
                return (jpeg, "image/jpeg")
            }
            compression -= 0.1
        }

        // Last resort: shrink the image itself.
        while true {
            let newSize = CGSize(width: working.size.width * 0.8, height: working.size.height * 0.8)
            working = UIGraphicsImageRenderer(size: newSize).image { _ in
                working.draw(in: CGRect(origin: .zero, size: newSize))
            }
            if let jpeg = working.jpegData(compressionQuality: 0.45), jpeg.count <= maxBytes {
                return (jpeg, "image/jpeg")
            }
            if working.size.width < 100 { return nil }   // give up at thumbnail size
        }
    }

    // BUG FIX #11: replaced deprecated UIGraphicsBeginImageContextWithOptions
    // with UIGraphicsImageRenderer throughout.

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        return UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func downscaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale   = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - URL encoding

    private func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters.map { "\(formEncode($0.key))=\(formEncode($0.value))" }.joined(separator: "&")
    }

    private func formEncode(_ string: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - OCR.space response model

struct OCRSpaceResponse: Codable {
    let ParsedResults: [ParsedResult]?
    let IsErroredOnProcessing: Bool
    let ErrorMessage: [String]?

    struct ParsedResult: Codable {
        let ParsedText: String?
    }
}
