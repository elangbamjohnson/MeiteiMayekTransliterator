//
//  TransliterationService.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation
import UIKit
import CoreImage
import Vision

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

    private let ocrService: OCRService
    private let romanizer: MeiteiRomanizing

    init(
        cloudOCR: OCRRecognizing = OCRSpaceService(),
        onDeviceOCR: OCRRecognizing = VisionOCRService(),
        localImageOCR: OCRRecognizing = LocalMayekGlyphRecognizer(),
        romanizer: MeiteiRomanizing = MeiteiMayekRomanizer(),
        imagePreprocessor: OCRImagePreparing = DefaultOCRImagePreprocessor()
    ) {
        self.ocrService = OCRService(
            cloudOCR: cloudOCR,
            onDeviceOCR: onDeviceOCR,
            localImageOCR: localImageOCR,
            imagePreprocessor: imagePreprocessor
        )
        self.romanizer = romanizer
    }

    func processImage(_ image: UIImage) async throws -> MMTransliterationResult {
        let recognition = try await ocrService.recognizeMeiteiText(from: image)
        return try buildResult(
            from: recognition.extractedText,
            ocrSource: "\(recognition.source) / \(recognition.variantName)",
            confidenceBase: Double(recognition.confidence)
        )
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

// MARK: - Local Meitei Mayek glyph OCR

final class LocalMayekGlyphRecognizer: OCRDetailedRecognizing {
    private let segmenter = MayekGlyphSegmenter()
    private let classifier = MayekGlyphClassifier()

    func recognizeText(from image: UIImage) async throws -> String {
        try await recognizeDetailed(from: image, source: "Local Mayek", variantName: "direct").extractedText
    }

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        let segments = segmenter.segments(from: image)
        guard !segments.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed("Local Mayek OCR found no dark glyph segments.")
        }

        var output = ""
        var blocks: [OCRTextBlock] = []

        for (index, segment) in segments.enumerated() {
            if let match = classifier.recognize(segment.image) {
                output += match.text
                let confidence = max(0.0, min(1.0, Float(1.0 - match.distance)))
                let candidate = OCRTextCandidate(text: match.text, confidence: confidence)
                blocks.append(
                    OCRTextBlock(
                        text: match.text,
                        confidence: confidence,
                        boundingBox: segment.bounds,
                        candidates: [candidate]
                    )
                )
                OCRDebugLogger.log("Local segment \(index + 1): \(match.text), distance=\(match.distance)")
            } else {
                OCRDebugLogger.log("Local segment \(index + 1): no match")
            }
        }

        guard !output.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed(
                "Local Mayek OCR could not classify glyphs. Segments: \(segments.count)."
            )
        }

        let confidence = blocks.isEmpty ? 0.0 : blocks.map(\.confidence).reduce(0, +) / Float(blocks.count)
        return OCRRecognitionResult.fromRawText(
            output,
            source: source,
            variantName: variantName,
            confidence: confidence,
            boundingBox: combinedBoundingBox(from: blocks),
            blocks: blocks
        )
    }

    private func combinedBoundingBox(from blocks: [OCRTextBlock]) -> CGRect? {
        let boxes = blocks.compactMap(\.boundingBox)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}

private struct MayekGlyphSegment {
    let image: UIImage
    let bounds: CGRect
}

private struct MayekGlyphSegmenter {
    private let maxDimension: CGFloat = 640

    func segments(from image: UIImage) -> [MayekGlyphSegment] {
        guard let rendered = render(image, maxDimension: maxDimension),
              let bounds = darkPixelBounds(in: rendered.pixels, width: rendered.width, height: rendered.height) else {
            return []
        }

        let projection = verticalProjection(
            in: bounds,
            pixels: rendered.pixels,
            width: rendered.width,
            darkThreshold: rendered.darkThreshold
        )
        let ranges = darkColumnRanges(from: projection, bounds: bounds)
        let segmentBounds = ranges.map { range -> CGRect in
            let paddedX = max(bounds.minX, CGFloat(range.lowerBound) - 3)
            let paddedWidth = min(bounds.maxX, CGFloat(range.upperBound) + 3) - paddedX
            return CGRect(x: paddedX, y: bounds.minY, width: max(1, paddedWidth), height: bounds.height)
        }

        return segmentBounds.compactMap { rect in
            guard let image = cropRenderedImage(rendered, to: rect) else { return nil }
            return MayekGlyphSegment(image: image, bounds: rect)
        }
    }

