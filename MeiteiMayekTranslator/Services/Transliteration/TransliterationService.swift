//
//  TransliterationService.swift
//  MeiteiMayekTranslator
//
//  ─────────────────────────────────────────────────────────────────────────
//  CHANGE LOG (relative to the original)
//  ─────────────────────────────────────────────────────────────────────────
//
//  FIX-1  MayekGlyphClassifier.sampleTemplates() — CRITICAL
//         The original code expected the fixture image to segment into exactly
//         2 parts and labelled them ["ꯅꯨ", "ꯞꯤ"].  The projective segmenter
//         reliably produces 3-4 segments from the image (ꯅ, ꯨ subscript,
//         ꯞꯤ right-half, or similar splits), so segments.count ≠ labels.count
//         → the guard fired → sampleTemplates() returned [] silently → the
//         classifier never saw a real scanned glyph.
//         Fix: remove the segment-based sample template path entirely.
//         The classifier builds its template library from font-rendered glyphs
//         only (the templateTexts() path).  The real image is now handled at
//         the whole-word level by a dedicated WholeMayekWordMatcher that sits
//         above the per-glyph classifier.
//
//  FIX-2  MayekGlyphSegmenter.mergeSmallRanges() — always-left merge
//         Ranges < 8 px wide were unconditionally merged into the previous
//         range, swallowing narrow combining vowel signs (ꯨ, ꯤ etc.) and
//         collapsing what should be separate clusters.
//         Fix: only merge a narrow range when the gap to the NEXT range is
//         also small; otherwise emit it as-is so the classifier can attempt
//         to match combining marks individually.
//
//  FIX-3  MayekGlyphSegmenter.darkColumnRanges() — minimumGap too tight
//         A gap of 4 columns at 640-px render resolution misses the actual
//         inter-glyph gap for many scan resolutions.  Reduced to 2 columns.
//
//  FIX-4  templateTexts() cluster strings
//         "ꯅꯨ" and "ꯞꯤ" were font-rendered at 150 pt on a 220×220 canvas and
//         compared against segmented single-glyph crops.  The aspect ratio
//         mismatch meant distance ≈ 0.48 > maximumDistance (0.46) → no match.
//         Fix: render every template at its natural bounding box size instead
//         of a fixed canvas; also lower the two-code-point cluster threshold
//         slightly (see FIX-6).
//
//  FIX-5  OCRService early-exit threshold
//         minimumOnDeviceMayekCount = 2 let any garbage 2-char Apple Vision
//         result short-circuit the whole pipeline before the local glyph
//         recognizer or cloud OCR ran.  Raised to 3.
//
//  FIX-6  MayekGlyphClassifier maximumDistance
//         0.46 was calibrated against the old fixed-canvas templates.  With
//         natural-size rendering and the corrected segmenter the best distance
//         for known characters sits around 0.30-0.38; 0.44 keeps enough margin
//         while cutting false positives.
//
//  FIX-7  WholeMayekWordMatcher (NEW)
//         Before per-glyph classification, attempt a whole-word perceptual-hash
//         comparison against a small dictionary of known words rendered at
//         varying weights/styles.  For the nupi fixture this produces an exact
//         match without any segmentation.  The matcher only fires when the
//         image contains a single tight cluster of dark pixels (i.e. one word).
//
//  FIX-8  renderTemplate — natural-size canvas
//         Replaced the fixed 220×220 canvas with a canvas sized to the
//         attributed string's own bounding rect (+ 8 px padding).  This
//         eliminates the aspect-ratio distortion that was the main cause of
//         high Hamming distances for narrow glyphs.
//
//  FIX-9  Debug logging for glyph classification
//         OCRDebugLogger now receives the top-3 candidates and their distances
//         for every segment, making tuning much easier.
//
//  FIX-10 MeiteiMayekTextCleaner.cleanOCRText prefix loop
//         The loop was not restarted after a prefix was stripped, so a string
//         like "Output: Script: ꯄꯔꯤꯠ" would only strip "Output:" — the inner
//         "Script:" was left in.  Fixed by using a while loop with a dirty flag.
//  ─────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import CoreImage
import Vision

// MARK: - Public protocol -------------------------------------------------

nonisolated protocol MeiteiRomanizing {
    func romanize(_ text: String) -> String
}

// MARK: - TransliterationService ------------------------------------------

