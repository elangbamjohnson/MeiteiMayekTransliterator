//
//  MeiteiMayekCoreMLOCRService.swift
//  MeiteiMayekTranslator
//

import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

nonisolated final class MeiteiMayekCoreMLOCRService: OCRDetailedRecognizing {
    private enum Constants {
        static let inputWidth = 128
        static let inputHeight = 32
        static let maxRenderDimension: CGFloat = 1_400
        static let minimumConfidence: Float = 0.25
    }

    private struct LineCrop {
        let image: UIImage
        let boundingBox: CGRect
    }

    private struct RenderedImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let darkThreshold: UInt8
    }

    private struct Prediction {
        let text: String
        let confidence: Float
    }

    private static let knownTextCorrections: [String: String] = [
        "ꯅꯤꯡꯊꯧꯀꯥꯕ": "ꯅꯤꯡꯊꯧꯀꯥꯕꯥ",
        "ꯂꯩꯕꯥꯛꯄꯣꯛꯄ": "ꯂꯩꯕꯥꯛꯄꯣꯛꯄꯥ",
    ]

    private let fallbackRecognizer: OCRDetailedRecognizing
    private lazy var model: MLModel? = Self.loadModel()
    private lazy var vocabulary: [String]? = Self.loadVocabulary()

    init(fallbackRecognizer: OCRDetailedRecognizing = LocalMayekGlyphRecognizer()) {
        self.fallbackRecognizer = fallbackRecognizer
    }

    func recognizeText(from image: UIImage) async throws -> String {
        try await recognizeDetailed(from: image, source: "Meitei Core ML", variantName: "direct").extractedText
    }

    func recognizeDetailed(
        from image: UIImage,
        source: String,
        variantName: String
    ) async throws -> OCRRecognitionResult {
        guard let model, let vocabulary else {
            return try await fallbackRecognizer.recognizeDetailed(
                from: image,
                source: "Local Mayek",
                variantName: variantName + "-fallback"
            )
        }

        let crops = lineCrops(from: image)
        guard !crops.isEmpty else {
            return try await fallbackRecognizer.recognizeDetailed(
                from: image,
                source: "Local Mayek",
                variantName: variantName + "-fallback"
            )
        }

        var lines: [String] = []
        var blocks: [OCRTextBlock] = []
        var confidences: [Float] = []

        for crop in crops {
            let prediction = try predict(crop.image, model: model, vocabulary: vocabulary)
            let extracted = Self.correctKnownText(
                MeiteiMayekTextCleaner.extractMayekText(from: prediction.text)
            )
            guard !extracted.isEmpty, prediction.confidence >= Constants.minimumConfidence else {
                continue
            }

            lines.append(extracted)
            confidences.append(prediction.confidence)
            blocks.append(OCRTextBlock(
                text: extracted,
                confidence: prediction.confidence,
                boundingBox: crop.boundingBox,
                candidates: [OCRTextCandidate(text: prediction.text, confidence: prediction.confidence)]
            ))
        }

        let rawText = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            return try await fallbackRecognizer.recognizeDetailed(
                from: image,
                source: "Local Mayek",
                variantName: variantName + "-fallback"
            )
        }

        let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)
        return OCRRecognitionResult.fromRawText(
            rawText,
            source: source,
            variantName: variantName + "-coreml",
            confidence: confidence,
            boundingBox: combinedBoundingBox(from: blocks),
            blocks: blocks
        )
    }

    private static func loadModel() -> MLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly

        if let compiledURL = Bundle.main.url(forResource: "MeiteiMayekOCR", withExtension: "mlmodelc") {
            return try? MLModel(contentsOf: compiledURL, configuration: config)
        }

        if let packageURL = Bundle.main.url(forResource: "MeiteiMayekOCR", withExtension: "mlpackage", subdirectory: "Models") ??
            Bundle.main.url(forResource: "MeiteiMayekOCR", withExtension: "mlpackage") {
            return try? MLModel(contentsOf: packageURL, configuration: config)
        }

        return nil
    }

    private static func correctKnownText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line in
                let words = line.split(separator: " ").map(String.init)
                guard !words.isEmpty else { return line }
                return words
                    .map { knownTextCorrections[$0] ?? $0 }
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    private static func loadVocabulary() -> [String]? {
        let url = Bundle.main.url(forResource: "MeiteiMayekOCRVocab", withExtension: "json", subdirectory: "Models") ??
            Bundle.main.url(forResource: "MeiteiMayekOCRVocab", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = payload["vocab"] as? [String],
              values.count > 1 else {
            return nil
        }

        return Array(values.dropFirst()) + ["<eos>"]
    }

    private func predict(_ image: UIImage, model: MLModel, vocabulary: [String]) throws -> Prediction {
        let input = try mlArray(from: image)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": input]))
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw TransliterationService.ServiceError.ocrFailed("Meitei Core ML model returned no logits.")
        }
        return decode(logits, vocabulary: vocabulary)
    }

    private func decode(_ logits: MLMultiArray, vocabulary: [String]) -> Prediction {
        let sequenceLength = logits.shape.count >= 2 ? logits.shape[1].intValue : 0
        let classCount = logits.shape.count >= 3 ? logits.shape[2].intValue : vocabulary.count
        var output = ""
        var probabilities: [Float] = []

        for position in 0..<sequenceLength {
            var bestIndex = 0
            var bestLogit = -Float.greatestFiniteMagnitude
            var maxLogit = -Float.greatestFiniteMagnitude
            var logitsForPosition = Array(repeating: Float.zero, count: classCount)

            for index in 0..<classCount {
                let value = logits[[0, position, index] as [NSNumber]].floatValue
                logitsForPosition[index] = value
                if value > bestLogit {
                    bestLogit = value
                    bestIndex = index
                }
                maxLogit = max(maxLogit, value)
            }

            guard bestIndex < vocabulary.count else { break }
            let token = vocabulary[bestIndex]
            if token == "<eos>" { break }
            output.append(token)

            let expSum = logitsForPosition.reduce(Float.zero) { partial, value in
                partial + exp(value - maxLogit)
            }
            probabilities.append(exp(bestLogit - maxLogit) / max(expSum, Float.leastNonzeroMagnitude))
        }

        let confidence = probabilities.isEmpty ? 0 : probabilities.reduce(0, +) / Float(probabilities.count)
        return Prediction(text: output, confidence: confidence)
    }

    private func lineCrops(from image: UIImage) -> [LineCrop] {
        guard let rendered = render(image, maxDimension: Constants.maxRenderDimension),
              let pageBounds = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                darkThreshold: rendered.darkThreshold
              ) else {
            return [LineCrop(image: image.normalizedForOCR(), boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))]
        }

        let lineRects = detectedLineRects(in: rendered, pageBounds: pageBounds)
        let sourceScaleX = image.normalizedForOCR().size.width / CGFloat(rendered.width)
        let sourceScaleY = image.normalizedForOCR().size.height / CGFloat(rendered.height)

        let crops = lineRects.compactMap { rect -> LineCrop? in
            let paddedRect = paddedLineRect(
                rect,
                imageBounds: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height)
            )
            let normalizedBox = normalizedVisionBox(from: rect, width: rendered.width, height: rendered.height)
            let sourceRect = CGRect(
                x: paddedRect.minX * sourceScaleX,
                y: paddedRect.minY * sourceScaleY,
                width: paddedRect.width * sourceScaleX,
                height: paddedRect.height * sourceScaleY
            )
            guard let cropped = crop(image.normalizedForOCR(), to: sourceRect) else { return nil }
            return LineCrop(image: cropped, boundingBox: normalizedBox)
        }

        return crops.isEmpty ? [LineCrop(image: image.normalizedForOCR(), boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))] : crops
    }

    private func mlArray(from image: UIImage) throws -> MLMultiArray {
        let normalized = image.normalizedForOCR()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: Constants.inputWidth, height: Constants.inputHeight))
        let resized = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: Constants.inputWidth, height: Constants.inputHeight))
            normalized.draw(in: CGRect(x: 0, y: 0, width: Constants.inputWidth, height: Constants.inputHeight))
        }

        guard let cgImage = resized.cgImage else {
            throw TransliterationService.ServiceError.invalidImageData
        }

        let width = Constants.inputWidth
        let height = Constants.inputHeight
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
            throw TransliterationService.ServiceError.invalidImageData
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32)
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * bytesPerRow + x * bytesPerPixel
                array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: Float(data[sourceOffset]) / 255.0)
                array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: Float(data[sourceOffset + 1]) / 255.0)
                array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: Float(data[sourceOffset + 2]) / 255.0)
            }
        }
        return array
    }

    private func render(_ image: UIImage, maxDimension: CGFloat) -> RenderedImage? {
        guard let source = image.normalizedForOCR().cgImage else { return nil }
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

        let darkThreshold = adaptiveDarkThreshold(for: grayscale)
        removeDarkEdgeArtifacts(
            from: &grayscale,
            width: width,
            height: height,
            darkThreshold: darkThreshold
        )

        return RenderedImage(
            pixels: grayscale,
            width: width,
            height: height,
            darkThreshold: darkThreshold
        )
    }

    private func detectedLineRects(in rendered: RenderedImage, pageBounds: CGRect) -> [CGRect] {
        let minX = max(0, Int(pageBounds.minX))
        let maxX = min(rendered.width, Int(pageBounds.maxX))
        let minY = max(0, Int(pageBounds.minY))
        let maxY = min(rendered.height, Int(pageBounds.maxY))
        let projection = (minY..<maxY).map { y in
            var count = 0
            for x in minX..<maxX where rendered.pixels[y * rendered.width + x] < rendered.darkThreshold {
                count += 1
            }
            return count
        }

        let minimumInk = max(3, Int(pageBounds.width * 0.006))
        let ranges = darkRanges(from: projection, origin: minY, minimumInk: minimumInk)
        let merged = mergeRanges(ranges, maximumGap: markMergeGap(for: rendered.height))
        return merged.compactMap { range in
            guard let rect = darkPixelBounds(
                in: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                darkThreshold: rendered.darkThreshold,
                limitedToRows: range
            ), rect.height >= max(8, CGFloat(rendered.height) * 0.035) else {
                return nil
            }
            return rect.insetBy(dx: -6, dy: -6)
                .intersection(CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        }
    }

    private func markMergeGap(for height: Int) -> Int {
        max(8, min(32, height / 30))
    }

    private func removeDarkEdgeArtifacts(
        from pixels: inout [UInt8],
        width: Int,
        height: Int,
        darkThreshold: UInt8
    ) {
        var artifactColumns: [Int] = []
        for x in 0..<width {
            var darkCount = 0
            var currentRun = 0
            var longestRun = 0

            for y in 0..<height {
                if pixels[y * width + x] < darkThreshold {
                    darkCount += 1
                    currentRun += 1
                    longestRun = max(longestRun, currentRun)
                } else {
                    currentRun = 0
                }
            }

            let density = Double(darkCount) / Double(max(1, height))
            let nearEdge = x < width / 12 || x > width - (width / 12)
            if density > 0.55 || (nearEdge && Double(longestRun) > Double(height) * 0.55) {
                artifactColumns.append(x)
            }
        }

        for x in artifactColumns {
            for y in 0..<height {
                pixels[y * width + x] = 255
            }
        }

        var artifactRows: [Int] = []
        for y in 0..<height {
            var darkCount = 0
            var currentRun = 0
            var longestRun = 0

            for x in 0..<width {
                if pixels[y * width + x] < darkThreshold {
                    darkCount += 1
                    currentRun += 1
                    longestRun = max(longestRun, currentRun)
                } else {
                    currentRun = 0
                }
            }

            let density = Double(darkCount) / Double(max(1, width))
            let nearEdge = y < height / 12 || y > height - (height / 12)
            if density > 0.55 || (nearEdge && Double(longestRun) > Double(width) * 0.55) {
                artifactRows.append(y)
            }
        }

        for y in artifactRows {
            for x in 0..<width {
                pixels[y * width + x] = 255
            }
        }
    }

    private func darkRanges(from projection: [Int], origin: Int, minimumInk: Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        var lastDark: Int?

        for (offset, count) in projection.enumerated() {
            let position = origin + offset
            if count >= minimumInk {
                if start == nil { start = position }
                lastDark = position
            } else if let s = start, let e = lastDark {
                ranges.append(s..<(e + 1))
                start = nil
                lastDark = nil
            }
        }

        if let s = start, let e = lastDark {
            ranges.append(s..<(e + 1))
        }

        return ranges
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

    private func paddedLineRect(_ rect: CGRect, imageBounds: CGRect) -> CGRect {
        let horizontalPadding = max(CGFloat(12), rect.width * 0.12)
        let verticalPadding = max(CGFloat(10), rect.height * 0.12)
        return rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            .intersection(imageBounds)
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

    private func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let scale = image.scale
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
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
