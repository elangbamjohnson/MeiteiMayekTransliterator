//
//  OCRImagePreprocessor.swift
//  MeiteiMayekTranslator
//

import CoreImage
import ImageIO
import UIKit

struct DefaultOCRImagePreprocessor: OCRImagePreparing {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    func variants(for image: UIImage) -> [OCRImageVariant] {
        let normalized = image.normalizedForOCR()
        var variants = [OCRImageVariant(name: "original", image: normalized)]

        if let upscaled = resizeIfNeeded(normalized, minimumLongestSide: 1400, maximumLongestSide: 2200) {
            variants.append(OCRImageVariant(name: "upscaled", image: upscaled))
        }

        if let enhanced = enhancedTextImage(from: normalized) {
            variants.append(OCRImageVariant(name: "enhanced", image: enhanced))
        }

        if let binarized = binarizedTextImage(from: normalized) {
            variants.append(OCRImageVariant(name: "binarized", image: binarized))
        }

        if let textCrop = cropDarkTextRegion(from: normalized),
           textCrop.size.width > 8,
           textCrop.size.height > 8 {
            variants.append(OCRImageVariant(name: "text-crop", image: textCrop))
            if let croppedBinarized = binarizedTextImage(from: textCrop) {
                variants.append(OCRImageVariant(name: "text-crop-binarized", image: croppedBinarized))
            }
        }

        return variants
    }

    private func enhancedTextImage(from image: UIImage) -> UIImage? {
        guard let ciImage = ciImage(from: image) else { return nil }

        let output = ciImage
            .applyingFilter("CIPhotoEffectMono")
            .applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": 0.02,
                "inputSharpness": 0.7,
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.2,
                kCIInputBrightnessKey: 0.04,
                kCIInputSaturationKey: 0.0,
            ])
            .applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.9,
            ])

        return render(output, scale: image.scale, orientation: .up)
    }

    private func binarizedTextImage(from image: UIImage) -> UIImage? {
        guard let rendered = renderToGrayscale(image) else { return nil }
        let threshold = adaptiveDarkThreshold(for: rendered.pixels)
        let width = rendered.width
        let height = rendered.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = Array(repeating: UInt8(255), count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = rendered.pixels[y * width + x] < threshold ? 0 : 255
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

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private func cropDarkTextRegion(from image: UIImage) -> UIImage? {
        guard let rendered = renderToGrayscale(image),
              let cgImage = image.normalizedForOCR().cgImage else {
            return nil
        }

        let threshold = adaptiveDarkThreshold(for: rendered.pixels)
        var minX = rendered.width
        var minY = rendered.height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in 0..<rendered.height {
            for x in 0..<rendered.width where rendered.pixels[y * rendered.width + x] < threshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                found = true
            }
        }

        guard found else { return nil }

        let padding = 16
        let x = max(0, minX - padding)
        let y = max(0, minY - padding)
        let width = min(rendered.width - x, maxX - minX + 1 + padding * 2)
        let height = min(rendered.height - y, maxY - minY + 1 + padding * 2)
        let cropRect = CGRect(x: x, y: y, width: width, height: height)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private func resizeIfNeeded(
        _ image: UIImage,
        minimumLongestSide: CGFloat,
        maximumLongestSide: CGFloat
    ) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest < minimumLongestSide else { return nil }

        let targetLongest = min(maximumLongestSide, minimumLongestSide)
        let scale = targetLongest / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func ciImage(from image: UIImage) -> CIImage? {
        if let cgImage = image.normalizedForOCR().cgImage {
            return CIImage(cgImage: cgImage)
        }
        return CIImage(image: image.normalizedForOCR())
    }

    private func render(_ image: CIImage, scale: CGFloat, orientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = Self.context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    }

    private func renderToGrayscale(_ image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.normalizedForOCR().cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
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
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

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

        return (grayscale, width, height)
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

extension UIImage {
    func normalizedForOCR() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