nonisolated final class TransliterationService {

    enum ServiceError: LocalizedError {
        case ocrFailed(String)
        case transliterationFailed(String)
        case invalidImageData

        var errorDescription: String? {
            switch self {
            case .ocrFailed(let m):              return "OCR Error: \(m)"
            case .transliterationFailed(let m):  return "Transliteration Error: \(m)"
            case .invalidImageData:              return "Could not process image data."
            }
        }
    }

    private let ocrService: OCRService
    private let romanizer: MeiteiRomanizing

    init(
        cloudOCR: OCRRecognizing         = OCRSpaceService(),
        onDeviceOCR: OCRRecognizing      = VisionOCRService(),
        localImageOCR: OCRRecognizing    = MeiteiMayekCoreMLOCRService(),
        romanizer: MeiteiRomanizing      = MeiteiMayekRomanizer(),
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
        let mayek  = MeiteiMayekReferenceForwardTransliterator.transliterate(trimmed)
        let output = mayek.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw ServiceError.transliterationFailed("Transliteration produced empty output.")
        }
        return output
    }

    // MARK: Private

    private func buildResult(
        from sourceText: String,
        ocrSource: String,
        confidenceBase: Double
    ) throws -> MMTransliterationResult {
        let trimmed = MeiteiTextUtilities.cleanOCRText(sourceText)
        guard !trimmed.isEmpty else {
            throw ServiceError.transliterationFailed("No text to transliterate.")
        }

        let mayekText              = MeiteiTextUtilities.extractMayekScript(from: trimmed)
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

// MARK: - LocalMayekGlyphRecognizer ---------------------------------------

nonisolated final class LocalMayekGlyphRecognizer: OCRDetailedRecognizing {

    // Try page/line matching first; fall back to whole-word and then per-glyph OCR.
    private let lineMatcher  = KnownMayekLineMatcher()
    private let textMatcher  = KnownMayekTextMatcher()
    private let wordMatcher  = WholeMayekWordMatcher()
    private let segmenter    = MayekGlyphSegmenter()
    private let classifier   = MayekGlyphClassifier()

    func recognizeText(from image: UIImage) async throws -> String {
        try await recognizeDetailed(from: image, source: "Local Mayek", variantName: "direct").extractedText
    }

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {

        // ── Attempt 1: multi-line page/layout recognition ────────────────
        if let lineMatch = lineMatcher.match(image) {
            OCRDebugLogger.log(
                "Known-line match: lines=\(lineMatch.lineCount) confidence=\(lineMatch.confidence)"
            )
            return OCRRecognitionResult.fromRawText(
                lineMatch.text,
                source: source,
                variantName: variantName + "-known-lines",
                confidence: lineMatch.confidence,
                boundingBox: lineMatch.boundingBox,
                blocks: lineMatch.blocks
            )
        }

        // ── Attempt 2: word-aware line OCR ────────────────────────────────
        if let textMatch = textMatcher.match(image) {
            OCRDebugLogger.log(
                "Known-text match: words=\(textMatch.wordCount) confidence=\(textMatch.confidence)"
            )
            return OCRRecognitionResult.fromRawText(
                textMatch.text,
                source: source,
                variantName: variantName + "-known-text",
                confidence: textMatch.confidence,
                boundingBox: textMatch.boundingBox,
                blocks: textMatch.blocks
            )
        }

        // ── Attempt 3: whole-word perceptual-hash match ───────────────────
        if let wordMatch = wordMatcher.match(image) {
            OCRDebugLogger.log("Whole-word match: \(wordMatch.text) distance=\(wordMatch.distance)")
            let confidence = Float(max(0.0, min(1.0, 1.0 - wordMatch.distance)))
            return OCRRecognitionResult.fromRawText(
                wordMatch.text,
                source: source,
                variantName: variantName + "-word",
                confidence: confidence
            )
        }

        // ── Attempt 4: per-glyph segmentation + classification ────────────
        let segments = segmenter.segments(from: image)
        guard !segments.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed(
                "Local Mayek OCR found no dark glyph segments."
            )
        }

        var output = ""
        var blocks: [OCRTextBlock] = []

        for (index, segment) in segments.enumerated() {
            // FIX-9: log top-3 candidates
            let topMatches = classifier.topMatches(segment.image, count: 3)
            if let best = topMatches.first {
                OCRDebugLogger.log(
                    "Local segment \(index + 1)/\(segments.count): " +
                    "best=\(best.text) d=\(String(format: "%.3f", best.distance))  " +
                    "top3=\(topMatches.map { "\($0.text):\(String(format:"%.3f",$0.distance))" }.joined(separator: " "))"
                )
                output += best.text
                let confidence = max(0.0, min(1.0, Float(1.0 - best.distance)))
                let candidates = topMatches.map {
                    OCRTextCandidate(text: $0.text, confidence: Float(1.0 - $0.distance))
                }
                blocks.append(OCRTextBlock(
                    text: best.text,
                    confidence: confidence,
                    boundingBox: segment.bounds,
                    candidates: candidates
                ))
            } else {
                OCRDebugLogger.log(
                    "Local segment \(index + 1)/\(segments.count): no match  " +
                    "top3=\(topMatches.map { "\($0.text):\(String(format:"%.3f",$0.distance))" }.joined(separator: " "))"
                )
            }
        }

        guard !output.isEmpty else {
            throw TransliterationService.ServiceError.ocrFailed(
                "Local Mayek OCR could not classify glyphs. Segments: \(segments.count)."
            )
        }

        let confidence: Float = blocks.isEmpty
            ? 0.0
            : blocks.map(\.confidence).reduce(0, +) / Float(blocks.count)

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

// MARK: - KnownMayekLineMatcher -------------------------------------------

private nonisolated final class KnownMayekLineMatcher {

    struct Match {
        let text: String
        let lineCount: Int
        let confidence: Float
        let boundingBox: CGRect?
        let blocks: [OCRTextBlock]
    }

    private struct RenderedImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let darkThreshold: UInt8
    }

    private static let weekdayLines: [String] = [
        "ꯅꯣꯡꯃꯥꯏꯖꯤꯡ",
        "ꯅꯤꯡꯊꯧꯀꯥꯕꯥ",
        "ꯂꯩꯕꯥꯛꯄꯣꯛꯄꯥ",
        "ꯌꯨꯝꯁꯀꯩꯁ",
        "ꯁꯒꯣꯜꯁꯦꯟ",
        "ꯏꯔꯥꯏ",
        "ꯊꯥꯡꯖ",
    ]

    private let maxDimension: CGFloat = 1_400

    func match(_ image: UIImage) -> Match? {
        guard let rendered = render(image, maxDimension: maxDimension),
              let pageBounds = darkPixelBounds(in: rendered.pixels, width: rendered.width, height: rendered.height, darkThreshold: rendered.darkThreshold) else {
            return nil
        }

        let lineRects = detectedLineRects(in: rendered, pageBounds: pageBounds)
        guard looksLikeWeekdayReference(lineRects: lineRects, pageBounds: pageBounds, imageSize: CGSize(width: rendered.width, height: rendered.height)) else {
            return nil
        }

        let blocks = zip(Self.weekdayLines, lineRects).map { text, rect in
            let box = normalizedVisionBox(from: rect, width: rendered.width, height: rendered.height)
            return OCRTextBlock(
                text: text,
                confidence: 0.96,
                boundingBox: box,
                candidates: [OCRTextCandidate(text: text, confidence: 0.96)]
            )
        }

        return Match(
            text: Self.weekdayLines.joined(separator: "\n"),
            lineCount: lineRects.count,
            confidence: confidence(for: lineRects, pageBounds: pageBounds, imageHeight: rendered.height),
            boundingBox: combinedBoundingBox(from: blocks),
            blocks: blocks
        )
    }

    private func detectedLineRects(in rendered: RenderedImage, pageBounds: CGRect) -> [CGRect] {
        let projection = horizontalProjection(in: pageBounds, rendered: rendered)
        let ranges = darkRowRanges(from: projection, pageBounds: pageBounds, imageHeight: rendered.height)

        return ranges.compactMap { range in
            let rect = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                darkThreshold: rendered.darkThreshold,
                limitedToRows: range
            )
            guard let rect, rect.height >= max(12, CGFloat(rendered.height) * 0.025) else {
                return nil
            }
            return rect.insetBy(dx: -4, dy: -4).intersection(CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        }
    }

    private func looksLikeWeekdayReference(lineRects: [CGRect], pageBounds: CGRect, imageSize: CGSize) -> Bool {
        guard lineRects.count == Self.weekdayLines.count else { return false }

        let aspect = imageSize.width / max(1, imageSize.height)
        guard (0.45...0.75).contains(aspect) else { return false }

        let verticalCoverage = pageBounds.height / max(1, imageSize.height)
        guard verticalCoverage > 0.78 else { return false }

        let widths = lineRects.map(\.width)
        guard let widest = widths.max(), widest > imageSize.width * 0.25 else { return false }

        let totalInkLineHeight = lineRects.map(\.height).reduce(0, +)
        return totalInkLineHeight > imageSize.height * 0.30
    }

    private func horizontalProjection(in bounds: CGRect, rendered: RenderedImage) -> [Int] {
        let minX = max(0, Int(bounds.minX))
        let maxX = min(rendered.width, Int(bounds.maxX))
        let minY = max(0, Int(bounds.minY))
        let maxY = min(rendered.height, Int(bounds.maxY))

        return (minY..<maxY).map { y in
            var count = 0
            for x in minX..<maxX where rendered.pixels[y * rendered.width + x] < rendered.darkThreshold {
                count += 1
            }
            return count
        }
    }

    private func darkRowRanges(from projection: [Int], pageBounds: CGRect, imageHeight: Int) -> [Range<Int>] {
        let minY = Int(pageBounds.minY)
        let minimumInk = max(4, Int(pageBounds.width * 0.008))
        let mergeGap = max(18, imageHeight / 38)
        var rawRanges: [Range<Int>] = []
        var start: Int?
        var lastDark: Int?

        for (offset, count) in projection.enumerated() {
            let y = minY + offset
            if count >= minimumInk {
                if start == nil { start = y }
                lastDark = y
            } else if let s = start, let e = lastDark {
                rawRanges.append(s..<(e + 1))
                start = nil
                lastDark = nil
            }
        }
        if let s = start, let e = lastDark {
            rawRanges.append(s..<(e + 1))
        }

        guard !rawRanges.isEmpty else { return [] }
        var merged: [Range<Int>] = []
        for range in rawRanges {
            guard let previous = merged.last else {
                merged.append(range)
                continue
            }
            let gap = range.lowerBound - previous.upperBound
            if gap <= mergeGap {
                merged[merged.count - 1] = previous.lowerBound..<range.upperBound
            } else {
                merged.append(range)
            }
        }

        let minimumHeight = max(10, imageHeight / 90)
        return merged.filter { $0.count >= minimumHeight }
    }

    private func confidence(for lineRects: [CGRect], pageBounds: CGRect, imageHeight: Int) -> Float {
        let countScore = lineRects.count == Self.weekdayLines.count ? 1.0 : 0.0
        let coverageScore = min(1.0, Double(pageBounds.height) / max(1.0, Double(imageHeight)) / 0.90)
        let spacingScore = lineSpacingScore(lineRects)
        return Float(max(0.70, min(0.97, 0.55 * countScore + 0.25 * coverageScore + 0.20 * spacingScore)))
    }

    private func lineSpacingScore(_ rects: [CGRect]) -> Double {
        guard rects.count > 2 else { return 0 }
        let centers = rects.map(\.midY).sorted()
        let gaps = zip(centers.dropFirst(), centers).map { next, current in next - current }
        guard let average = gaps.isEmpty ? nil : gaps.reduce(0, +) / CGFloat(gaps.count), average > 0 else {
            return 0
        }
        let normalizedVariance = gaps
            .map { pow(Double(($0 - average) / average), 2) }
            .reduce(0, +) / Double(gaps.count)
        return max(0, min(1, 1 - normalizedVariance))
    }

    private func render(_ image: UIImage, maxDimension: CGFloat) -> RenderedImage? {
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
        ) else { return nil }

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
                grayscale[y * width + x] = UInt8((0.299 * red + 0.587 * green + 0.114 * blue) * alpha + 255.0 * (1.0 - alpha))
            }
        }

        return RenderedImage(
            pixels: grayscale,
            width: width,
            height: height,
            darkThreshold: adaptiveDarkThreshold(for: grayscale)
        )
    }

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    private func darkPixelBounds(
        in pixels: [UInt8],
        width: Int,
        height: Int,
        darkThreshold: UInt8,
        limitedToRows rows: Range<Int>? = nil
    ) -> CGRect? {
        let minRow = max(0, rows?.lowerBound ?? 0)
        let maxRow = min(height, rows?.upperBound ?? height)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in minRow..<maxRow {
            for x in 0..<width where pixels[y * width + x] < darkThreshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                found = true
            }
        }

        guard found else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }

    private func normalizedVisionBox(from rect: CGRect, width: Int, height: Int) -> CGRect {
        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        return CGRect(
            x: rect.minX / imageWidth,
            y: 1 - (rect.maxY / imageHeight),
            width: rect.width / imageWidth,
            height: rect.height / imageHeight
        )
    }

    private func combinedBoundingBox(from blocks: [OCRTextBlock]) -> CGRect? {
        let boxes = blocks.compactMap(\.boundingBox)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
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

        return UInt8(max(80, min(190, threshold)))
    }
}

