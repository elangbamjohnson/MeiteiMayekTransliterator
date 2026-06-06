#if canImport(Testing)
import Testing
import UIKit

@Suite("Transliteration pipeline")
struct TransliterationPipelineTests {

    @Test
    func mayekRatio() async throws {
        #expect(MeiteiTextUtilities.mayekRatio(in: "ꯑꯃꯤ") == 1.0)
        #expect(MeiteiTextUtilities.mayekRatio(in: "hello") == 0.0)
        #expect(MeiteiTextUtilities.mayekRatio(in: "ꯑ a") > 0.4)
    }

    @Test
    func scriptDetector() async throws {
        #expect(ScriptDetector.detectScript("ꯑꯃꯤ") == "Meitei Mayek")
        #expect(ScriptDetector.detectScript("অ আ ই") == "Bengali")
        #expect(ScriptDetector.detectScript("hello") == "Unknown")
    }

    @Test
    func syllableRomanizer() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯃꯤ") == "Mi")
    }

    @Test
    func extractMayekFromNoisyOCR() async throws {
        let noisy = "Detected: hello ꯃꯤꯇꯩ | 123"
        let extracted = MeiteiTextUtilities.extractMayekScript(from: noisy)
        #expect(extracted.contains("ꯃ"))
        #expect(MeiteiTextUtilities.mayekCharacterCount(in: extracted) >= 3)
    }

    @Test
    func extractMayekKeepsSeparatedNoisyFragmentsApart() async throws {
        let noisy = "Detected: ꯃ hello ꯇꯩ | done"
        #expect(MeiteiTextUtilities.extractMayekScript(from: noisy) == "ꯃ ꯇꯩ")
    }

    @Test
    func cleanerKeepsMainAndExtensionMayekRanges() async throws {
        let extensionScalar = try #require(UnicodeScalar(0xAAE0))
        let text = "abc ꯃ\(String(extensionScalar)) 123"
        #expect(MeiteiMayekTextCleaner.extractMayekText(from: text) == "ꯃ\(String(extensionScalar))")
    }

    @Test
    func readingOrderSortsTopToBottomThenLeftToRight() async throws {
        let lower = OCRTextBlock(text: "lower", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), candidates: [])
        let topRight = OCRTextBlock(text: "right", confidence: 0.9, boundingBox: CGRect(x: 0.7, y: 0.8, width: 0.2, height: 0.1), candidates: [])
        let topLeft = OCRTextBlock(text: "left", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.1), candidates: [])

        let sorted = OCRService.sortedReadingOrder([lower, topRight, topLeft])

        #expect(sorted.map(\.text) == ["left", "right", "lower"])
    }

    @Test
    func lowConfidenceBlocksAreRejected() async throws {
        let blocks = [
            OCRTextBlock(text: "keep", confidence: 0.6, boundingBox: nil, candidates: []),
            OCRTextBlock(text: "drop", confidence: 0.04, boundingBox: nil, candidates: []),
        ]

        #expect(OCRService.rejectLowConfidence(blocks, minimumConfidence: 0.05).map(\.text) == ["keep"])
    }

    @Test
    func rawOCRResultSeparatesCleanedAndExtractedText() async throws {
        let result = OCRRecognitionResult.fromRawText(
            "Detected: hello ꯃꯤ | done",
            source: "test",
            variantName: "unit",
            confidence: 0.7
        )

        #expect(result.cleanedText == "hello ꯃꯤ | done")
        #expect(result.extractedText == "ꯃꯤ")
        #expect(result.mayekCount == 2)
    }

    @Test
    func localTransliterationService() async throws {
        let service = TransliterationService()
        let result = try service.transliterateText("ꯑ ꯃꯤ")
        #expect(result.transliterationEngine == "On-device")
        #expect(result.englishTransliteration == "A Mi")
        #expect(MeiteiTextUtilities.isEnglishAlphabetTransliteration(result.englishTransliteration))
        #expect(!MeiteiTextUtilities.containsMayek(result.englishTransliteration))
    }

    @Test
    func englishAlphabetValidator() async throws {
        #expect(MeiteiTextUtilities.isEnglishAlphabetTransliteration("Mitay"))
        #expect(!MeiteiTextUtilities.isEnglishAlphabetTransliteration("ꯃꯤ"))
    }

    @Test
    func imageOCRAcceptsSingleMayekCharacter() async throws {
        let service = TransliterationService(
            cloudOCR: StubOCR(text: "not mayek"),
            onDeviceOCR: StubOCR(text: "ꯑ"),
            imagePreprocessor: SingleVariantPreprocessor()
        )

        let result = try await service.processImage(Self.testImage())
        #expect(result.detectedScript == "ꯑ")
        #expect(result.englishTransliteration == "A")
        #expect(result.ocrSource == "Apple Vision / test")
    }

    @Test
    func imageOCRExtractsMayekFromNoisyProviderText() async throws {
        let service = TransliterationService(
            cloudOCR: StubOCR(text: "Detected: ꯃ hello ꯇꯩ | done"),
            onDeviceOCR: StubOCR(text: "latin only"),
            imagePreprocessor: SingleVariantPreprocessor()
        )

        let result = try await service.processImage(Self.testImage())
        #expect(result.detectedScript == "ꯃ ꯇꯩ")
        #expect(result.ocrSource == "OCR.space / test")
    }

    @Test
    func localImageOCRExtractsNupiFromFixtureImage() async throws {
        let image = try #require(Self.fixtureImage(named: "meitei_mayek_nupi", extension: "png"))
        let service = TransliterationService(
            cloudOCR: FailingOCR(),
            onDeviceOCR: FailingOCR(),
            localImageOCR: LocalMayekGlyphRecognizer()
        )

        let result = try await service.processImage(image)

        #expect(result.detectedScript == "ꯅꯨꯞꯤ")
    }

    private static func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static func fixtureImage(named name: String, extension fileExtension: String) -> UIImage? {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MeiteiMayekTranslator")
            .appendingPathComponent("\(name).\(fileExtension)")
        return UIImage(contentsOfFile: sourceURL.path)
    }
}