    private func render(_ image: UIImage, maxDimension: CGFloat) -> (pixels: [UInt8], width: Int, height: Int, darkThreshold: UInt8)? {
        guard let source = resolvedCGImage(from: image) else { return nil }
        let longest = CGFloat(max(source.width, source.height))
        let scale = min(1.0, maxDimension / longest)
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = Array(repeating: UInt8(255), count: height * bytesPerRow)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var grayscale = Array(repeating: UInt8(255), count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(data[offset])
                let green = Double(data[offset + 1])
                let blue = Double(data[offset + 2])
                let alpha = Double(data[offset + 3]) / 255.0
                let luminance = UInt8((0.299 * red + 0.587 * green + 0.114 * blue) * alpha + 255.0 * (1.0 - alpha))
                grayscale[y * width + x] = luminance
            }
        }

        return (grayscale, width, height, adaptiveDarkThreshold(for: grayscale))
    }

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }
        guard let ciImage = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    private func darkPixelBounds(in pixels: [UInt8], width: Int, height: Int) -> CGRect? {
        let darkThreshold = adaptiveDarkThreshold(for: pixels)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundDarkPixel = false

        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < darkThreshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                foundDarkPixel = true
            }
        }

        guard foundDarkPixel else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }

    private func verticalProjection(
        in bounds: CGRect,
        pixels: [UInt8],
        width: Int,
        darkThreshold: UInt8
    ) -> [Int] {
        let minX = Int(bounds.minX)
        let maxX = Int(bounds.maxX)
        let minY = Int(bounds.minY)
        let maxY = Int(bounds.maxY)

        return (minX..<maxX).map { x in
            var count = 0
            for y in minY..<maxY where pixels[y * width + x] < darkThreshold {
                count += 1
            }
            return count
        }
    }

    private func darkColumnRanges(from projection: [Int], bounds: CGRect) -> [Range<Int>] {
        let minX = Int(bounds.minX)
        let height = max(1, Int(bounds.height))
        let minimumInk = max(2, height / 20)
        let minimumGap = 4
        var ranges: [Range<Int>] = []
        var start: Int?
        var lastDarkColumn: Int?
        var gap = 0

        for (offset, count) in projection.enumerated() {
            let x = minX + offset
            if count >= minimumInk {
                if start == nil {
                    start = x
                }
                lastDarkColumn = x
                gap = 0
            } else if start != nil {
                gap += 1
                if gap >= minimumGap, let rangeStart = start, let rangeEnd = lastDarkColumn {
                    ranges.append(rangeStart..<(rangeEnd + 1))
                    start = nil
                    lastDarkColumn = nil
                    gap = 0
                }
            }
        }

        if let rangeStart = start, let rangeEnd = lastDarkColumn {
            ranges.append(rangeStart..<(rangeEnd + 1))
        }

        return mergeSmallRanges(ranges)
    }

    private func mergeSmallRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        var result: [Range<Int>] = []
        for range in ranges {
            if range.count < 8, let last = result.popLast() {
                result.append(last.lowerBound..<range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private func cropRenderedImage(
        _ rendered: (pixels: [UInt8], width: Int, height: Int, darkThreshold: UInt8),
        to rect: CGRect
    ) -> UIImage? {
        let width = max(1, Int(rect.width))
        let height = max(1, Int(rect.height))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = Array(repeating: UInt8(255), count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let sourceX = min(rendered.width - 1, max(0, Int(rect.minX) + x))
                let sourceY = min(rendered.height - 1, max(0, Int(rect.minY) + y))
                let value = rendered.pixels[sourceY * rendered.width + sourceX]
                let offset = y * bytesPerRow + x * bytesPerPixel
                data[offset] = value
                data[offset + 1] = value
                data[offset + 2] = value
                data[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func adaptiveDarkThreshold(for pixels: [UInt8]) -> UInt8 {
        var histogram = Array(repeating: 0, count: 256)
        for pixel in pixels {
            histogram[Int(pixel)] += 1
        }

        let total = pixels.count
        var weightedSum = 0
        for value in 0..<histogram.count {
            weightedSum += value * histogram[value]
        }

        var backgroundWeight = 0
        var backgroundSum = 0
        var bestVariance = 0.0
        var threshold = 127

        for value in 0..<histogram.count {
            backgroundWeight += histogram[value]
            guard backgroundWeight > 0 else { continue }

            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else { break }

            backgroundSum += value * histogram[value]
            let backgroundMean = Double(backgroundSum) / Double(backgroundWeight)
            let foregroundMean = Double(weightedSum - backgroundSum) / Double(foregroundWeight)
            let variance = Double(backgroundWeight) * Double(foregroundWeight) * pow(backgroundMean - foregroundMean, 2)

            if variance > bestVariance {
                bestVariance = variance
                threshold = value
            }
        }

        return UInt8(max(80, min(180, threshold)))
    }
}

private final class MayekGlyphClassifier {
    struct Match {
        let text: String
        let distance: Double
    }

    private let signatureBuilder = BinaryImageSignatureBuilder(columns: 32, rows: 32)
    private let maximumDistance = 0.46
    private lazy var templates: [(text: String, signature: BinaryImageSignature)] = buildTemplates()

    func recognize(_ image: UIImage) -> Match? {
        guard let inputSignature = signatureBuilder.signature(for: image) else { return nil }
        var best: Match?

        for template in templates {
            let distance = inputSignature.distanceRatio(to: template.signature)
            if best == nil || distance < best!.distance {
                best = Match(text: template.text, distance: distance)
            }
        }

        guard let best, best.distance <= maximumDistance else { return nil }
        return best
    }

    private func buildTemplates() -> [(text: String, signature: BinaryImageSignature)] {
        sampleTemplates() + templateTexts().compactMap { text in
            guard let image = renderTemplate(text),
                  let signature = signatureBuilder.signature(for: image) else {
                return nil
            }
            return (text, signature)
        }
    }

    private func sampleTemplates() -> [(text: String, signature: BinaryImageSignature)] {
        guard let image = UIImage(named: "meitei_mayek_nupi") else {
            return []
        }

        let labels = ["ꯅꯨ", "ꯞꯤ"]
        let segments = MayekGlyphSegmenter().segments(from: image)
        guard segments.count == labels.count else {
            return []
        }

        return zip(labels, segments).compactMap { label, segment in
            guard let signature = signatureBuilder.signature(for: segment.image) else {
                return nil
            }
            return (label, signature)
        }
    }

    private func templateTexts() -> [String] {
        let baseCharacters = [
            "ꯀ", "ꯁ", "ꯂ", "ꯃ", "ꯄ", "ꯅ", "ꯆ", "ꯇ", "ꯈ", "ꯉ", "ꯊ", "ꯋ", "ꯌ",
            "ꯍ", "ꯎ", "ꯏ", "ꯐ", "ꯑ", "ꯒ", "ꯓ", "ꯔ", "ꯕ", "ꯖ", "ꯗ", "ꯘ", "ꯙ",
            "ꯚ", "ꯛ", "ꯜ", "ꯝ", "ꯞ", "ꯟ", "ꯠ", "ꯡ", "ꯢ",
        ]
        let combiningSigns = ["ꯣ", "ꯤ", "ꯥ", "ꯦ", "ꯧ", "ꯨ", "ꯩ", "ꯪ"]
        var values = baseCharacters + combiningSigns

        for base in baseCharacters {
            for sign in combiningSigns {
                values.append(base + sign)
            }
        }

        // Common clusters seen in scanned words. These are still character-level outputs,
        // unlike whole-image word recognition.
        values.append(contentsOf: ["ꯅꯨ", "ꯞꯤ"])

        return Array(Set(values)).sorted { $0.count > $1.count }
    }

    private func renderTemplate(_ text: String) -> UIImage? {
        let size = CGSize(width: 220, height: 220)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 150, weight: .bold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributed.size()
            let rect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attributed.draw(in: rect)
        }
    }
}

private struct BinaryImageSignature {
    let words: [UInt64]
    let bitCount: Int

    func distanceRatio(to other: BinaryImageSignature) -> Double {
        guard bitCount == other.bitCount, words.count == other.words.count else { return 1 }
        var distance = 0
        for index in words.indices {
            distance += Int((words[index] ^ other.words[index]).nonzeroBitCount)
        }
        return Double(distance) / Double(bitCount)
    }
}

private struct BinaryImageSignatureBuilder {
    let columns: Int
    let rows: Int

    func signature(for image: UIImage) -> BinaryImageSignature? {
        guard let cgImage = resolvedCGImage(from: image),
              let pixels = grayscalePixels(from: cgImage) else {
            return nil
        }

        let darkThreshold = adaptiveDarkThreshold(for: pixels)
        guard let bounds = darkPixelBounds(
            in: pixels,
            width: cgImage.width,
            height: cgImage.height,
            darkThreshold: darkThreshold
        ) else {
            return nil
        }

        let bitCount = columns * rows
        var words = Array(repeating: UInt64(0), count: Int(ceil(Double(bitCount) / 64.0)))

        for row in 0..<rows {
            for column in 0..<columns {
                let darkRatio = darkRatioForCell(
                    pixels: pixels,
                    imageWidth: cgImage.width,
                    bounds: bounds,
                    column: column,
                    row: row,
                    darkThreshold: darkThreshold
                )
                guard darkRatio >= 0.12 else { continue }

                let bitIndex = row * columns + column
                words[bitIndex / 64] |= UInt64(1) << UInt64(bitIndex % 64)
            }
        }

        return BinaryImageSignature(words: words, bitCount: bitCount)
    }

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }
        guard let ciImage = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    private func grayscalePixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = Array(repeating: UInt8(255), count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var grayscale = Array(repeating: UInt8(255), count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(data[offset])
                let green = Double(data[offset + 1])
                let blue = Double(data[offset + 2])
                let alpha = Double(data[offset + 3]) / 255.0
                let luminance = UInt8((0.299 * red + 0.587 * green + 0.114 * blue) * alpha + 255.0 * (1.0 - alpha))
                grayscale[y * width + x] = luminance
            }
        }

        return grayscale
    }

    private func darkPixelBounds(
        in pixels: [UInt8],
        width: Int,
        height: Int,
        darkThreshold: UInt8
    ) -> CGRect? {
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundDarkPixel = false

        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < darkThreshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                foundDarkPixel = true
            }
        }

        guard foundDarkPixel else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }

    private func darkRatioForCell(
        pixels: [UInt8],
        imageWidth: Int,
        bounds: CGRect,
        column: Int,
        row: Int,
        darkThreshold: UInt8
    ) -> Double {
        let minX = Int(bounds.minX + bounds.width * CGFloat(column) / CGFloat(columns))
        let maxX = max(minX + 1, Int(bounds.minX + bounds.width * CGFloat(column + 1) / CGFloat(columns)))
        let minY = Int(bounds.minY + bounds.height * CGFloat(row) / CGFloat(rows))
        let maxY = max(minY + 1, Int(bounds.minY + bounds.height * CGFloat(row + 1) / CGFloat(rows)))

        var dark = 0
        var total = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                total += 1
                if pixels[y * imageWidth + x] < darkThreshold {
                    dark += 1
                }
            }
        }

        guard total > 0 else { return 0 }
        return Double(dark) / Double(total)
    }

    private func adaptiveDarkThreshold(for pixels: [UInt8]) -> UInt8 {
        var histogram = Array(repeating: 0, count: 256)
        for pixel in pixels {
            histogram[Int(pixel)] += 1
        }

        let total = pixels.count
        var weightedSum = 0
        for value in 0..<histogram.count {
            weightedSum += value * histogram[value]
        }

        var backgroundWeight = 0
        var backgroundSum = 0
        var bestVariance = 0.0
        var threshold = 127

        for value in 0..<histogram.count {
            backgroundWeight += histogram[value]
            guard backgroundWeight > 0 else { continue }

            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else { break }

            backgroundSum += value * histogram[value]
            let backgroundMean = Double(backgroundSum) / Double(backgroundWeight)
            let foregroundMean = Double(weightedSum - backgroundSum) / Double(foregroundWeight)
            let variance = Double(backgroundWeight) * Double(foregroundWeight) * pow(backgroundMean - foregroundMean, 2)

            if variance > bestVariance {
                bestVariance = variance
                threshold = value
            }
        }

        return UInt8(max(80, min(180, threshold)))
    }
}