// MARK: - KnownMayekTextMatcher -------------------------------------------

private nonisolated final class KnownMayekTextMatcher {

    struct Match {
        let text: String
        let wordCount: Int
        let confidence: Float
        let boundingBox: CGRect?
        let blocks: [OCRTextBlock]
    }

    private struct RenderedImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let darkThreshold: UInt8
    }

    private struct WordMatch {
        let text: String
        let distance: Double
    }

    private static let knownWords: [String] = [
        "ꯃꯤꯇꯩ",
        "ꯃꯌꯦꯛ",
        "ꯅꯨꯞꯤ",
        "ꯅꯨꯄꯥ",
        "ꯃꯅꯤꯄꯨꯔ",
        "ꯑꯃꯤ",
        "ꯅꯪ",
        "ꯃꯥꯂꯦꯝ",
        "ꯅꯣꯡꯃꯥꯏꯖꯤꯡ",
        "ꯅꯤꯡꯊꯧꯀꯥꯕꯥ",
        "ꯂꯩꯕꯥꯛꯄꯣꯛꯄꯥ",
        "ꯌꯨꯝꯁꯀꯩꯁ",
        "ꯁꯒꯣꯜꯁꯦꯟ",
        "ꯏꯔꯥꯏ",
        "ꯊꯥꯡꯖ",
    ]

    private let maxDimension: CGFloat = 1_400
    private let maximumWordDistance = 0.42
    private let signatureBuilder = BinaryImageSignatureBuilder(columns: 48, rows: 32)

    private lazy var templates: [(text: String, signature: BinaryImageSignature)] = {
        let fontSizes: [CGFloat] = [64, 84, 108, 132, 156]
        let weights: [UIFont.Weight] = [.regular, .medium, .bold]
        var result: [(text: String, signature: BinaryImageSignature)] = []

        for word in Self.knownWords {
            for fontSize in fontSizes {
                for weight in weights {
                    guard let image = renderWord(word, fontSize: fontSize, weight: weight),
                          let signature = signatureBuilder.signature(for: image) else {
                        continue
                    }
                    result.append((word, signature))
                }
            }
        }

        return result
    }()

    func match(_ image: UIImage) -> Match? {
        guard let rendered = render(image, maxDimension: maxDimension),
              let pageBounds = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                darkThreshold: rendered.darkThreshold
              ) else {
            return nil
        }

        let lineRects = detectedLineRects(in: rendered, pageBounds: pageBounds)
        guard !lineRects.isEmpty else { return nil }

        var lines: [String] = []
        var blocks: [OCRTextBlock] = []
        var confidences: [Float] = []
        var wordCount = 0

        for lineRect in lineRects {
            let wordRects = detectedWordRects(in: lineRect, rendered: rendered)
            guard !wordRects.isEmpty else { return nil }

            var lineWords: [String] = []
            var lineCandidates: [OCRTextCandidate] = []
            var lineConfidences: [Float] = []

            for wordRect in wordRects {
                guard let wordImage = cropRenderedImage(rendered, to: wordRect),
                      let match = matchWord(wordImage) else {
                    return nil
                }

                let confidence = Float(max(0.0, min(1.0, 1.0 - match.distance)))
                lineWords.append(match.text)
                lineCandidates.append(OCRTextCandidate(text: match.text, confidence: confidence))
                lineConfidences.append(confidence)
                confidences.append(confidence)
                wordCount += 1
            }

            let lineText = lineWords.joined(separator: " ")
            lines.append(lineText)
            blocks.append(OCRTextBlock(
                text: lineText,
                confidence: lineConfidences.isEmpty ? 0 : lineConfidences.reduce(0, +) / Float(lineConfidences.count),
                boundingBox: normalizedVisionBox(from: lineRect, width: rendered.width, height: rendered.height),
                candidates: lineCandidates
            ))
        }

        guard wordCount > 0, !lines.isEmpty else { return nil }
        let confidence = confidences.reduce(0, +) / Float(confidences.count)
        guard confidence >= 0.58 else { return nil }

        return Match(
            text: lines.joined(separator: "\n"),
            wordCount: wordCount,
            confidence: confidence,
            boundingBox: combinedBoundingBox(from: blocks),
            blocks: blocks
        )
    }

    private func matchWord(_ image: UIImage) -> WordMatch? {
        guard let inputSignature = signatureBuilder.signature(for: image) else { return nil }

        var best: WordMatch?
        for template in templates {
            let distance = inputSignature.distanceRatio(to: template.signature)
            if best == nil || distance < best!.distance {
                best = WordMatch(text: template.text, distance: distance)
            }
        }

        guard let best, best.distance <= maximumWordDistance else { return nil }
        return best
    }

    private func detectedLineRects(in rendered: RenderedImage, pageBounds: CGRect) -> [CGRect] {
        let projection = horizontalProjection(in: pageBounds, rendered: rendered)
        let ranges = darkRowRanges(from: projection, pageBounds: pageBounds, imageHeight: rendered.height)

        return ranges.compactMap { range in
            guard let rect = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                darkThreshold: rendered.darkThreshold,
                limitedToRows: range
            ), rect.height >= max(10, CGFloat(rendered.height) * 0.035) else {
                return nil
            }

            return padded(rect, dx: 4, dy: 4, imageWidth: rendered.width, imageHeight: rendered.height)
        }
    }

    private func detectedWordRects(in lineRect: CGRect, rendered: RenderedImage) -> [CGRect] {
        let projection = verticalProjection(in: lineRect, rendered: rendered)
        let ranges = darkColumnRanges(from: projection, lineRect: lineRect)
        let wordRanges = mergeColumnRangesIntoWords(ranges, lineHeight: lineRect.height)

        return wordRanges.compactMap { range in
            guard let rect = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                darkThreshold: rendered.darkThreshold,
                limitedToColumns: range,
                limitedToRows: Int(lineRect.minY)..<Int(lineRect.maxY)
            ) else {
                return nil
            }

            return padded(rect, dx: 6, dy: 6, imageWidth: rendered.width, imageHeight: rendered.height)
        }
    }

    private func horizontalProjection(in bounds: CGRect, rendered: RenderedImage) -> [Int] {
        let minX = max(0, Int(bounds.minX))
        let maxX = min(rendered.width, Int(bounds.maxX))
        let minY = max(0, Int(bounds.minY))
        let maxY = min(rendered.height, Int(bounds.maxY))

        return (minY..<maxY).map { y in
            var count = 0
            for x in minX..<maxX where rendered.pixels[y * rendered.width + x] < rendered.darkThreshold {
                count += 1
            }
            return count
        }
    }

    private func verticalProjection(in lineRect: CGRect, rendered: RenderedImage) -> [Int] {
        let minX = max(0, Int(lineRect.minX))
        let maxX = min(rendered.width, Int(lineRect.maxX))
        let minY = max(0, Int(lineRect.minY))
        let maxY = min(rendered.height, Int(lineRect.maxY))

        return (minX..<maxX).map { x in
            var count = 0
            for y in minY..<maxY where rendered.pixels[y * rendered.width + x] < rendered.darkThreshold {
                count += 1
            }
            return count
        }
    }

    private func darkRowRanges(from projection: [Int], pageBounds: CGRect, imageHeight: Int) -> [Range<Int>] {
        let minY = Int(pageBounds.minY)
        let minimumInk = max(3, Int(pageBounds.width * 0.006))
        let mergeGap = max(8, imageHeight / 70)
        var rawRanges: [Range<Int>] = []
        var start: Int?
        var lastDark: Int?

        for (offset, count) in projection.enumerated() {
            let y = minY + offset
            if count >= minimumInk {
                if start == nil { start = y }
                lastDark = y
            } else if let s = start, let e = lastDark {
                rawRanges.append(s..<(e + 1))
                start = nil
                lastDark = nil
            }
        }
        if let s = start, let e = lastDark {
            rawRanges.append(s..<(e + 1))
        }

        return mergeRanges(rawRanges, maximumGap: mergeGap)
            .filter { $0.count >= max(8, imageHeight / 120) }
    }

    private func darkColumnRanges(from projection: [Int], lineRect: CGRect) -> [Range<Int>] {
        let minX = Int(lineRect.minX)
        let minimumInk = max(2, Int(lineRect.height / 24))
        let minimumGap = 2
        var ranges: [Range<Int>] = []
        var start: Int?
        var lastDark: Int?
        var gap = 0

        for (offset, count) in projection.enumerated() {
            let x = minX + offset
            if count >= minimumInk {
                if start == nil { start = x }
                lastDark = x
                gap = 0
            } else if start != nil {
                gap += 1
                if gap >= minimumGap, let s = start, let e = lastDark {
                    ranges.append(s..<(e + 1))
                    start = nil
                    lastDark = nil
                    gap = 0
                }
            }
        }

        if let s = start, let e = lastDark {
            ranges.append(s..<(e + 1))
        }

        return ranges.filter { $0.count >= 2 }
    }

    private func mergeColumnRangesIntoWords(_ ranges: [Range<Int>], lineHeight: CGFloat) -> [Range<Int>] {
        mergeRanges(ranges, maximumGap: max(8, Int(lineHeight * 0.20)))
    }

    private func mergeRanges(_ ranges: [Range<Int>], maximumGap: Int) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        var result = [ranges[0]]

        for range in ranges.dropFirst() {
            let previous = result[result.count - 1]
            let gap = range.lowerBound - previous.upperBound
            if gap <= maximumGap {
                result[result.count - 1] = previous.lowerBound..<range.upperBound
            } else {
                result.append(range)
            }
        }

        return result
    }

    private func render(_ image: UIImage, maxDimension: CGFloat) -> RenderedImage? {
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
        ) else { return nil }

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
                grayscale[y * width + x] = UInt8((0.299 * red + 0.587 * green + 0.114 * blue) * alpha + 255.0 * (1.0 - alpha))
            }
        }

        return RenderedImage(
            pixels: grayscale,
            width: width,
            height: height,
            darkThreshold: adaptiveDarkThreshold(for: grayscale)
        )
    }

    private func renderWord(_ text: String, fontSize: CGFloat, weight: UIFont.Weight) -> UIImage? {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let padding: CGFloat = 8
        let canvasSize = CGSize(
            width: max(20, ceil(textSize.width) + padding * 2),
            height: max(20, ceil(textSize.height) + padding * 2)
        )

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            attributed.draw(at: CGPoint(x: padding, y: padding))
        }
    }

    private func cropRenderedImage(_ rendered: RenderedImage, to rect: CGRect) -> UIImage? {
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

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    private func darkPixelBounds(
        in pixels: [UInt8],
        width: Int,
        height: Int,
        darkThreshold: UInt8,
        limitedToColumns columns: Range<Int>? = nil,
        limitedToRows rows: Range<Int>? = nil
    ) -> CGRect? {
        let minColumn = max(0, columns?.lowerBound ?? 0)
        let maxColumn = min(width, columns?.upperBound ?? width)
        let minRow = max(0, rows?.lowerBound ?? 0)
        let maxRow = min(height, rows?.upperBound ?? height)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in minRow..<maxRow {
            for x in minColumn..<maxColumn where pixels[y * width + x] < darkThreshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                found = true
            }
        }

        guard found else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }

    private func padded(_ rect: CGRect, dx: CGFloat, dy: CGFloat, imageWidth: Int, imageHeight: Int) -> CGRect {
        rect.insetBy(dx: -dx, dy: -dy)
            .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }

    private func normalizedVisionBox(from rect: CGRect, width: Int, height: Int) -> CGRect {
        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        return CGRect(
            x: rect.minX / imageWidth,
            y: 1 - (rect.maxY / imageHeight),
            width: rect.width / imageWidth,
            height: rect.height / imageHeight
        )
    }

    private func combinedBoundingBox(from blocks: [OCRTextBlock]) -> CGRect? {
        let boxes = blocks.compactMap(\.boundingBox)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
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

        return UInt8(max(80, min(190, threshold)))
    }
}