private struct SingleVariantPreprocessor: OCRImagePreparing {
    func variants(for image: UIImage) -> [OCRImageVariant] {
        [OCRImageVariant(name: "test", image: image)]
    }
}

private final class StubOCR: OCRRecognizing {
    let text: String

    init(text: String) {
        self.text = text
    }

    func recognizeText(from image: UIImage) async throws -> String {
        text
    }
}

private final class FailingOCR: OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String {
        throw TransliterationService.ServiceError.ocrFailed("Disabled in fixture test.")
    }
}
#elseif canImport(XCTest)
import XCTest
import UIKit
@testable import MeiteiMayekTranslator

final class TransliterationPipelineTests: XCTestCase {

    func testMayekRatio() {
        XCTAssertEqual(MeiteiTextUtilities.mayekRatio(in: "ꯑꯃꯤ"), 1.0)
        XCTAssertEqual(MeiteiTextUtilities.mayekRatio(in: "hello"), 0.0)
        XCTAssertGreaterThan(MeiteiTextUtilities.mayekRatio(in: "ꯑ a"), 0.4)
    }

    func testScriptDetector() {
        XCTAssertEqual(ScriptDetector.detectScript("ꯑꯃꯤ"), "Meitei Mayek")
        XCTAssertEqual(ScriptDetector.detectScript("অ আ ই"), "Bengali")
        XCTAssertEqual(ScriptDetector.detectScript("hello"), "Unknown")
    }

    func testSyllableRomanizer() {
        let r = MeiteiMayekRomanizer()
        XCTAssertEqual(r.romanize("ꯃꯤ"), "Mi")
    }

    func testExtractMayekFromNoisyOCR() {
        let noisy = "Detected: hello ꯃꯤꯇꯩ | 123"
        let extracted = MeiteiTextUtilities.extractMayekScript(from: noisy)
        XCTAssertTrue(extracted.contains("ꯃ"))
        XCTAssertGreaterThanOrEqual(MeiteiTextUtilities.mayekCharacterCount(in: extracted), 3)
    }

    func testExtractMayekKeepsSeparatedNoisyFragmentsApart() {
        let noisy = "Detected: ꯃ hello ꯇꯩ | done"
        XCTAssertEqual(MeiteiTextUtilities.extractMayekScript(from: noisy), "ꯃ ꯇꯩ")
    }

    func testCleanerKeepsMainAndExtensionMayekRanges() throws {
        let extensionScalar = try XCTUnwrap(UnicodeScalar(0xAAE0))
        let text = "abc ꯃ\(String(extensionScalar)) 123"
        XCTAssertEqual(MeiteiMayekTextCleaner.extractMayekText(from: text), "ꯃ\(String(extensionScalar))")
    }