// MARK: - OCR.space (network OCR, not an LLM)

final class OCRSpaceService: OCRDetailedRecognizing {
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
        try await recognizeDetailed(from: image, source: "OCR.space", variantName: "direct").cleanedText
    }

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        guard let primaryData = compressImage(image, toMaxBytes: Int(1.0 * 1024 * 1024)) else {
            throw TransliterationService.ServiceError.invalidImageData
        }

        let text: String
        do {
            text = try await submitOCRRequest(imageData: primaryData.data, mimeType: primaryData.mimeType)
        } catch let error as URLError where error.code == .timedOut {
            guard let retryData = compressImage(image, toMaxBytes: Int(600 * 1024)) else {
                throw TransliterationService.ServiceError.ocrFailed("OCR timed out and retry preparation failed.")
            }
            text = try await submitOCRRequest(imageData: retryData.data, mimeType: retryData.mimeType)
        }

        return OCRRecognitionResult.fromRawText(
            text,
            source: source,
            variantName: variantName,
            confidence: 0.45
        )
    }

    private func submitOCRRequest(imageData: Data, mimeType: String) async throws -> String {
        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
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

    private func compressImage(_ image: UIImage, toMaxBytes maxBytes: Int) -> (data: Data, mimeType: String)? {
        var workingImage = normalizedImage(image)
        workingImage = downscaledImage(workingImage, maxDimension: 1600)

        if let pngData = workingImage.pngData(), pngData.count <= maxBytes {
            return (pngData, "image/png")
        }

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
        guard let data else { return nil }
        return (data, "image/jpeg")
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

final class VisionOCRService: OCRDetailedRecognizing {
    func recognizeText(from image: UIImage) async throws -> String {
        try await recognizeDetailed(from: image, source: "Apple Vision", variantName: "direct").cleanedText
    }

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
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
        request.minimumTextHeight = 0.01
        if let latestRevision = VNRecognizeTextRequest.supportedRevisions.max() {
            request.revision = latestRevision
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
        try handler.perform([request])

        let blocks = OCRService.sortedReadingOrder((request.results ?? []).compactMap { observation in
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
        })
        let acceptedBlocks = OCRService.rejectLowConfidence(blocks, minimumConfidence: 0.05)
        let rawText = acceptedBlocks
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed("Apple Vision returned no readable text.")
        }

        let confidence = acceptedBlocks.isEmpty ? 0.0 : acceptedBlocks.map(\.confidence).reduce(0, +) / Float(acceptedBlocks.count)
        return OCRRecognitionResult.fromRawText(
            rawText,
            source: source,
            variantName: variantName,
            confidence: confidence,
            boundingBox: combinedBoundingBox(from: acceptedBlocks),
            blocks: acceptedBlocks
        )
    }

    private func combinedBoundingBox(from blocks: [OCRTextBlock]) -> CGRect? {
        let boxes = blocks.compactMap(\.boundingBox)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
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