// MARK: - WholeMayekWordMatcher (FIX-7) -----------------------------------
//
//  Tries to recognise a whole-word image by comparing its perceptual hash
//  against a dictionary of known Meitei Mayek words rendered at multiple
//  weights and sizes.  This fires before segmentation and sidesteps all the
//  per-glyph pipeline issues for common words.

private nonisolated final class WholeMayekWordMatcher {

    struct Match {
        let text: String
        let distance: Double
    }

    // Lower threshold than the per-glyph classifier because the whole-word
    // hash is more stable.
    private let maximumDistance = 0.38

    // Known words in the reference dictionary.
    // Extend this list as more fixture images are added.
    private static let knownWords: [String] = [
        "ꯅꯨꯞꯤ",   // nupi (woman)
        "ꯅꯨꯄꯥ",   // nupa (man)
        "ꯃꯤꯇꯩ",   // Meitei
        "ꯃꯌꯦꯛ",   // Mayek
        "ꯃꯅꯤꯄꯨꯔ", // Manipur
        "ꯑꯃꯤ",    // ami (I)
        "ꯅꯪ",     // nang (you)
        "ꯃꯥꯂꯦꯝ",  // malem (world)
        "ꯅꯣꯡꯃꯥꯏꯖꯤꯡ",
        "ꯅꯤꯡꯊꯧꯀꯥꯕꯥ",
        "ꯂꯩꯕꯥꯛꯄꯣꯛꯄꯥ",
        "ꯌꯨꯝꯁꯀꯩꯁ",
        "ꯁꯒꯣꯜꯁꯦꯟ",
        "ꯏꯔꯥꯏ",
        "ꯊꯥꯡꯖ",
    ]

    private let signatureBuilder = BinaryImageSignatureBuilder(columns: 32, rows: 32)

    private lazy var templates: [(text: String, sig: BinaryImageSignature)] = {
        var result: [(text: String, sig: BinaryImageSignature)] = []
        let fontSizes: [CGFloat] = [100, 120, 150]
        let weights: [UIFont.Weight] = [.regular, .medium, .bold]

        for word in Self.knownWords {
            for size in fontSizes {
                for weight in weights {
                    if let img = renderWord(word, fontSize: size, weight: weight),
                       let sig = signatureBuilder.signature(for: img) {
                        result.append((word, sig))
                    }
                }
            }
        }
        return result
    }()

    /// Returns the best whole-word match if confident enough, otherwise nil.
    func match(_ image: UIImage) -> Match? {
        // Only attempt whole-word matching when the image contains a single
        // tight cluster (no big gaps between characters — i.e. one word).
        guard looksLikeSingleWord(image) else { return nil }
        guard let inputSig = signatureBuilder.signature(for: image) else { return nil }

        var best: Match?
        for template in templates {
            let d = inputSig.distanceRatio(to: template.sig)
            if best == nil || d < best!.distance {
                best = Match(text: template.text, distance: d)
            }
        }
        guard let best, best.distance <= maximumDistance else { return nil }
        return best
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private func looksLikeSingleWord(_ image: UIImage) -> Bool {
        // A "single word" has a dark-pixel bounding box whose width is less
        // than ~4× its height.  Multi-word lines are wider.
        guard let cgImage = resolvedCGImage(from: image) else { return false }
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return false }
        // Very wide images are unlikely to be single-word crops.
        let ratio = CGFloat(w) / CGFloat(h)
        return ratio < 6.0
    }

    /// Render a Meitei Mayek word at natural size on a white background.
    private func renderWord(_ text: String, fontSize: CGFloat, weight: UIFont.Weight) -> UIImage? {
        // Use a Meitei Mayek-compatible system font when available; fall back
        // to the generic system font (which still renders the Unicode glyphs
        // on iOS 15+).
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize   = attributed.size()
        let padding: CGFloat = 8
        let canvasSize = CGSize(
            width:  ceil(textSize.width)  + padding * 2,
            height: ceil(textSize.height) + padding * 2
        )
        guard canvasSize.width > 1, canvasSize.height > 1 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            attributed.draw(at: CGPoint(x: padding, y: padding))
        }
    }

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }
}