    func testReadingOrderSortsTopToBottomThenLeftToRight() {
        let lower = OCRTextBlock(text: "lower", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), candidates: [])
        let topRight = OCRTextBlock(text: "right", confidence: 0.9, boundingBox: CGRect(x: 0.7, y: 0.8, width: 0.2, height: 0.1), candidates: [])
        let topLeft = OCRTextBlock(text: "left", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.1), candidates: [])

        let sorted = OCRService.sortedReadingOrder([lower, topRight, topLeft])

        XCTAssertEqual(sorted.map(\.text), ["left", "right", "lower"])
    }

    func testLowConfidenceBlocksAreRejected() {
        let blocks = [
            OCRTextBlock(text: "keep", confidence: 0.6, boundingBox: nil, candidates: []),
            OCRTextBlock(text: "drop", confidence: 0.04, boundingBox: nil, candidates: []),
        ]

        XCTAssertEqual(OCRService.rejectLowConfidence(blocks, minimumConfidence: 0.05).map(\.text), ["keep"])
    }

    func testRawOCRResultSeparatesCleanedAndExtractedText() {
        let result = OCRRecognitionResult.fromRawText(
            "Detected: hello ꯃꯤ | done",
            source: "test",
            variantName: "unit",
            confidence: 0.7
        )

        XCTAssertEqual(result.cleanedText, "hello ꯃꯤ | done")
        XCTAssertEqual(result.extractedText, "ꯃꯤ")
        XCTAssertEqual(result.mayekCount, 2)
    }

    func testLocalTransliterationService() throws {
        let service = TransliterationService()
        let result = try service.transliterateText("ꯑ ꯃꯤ")
        XCTAssertEqual(result.transliterationEngine, "On-device")
        XCTAssertEqual(result.englishTransliteration, "A Mi")
        XCTAssertTrue(MeiteiTextUtilities.isEnglishAlphabetTransliteration(result.englishTransliteration))
        XCTAssertFalse(MeiteiTextUtilities.containsMayek(result.englishTransliteration))
    }

    func testEnglishAlphabetValidator() {
        XCTAssertTrue(MeiteiTextUtilities.isEnglishAlphabetTransliteration("Mitay"))
        XCTAssertFalse(MeiteiTextUtilities.isEnglishAlphabetTransliteration("ꯃꯤ"))
    }

    func testImageOCRAcceptsSingleMayekCharacter() async throws {
        let service = TransliterationService(
            cloudOCR: StubOCR(text: "not mayek"),
            onDeviceOCR: StubOCR(text: "ꯑ"),
            imagePreprocessor: SingleVariantPreprocessor()
        )

        let result = try await service.processImage(Self.testImage())
        XCTAssertEqual(result.detectedScript, "ꯑ")
        XCTAssertEqual(result.englishTransliteration, "A")
        XCTAssertEqual(result.ocrSource, "Apple Vision / test")
    }

    func testImageOCRExtractsMayekFromNoisyProviderText() async throws {
        let service = TransliterationService(
            cloudOCR: StubOCR(text: "Detected: ꯃ hello ꯇꯩ | done"),
            onDeviceOCR: StubOCR(text: "latin only"),
            imagePreprocessor: SingleVariantPreprocessor()
        )

        let result = try await service.processImage(Self.testImage())
        XCTAssertEqual(result.detectedScript, "ꯃ ꯇꯩ")
        XCTAssertEqual(result.ocrSource, "OCR.space / test")
    }

    func testLocalImageOCRExtractsNupiFromFixtureImage() async throws {
        let image = try XCTUnwrap(Self.fixtureImage(named: "meitei_mayek_nupi", extension: "png"))
        let service = TransliterationService(
            cloudOCR: FailingOCR(),
            onDeviceOCR: FailingOCR(),
            localImageOCR: LocalMayekGlyphRecognizer()
        )

        let result = try await service.processImage(image)

        XCTAssertEqual(result.detectedScript, "ꯅꯨꯞꯤ")
    }

    private static func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static func fixtureImage(named name: String, extension fileExtension: String) -> UIImage? {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MeiteiMayekTranslator")
            .appendingPathComponent("\(name).\(fileExtension)")
        return UIImage(contentsOfFile: sourceURL.path)
    }
}

private struct SingleVariantPreprocessor: OCRImagePreparing {
    func variants(for image: UIImage) -> [OCRImageVariant] {
        [OCRImageVariant(name: "test", image: image)]
    }
}

private final class StubOCR: OCRRecognizing {
    let text: String

    init(text: String) {
        self.text = text
    }

    func recognizeText(from image: UIImage) async throws -> String {
        text
    }
}

private final class FailingOCR: OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String {
        throw TransliterationService.ServiceError.ocrFailed("Disabled in fixture test.")
    }
}
#endif