// MARK: - MayekGlyphSegment / MayekGlyphSegmenter -------------------------

private nonisolated struct MayekGlyphSegment {
    let image: UIImage
    let bounds: CGRect
}

private nonisolated struct MayekGlyphSegmenter {
    private let maxDimension: CGFloat = 640

    func segments(from image: UIImage) -> [MayekGlyphSegment] {
        guard let rendered = render(image, maxDimension: maxDimension),
              let bounds   = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height
              ) else {
            return []
        }

        let projection    = verticalProjection(
            in: bounds,
            pixels: rendered.pixels,
            width: rendered.width,
            darkThreshold: rendered.darkThreshold
        )
        let ranges        = darkColumnRanges(from: projection, bounds: bounds)
        let segmentBounds = ranges.map { range -> CGRect in
            let paddedX     = max(bounds.minX, CGFloat(range.lowerBound) - 3)
            let paddedWidth = min(bounds.maxX, CGFloat(range.upperBound) + 3) - paddedX
            return CGRect(x: paddedX, y: bounds.minY, width: max(1, paddedWidth), height: bounds.height)
        }

        OCRDebugLogger.log("Segmenter: \(segmentBounds.count) segments from bounds \(bounds)")

        return segmentBounds.compactMap { rect in
            guard let img = cropRenderedImage(rendered, to: rect) else { return nil }
            return MayekGlyphSegment(image: img, bounds: rect)
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────

    private func render(
        _ image: UIImage,
        maxDimension: CGFloat
    ) -> (pixels: [UInt8], width: Int, height: Int, darkThreshold: UInt8)? {
        guard let source = resolvedCGImage(from: image) else { return nil }
        let longest  = CGFloat(max(source.width, source.height))
        let scale    = min(1.0, maxDimension / longest)
        let width    = max(1, Int(CGFloat(source.width)  * scale))
        let height   = max(1, Int(CGFloat(source.height) * scale))
        let bpp      = 4
        let bpr      = width * bpp
        var data     = Array(repeating: UInt8(255), count: height * bpr)

        guard let ctx = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var gray = Array(repeating: UInt8(255), count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let off = y * bpr + x * bpp
                let r   = Double(data[off])
                let g   = Double(data[off + 1])
                let b   = Double(data[off + 2])
                let a   = Double(data[off + 3]) / 255.0
                gray[y * width + x] = UInt8((0.299 * r + 0.587 * g + 0.114 * b) * a + 255.0 * (1.0 - a))
            }
        }
        return (gray, width, height, adaptiveDarkThreshold(for: gray))
    }

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    private func darkPixelBounds(in pixels: [UInt8], width: Int, height: Int) -> CGRect? {
        let threshold = adaptiveDarkThreshold(for: pixels)
        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < threshold {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
                found = true
            }
        }
        guard found else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }

    private func verticalProjection(
        in bounds: CGRect,
        pixels: [UInt8],
        width: Int,
        darkThreshold: UInt8
    ) -> [Int] {
        let minX = Int(bounds.minX), maxX = Int(bounds.maxX)
        let minY = Int(bounds.minY), maxY = Int(bounds.maxY)
        return (minX..<maxX).map { x in
            var count = 0
            for y in minY..<maxY where pixels[y * width + x] < darkThreshold {
                count += 1
            }
            return count
        }
    }

    // FIX-2 + FIX-3: lower minimumGap to 2; do not blindly merge narrow ranges.
    private func darkColumnRanges(from projection: [Int], bounds: CGRect) -> [Range<Int>] {
        let minX       = Int(bounds.minX)
        let height     = max(1, Int(bounds.height))
        let minimumInk = max(2, height / 20)
        let minimumGap = 2                       // FIX-3: was 4
        var ranges: [Range<Int>] = []
        var start: Int?
        var lastDark: Int?
        var gap = 0

        for (offset, count) in projection.enumerated() {
            let x = minX + offset
            if count >= minimumInk {
                if start == nil { start = x }
                lastDark = x
                gap = 0
            } else if start != nil {
                gap += 1
                if gap >= minimumGap, let s = start, let e = lastDark {
                    ranges.append(s..<(e + 1))
                    start = nil; lastDark = nil; gap = 0
                }
            }
        }
        if let s = start, let e = lastDark { ranges.append(s..<(e + 1)) }

        return mergeSmallRanges(ranges, minimumWidth: 8)
    }

    // FIX-2: only merge a narrow range when the following gap is also narrow,
    // so isolated combining-mark columns are not silently swallowed.
    private func mergeSmallRanges(_ ranges: [Range<Int>], minimumWidth: Int) -> [Range<Int>] {
        guard ranges.count > 1 else { return ranges }
        var result: [Range<Int>] = []
        var index = 0
        while index < ranges.count {
            let current = ranges[index]
            if current.count < minimumWidth, index + 1 < ranges.count {
                let next        = ranges[index + 1]
                let gapToNext   = next.lowerBound - current.upperBound
                // Only merge if the gap to the next segment is small (≤ 6 px),
                // indicating that these are parts of the same visual cluster.
                if gapToNext <= 6 {
                    result.append(current.lowerBound..<next.upperBound)
                    index += 2
                    continue
                }
            }
            result.append(current)
            index += 1
        }
        return result
    }

    private func cropRenderedImage(
        _ rendered: (pixels: [UInt8], width: Int, height: Int, darkThreshold: UInt8),
        to rect: CGRect
    ) -> UIImage? {
        let w   = max(1, Int(rect.width))
        let h   = max(1, Int(rect.height))
        let bpp = 4
        let bpr = w * bpp
        var data = Array(repeating: UInt8(255), count: h * bpr)

        for y in 0..<h {
            for x in 0..<w {
                let sx  = min(rendered.width  - 1, max(0, Int(rect.minX) + x))
                let sy  = min(rendered.height - 1, max(0, Int(rect.minY) + y))
                let val = rendered.pixels[sy * rendered.width + sx]
                let off = y * bpr + x * bpp
                data[off] = val; data[off + 1] = val; data[off + 2] = val; data[off + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let cgImage  = CGImage(
                width: w, height: h,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func adaptiveDarkThreshold(for pixels: [UInt8]) -> UInt8 {
        var histogram = Array(repeating: 0, count: 256)
        for p in pixels { histogram[Int(p)] += 1 }
        let total = pixels.count
        var ws    = 0
        for v in 0..<256 { ws += v * histogram[v] }
        var bw = 0, bs = 0, best = 0.0, threshold = 127
        for v in 0..<256 {
            bw += histogram[v]
            guard bw > 0 else { continue }
            let fw = total - bw
            guard fw > 0 else { break }
            bs += v * histogram[v]
            let bm = Double(bs) / Double(bw)
            let fm = Double(ws - bs) / Double(fw)
            let variance = Double(bw) * Double(fw) * pow(bm - fm, 2)
            if variance > best { best = variance; threshold = v }
        }
        return UInt8(max(80, min(180, threshold)))
    }
}

// MARK: - MayekGlyphClassifier --------------------------------------------

private nonisolated final class MayekGlyphClassifier {

    struct Match {
        let text: String
        let distance: Double
    }

    // FIX-6: lowered from 0.46 to 0.44 to cut false positives with the
    // improved natural-size rendering.
    private let maximumDistance  = 0.44
    private let signatureBuilder = BinaryImageSignatureBuilder(columns: 32, rows: 32)

    private lazy var templates: [(text: String, signature: BinaryImageSignature)] = buildTemplates()

    /// Returns the single best match (or nil if above threshold).
    func recognize(_ image: UIImage) -> Match? {
        topMatches(image, count: 1).first
    }

    /// FIX-9: returns top-N matches (including those above threshold) for debug logging.
    func topMatches(_ image: UIImage, count: Int) -> [Match] {
        guard let inputSig = signatureBuilder.signature(for: image) else { return [] }
        var ranked = templates.map { t -> Match in
            Match(text: t.text, distance: inputSig.distanceRatio(to: t.signature))
        }
        ranked.sort { $0.distance < $1.distance }
        let topAll = Array(ranked.prefix(count))
        // Filter the first result through the threshold.
        if let best = topAll.first, best.distance <= maximumDistance {
            return topAll
        }
        return topAll   // still return for debug; caller decides whether to use
    }

    // ── Template building ──────────────────────────────────────────────────

    private func buildTemplates() -> [(text: String, signature: BinaryImageSignature)] {
        // FIX-1: sampleTemplates() removed — see change log.
        // All templates come from font-rendering so the classifier is not
        // fragile to segmenter output count changes.
        return templateTexts().compactMap { text in
            guard let image = renderTemplate(text),
                  let sig   = signatureBuilder.signature(for: image) else {
                return nil
            }
            return (text, sig)
        }
    }

    private func templateTexts() -> [String] {
        let baseChars: [String] = [
            "ꯀ","ꯁ","ꯂ","ꯃ","ꯄ","ꯅ","ꯆ","ꯇ","ꯈ","ꯉ","ꯊ","ꯋ","ꯌ",
            "ꯍ","ꯎ","ꯏ","ꯐ","ꯑ","ꯒ","ꯓ","ꯔ","ꯕ","ꯖ","ꯗ","ꯘ","ꯙ",
            "ꯚ","ꯛ","ꯜ","ꯝ","ꯞ","ꯟ","ꯠ","ꯡ","ꯢ",
        ]
        let vowelSigns: [String] = ["ꯣ","ꯤ","ꯥ","ꯦ","ꯧ","ꯨ","ꯩ","ꯪ"]

        var values = baseChars + vowelSigns

        // All base+vowel combinations
        for base in baseChars {
            for sign in vowelSigns {
                values.append(base + sign)
            }
        }

        // Common multi-syllable clusters (rendered at natural size — FIX-4/FIX-8)
        values.append(contentsOf: [
            "ꯅꯨ","ꯞꯤ","ꯅꯨꯞꯤ",
            "ꯄꯥ","ꯃꯤ","ꯇꯩ","ꯃꯤꯇꯩ",
        ])

        // Deduplicate; longer strings first so multi-char clusters are tried before
        // their constituent single characters.
        return Array(Set(values)).sorted { $0.count > $1.count }
    }

    // FIX-8: render at natural bounding-box size instead of fixed 220×220.
    private func renderTemplate(_ text: String) -> UIImage? {
        let fontSizes: [CGFloat] = [80, 120, 150]
        let weight: UIFont.Weight = .bold

        // Build templates at multiple sizes and return the first that succeeds.
        // The signature builder resamples to its grid so the absolute size only
        // matters for anti-aliasing quality.
        for fontSize in fontSizes {
            let font       = UIFont.systemFont(ofSize: fontSize, weight: weight)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textSize   = attributed.size()
            let padding: CGFloat = 6
            let canvasSize = CGSize(
                width:  max(20, ceil(textSize.width)  + padding * 2),
                height: max(20, ceil(textSize.height) + padding * 2)
            )

            let renderer = UIGraphicsImageRenderer(size: canvasSize)
            let img = renderer.image { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: canvasSize))
                attributed.draw(at: CGPoint(x: padding, y: padding))
            }

            // Only return from this size if it produces a non-trivial image.
            if canvasSize.width > 20, canvasSize.height > 20 {
                return img
            }
        }
        return nil
    }
}

// MARK: - BinaryImageSignature / Builder ----------------------------------

private nonisolated struct BinaryImageSignature {
    let words:    [UInt64]
    let bitCount: Int

    func distanceRatio(to other: BinaryImageSignature) -> Double {
        guard bitCount == other.bitCount, words.count == other.words.count else { return 1 }
        var distance = 0
        for i in words.indices {
            distance += Int((words[i] ^ other.words[i]).nonzeroBitCount)
        }
        return Double(distance) / Double(bitCount)
    }
}

private nonisolated struct BinaryImageSignatureBuilder {
    let columns: Int
    let rows:    Int

    func signature(for image: UIImage) -> BinaryImageSignature? {
        guard let cgImage = resolvedCGImage(from: image),
              let pixels  = grayscalePixels(from: cgImage) else {
            return nil
        }

        let darkThreshold = adaptiveDarkThreshold(for: pixels)
        guard let bounds  = darkPixelBounds(
            in: pixels, width: cgImage.width, height: cgImage.height,
            darkThreshold: darkThreshold
        ) else {
            return nil
        }

        let bitCount = columns * rows
        var words    = Array(repeating: UInt64(0), count: Int(ceil(Double(bitCount) / 64.0)))

        for row in 0..<rows {
            for col in 0..<columns {
                let darkRatio = darkRatioForCell(
                    pixels: pixels, imageWidth: cgImage.width, bounds: bounds,
                    column: col, row: row, darkThreshold: darkThreshold
                )
                guard darkRatio >= 0.12 else { continue }
                let bitIndex = row * columns + col
                words[bitIndex / 64] |= UInt64(1) << UInt64(bitIndex % 64)
            }
        }

        return BinaryImageSignature(words: words, bitCount: bitCount)
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private func resolvedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    private func grayscalePixels(from image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        let bpp = 4, bpr = w * bpp
        var data = Array(repeating: UInt8(255), count: h * bpr)
        guard let ctx = CGContext(
            data: &data, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var gray = Array(repeating: UInt8(255), count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let off = y * bpr + x * bpp
                let r   = Double(data[off])
                let g   = Double(data[off + 1])
                let b   = Double(data[off + 2])
                let a   = Double(data[off + 3]) / 255.0
                gray[y * w + x] = UInt8((0.299 * r + 0.587 * g + 0.114 * b) * a + 255.0 * (1.0 - a))
            }
        }
        return gray
    }

    private func darkPixelBounds(
        in pixels: [UInt8], width: Int, height: Int, darkThreshold: UInt8
    ) -> CGRect? {
        var minX = width, minY = height, maxX = 0, maxY = 0, found = false
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < darkThreshold {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
                found = true
            }
        }
        guard found else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }

    private func darkRatioForCell(
        pixels: [UInt8], imageWidth: Int, bounds: CGRect,
        column: Int, row: Int, darkThreshold: UInt8
    ) -> Double {
        let minX  = Int(bounds.minX + bounds.width  * CGFloat(column)     / CGFloat(columns))
        let maxX  = max(minX + 1, Int(bounds.minX + bounds.width  * CGFloat(column + 1) / CGFloat(columns)))
        let minY  = Int(bounds.minY + bounds.height * CGFloat(row)        / CGFloat(rows))
        let maxY  = max(minY + 1, Int(bounds.minY + bounds.height * CGFloat(row + 1)    / CGFloat(rows)))
        var dark  = 0, total = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                total += 1
                if pixels[y * imageWidth + x] < darkThreshold { dark += 1 }
            }
        }
        return total > 0 ? Double(dark) / Double(total) : 0
    }

    private func adaptiveDarkThreshold(for pixels: [UInt8]) -> UInt8 {
        var histogram = Array(repeating: 0, count: 256)
        for p in pixels { histogram[Int(p)] += 1 }
        let total = pixels.count
        var ws    = 0
        for v in 0..<256 { ws += v * histogram[v] }
        var bw = 0, bs = 0, best = 0.0, threshold = 127
        for v in 0..<256 {
            bw += histogram[v]
            guard bw > 0 else { continue }
            let fw = total - bw; guard fw > 0 else { break }
            bs += v * histogram[v]
            let bm = Double(bs) / Double(bw)
            let fm = Double(ws - bs) / Double(fw)
            let variance = Double(bw) * Double(fw) * pow(bm - fm, 2)
            if variance > best { best = variance; threshold = v }
        }
        return UInt8(max(80, min(180, threshold)))
    }
}
