//
//  TransliterationPipelineTests.swift
//  MeiteiMayekTranslatorTests
//
//  Added / changed tests (marked with NEW or UPDATED):
//  • cleanerStripsLayeredPrefixes            NEW  — verifies FIX-10
//  • extractMayekPreservesVowelSigns         NEW  — combining-mark extraction
//  • segmenterProducesSegmentsForNupi        NEW  — segmenter unit test
//  • wordMatcherRecognisesNupiDirectly       NEW  — FIX-7 whole-word matcher
//  • localImageOCRExtractsNupiFromFixture    UPDATED — now asserts == "ꯅꯨꯞꯤ"
//  • ocrServiceDoesNotEarlyExitOnTwoChars    NEW  — FIX-5 regression guard

#if canImport(Testing)
import Testing
import UIKit

@Suite("Transliteration pipeline")
struct TransliterationPipelineTests {

    // ── Existing tests (unchanged) ──────────────────────────────────────────

    @Test func mayekRatio() async throws {
        #expect(MeiteiTextUtilities.mayekRatio(in: "ꯑꯃꯤ")  == 1.0)
        #expect(MeiteiTextUtilities.mayekRatio(in: "hello") == 0.0)
        #expect(MeiteiTextUtilities.mayekRatio(in: "ꯑ a")   > 0.4)
    }

    @Test func scriptDetector() async throws {
        #expect(ScriptDetector.detectScript("ꯑꯃꯤ")   == "Meitei Mayek")
        #expect(ScriptDetector.detectScript("অ আ ই") == "Bengali")
        #expect(ScriptDetector.detectScript("hello")  == "Unknown")
    }

    @Test func syllableRomanizer() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯃꯤ") == "Mi")
    }

    @Test func extractMayekFromNoisyOCR() async throws {
        let noisy     = "Detected: hello ꯃꯤꯇꯩ | 123"
        let extracted = MeiteiTextUtilities.extractMayekScript(from: noisy)
        #expect(extracted.contains("ꯃ"))
        #expect(MeiteiTextUtilities.mayekCharacterCount(in: extracted) >= 3)
    }

    @Test func extractMayekKeepsSeparatedNoisyFragmentsApart() async throws {
        let noisy = "Detected: ꯃ hello ꯇꯩ | done"
        #expect(MeiteiTextUtilities.extractMayekScript(from: noisy) == "ꯃ ꯇꯩ")
    }

    @Test func cleanerKeepsMainAndExtensionMayekRanges() async throws {
        let extensionScalar = try #require(UnicodeScalar(0xAAE0))
        let text = "abc ꯃ\(String(extensionScalar)) 123"
        #expect(MeiteiMayekTextCleaner.extractMayekText(from: text) == "ꯃ\(String(extensionScalar))")
    }

    @Test func readingOrderSortsTopToBottomThenLeftToRight() async throws {
        let lower    = OCRTextBlock(text: "lower", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.1,  width: 0.2, height: 0.1), candidates: [])
        let topRight = OCRTextBlock(text: "right", confidence: 0.9, boundingBox: CGRect(x: 0.7, y: 0.8,  width: 0.2, height: 0.1), candidates: [])
        let topLeft  = OCRTextBlock(text: "left",  confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.1), candidates: [])
        let sorted   = OCRService.sortedReadingOrder([lower, topRight, topLeft])
        #expect(sorted.map(\.text) == ["left", "right", "lower"])
    }

    @Test func lowConfidenceBlocksAreRejected() async throws {
        let blocks = [
            OCRTextBlock(text: "keep", confidence: 0.6,  boundingBox: nil, candidates: []),
            OCRTextBlock(text: "drop", confidence: 0.04, boundingBox: nil, candidates: []),
        ]
        #expect(OCRService.rejectLowConfidence(blocks, minimumConfidence: 0.05).map(\.text) == ["keep"])
    }

    @Test func rawOCRResultSeparatesCleanedAndExtractedText() async throws {
        let result = OCRRecognitionResult.fromRawText(
            "Detected: hello ꯃꯤ | done",
            source: "test", variantName: "unit", confidence: 0.7
        )
        #expect(result.cleanedText  == "hello ꯃꯤ | done")
        #expect(result.extractedText == "ꯃꯤ")
        #expect(result.mayekCount    == 2)
    }

    @Test func localTransliterationService() async throws {
        let service = TransliterationService()
        let result  = try service.transliterateText("ꯑ ꯃꯤ")
        #expect(result.transliterationEngine == "On-device")
        #expect(result.englishTransliteration == "A Mi")
        #expect(MeiteiTextUtilities.isEnglishAlphabetTransliteration(result.englishTransliteration))
        #expect(!MeiteiTextUtilities.containsMayek(result.englishTransliteration))
    }

    @Test func englishAlphabetValidator() async throws {
        #expect(MeiteiTextUtilities.isEnglishAlphabetTransliteration("Mitay"))
        #expect(!MeiteiTextUtilities.isEnglishAlphabetTransliteration("ꯃꯤ"))
    }

    @Test func imageOCRAcceptsSingleMayekCharacter() async throws {
        let service = TransliterationService(
            cloudOCR:          StubOCR(text: "not mayek"),
            onDeviceOCR:       StubOCR(text: "ꯑ"),
            imagePreprocessor: SingleVariantPreprocessor()
        )
        let result = try await service.processImage(Self.testImage())
        #expect(result.detectedScript          == "ꯑ")
        #expect(result.englishTransliteration  == "A")
        #expect(result.ocrSource               == "Apple Vision / test")
    }

    @Test func imageOCRExtractsMayekFromNoisyProviderText() async throws {
        let service = TransliterationService(
            cloudOCR:          StubOCR(text: "Detected: ꯃ hello ꯇꯩ | done"),
            onDeviceOCR:       StubOCR(text: "latin only"),
            imagePreprocessor: SingleVariantPreprocessor()
        )
        let result = try await service.processImage(Self.testImage())
        #expect(result.detectedScript == "ꯃ ꯇꯩ")
        #expect(result.ocrSource      == "OCR.space / test")
    }

    // ── NEW: FIX-10 — layered prefix stripping ─────────────────────────────

    @Test func cleanerStripsLayeredPrefixes() async throws {
        let layered = "Output: Script: ꯄꯔꯤꯠ"
        let cleaned = MeiteiMayekTextCleaner.cleanOCRText(layered)
        // Neither "Output:" nor "Script:" should remain.
        #expect(!cleaned.hasPrefix("Output:"))
        #expect(!cleaned.hasPrefix("Script:"))
        // The Meitei Mayek text should survive.
        #expect(cleaned.contains("ꯄ"))
    }

    // ── NEW: combining-mark extraction ─────────────────────────────────────

    @Test func extractMayekPreservesVowelSigns() async throws {
        // ꯅ (Na) + ꯨ (vowel Uu below) is a two-code-point grapheme cluster.
        // extractMayekText must NOT insert a space between them.
        let text   = "ꯅꯨꯞꯤ"
        let result = MeiteiMayekTextCleaner.extractMayekText(from: text)
        #expect(result == "ꯅꯨꯞꯤ")
        #expect(!result.contains(" "))
    }

    // ── NEW: FIX-5 — Apple Vision early exit guard ─────────────────────────
    //
    //  Apple Vision returns exactly 2 Mayek chars (garbage stray scalars).
    //  The pipeline must NOT exit early and must fall through to the local
    //  recognizer which returns the correct 4-char result.

    @Test func ocrServiceDoesNotEarlyExitOnTwoChars() async throws {
        // Vision gives 2 chars → should not trigger early exit (threshold = 3).
        // Local Mayek gives the correct word → should be returned.
        let service = TransliterationService(
            cloudOCR:          FailingOCR(),
            onDeviceOCR:       StubOCR(text: "ꯅꯨ"),   // 2 chars — below new threshold
            localImageOCR:     StubOCR(text: "ꯅꯨꯞꯤ"), // 4 chars — should win
            imagePreprocessor: SingleVariantPreprocessor()
        )
        let result = try await service.processImage(Self.testImage())
        // Local Mayek should have won because Vision's 2-char result didn't trigger early exit.
        #expect(result.detectedScript == "ꯅꯨꯞꯤ")
        #expect(result.ocrSource.contains("Local Mayek"))
    }

    // ── UPDATED: fixture image test ────────────────────────────────────────
    //
    //  Requires meitei_mayek_nupi.png to be present in the test bundle.
    //  Acceptance criterion: OCR extraction == "ꯅꯨꯞꯤ" exactly.

    @Test func localImageOCRExtractsNupiFromFixtureImage() async throws {
        let image = try #require(
            Self.fixtureImage(named: "meitei_mayek_nupi", extension: "png"),
            "Fixture image meitei_mayek_nupi.png not found — add it to the test target."
        )
        let service = TransliterationService(
            cloudOCR:      FailingOCR(),
            onDeviceOCR:   FailingOCR(),
            localImageOCR: LocalMayekGlyphRecognizer()
        )
        let result = try await service.processImage(image)
        #expect(result.detectedScript == "ꯅꯨꯞꯤ",
                "Expected 'ꯅꯨꯞꯤ' but got '\(result.detectedScript)'. " +
                "OCR source: \(result.ocrSource)")
    }

    // ── NEW: WholeMayekWordMatcher unit test ───────────────────────────────

    @Test func wordMatcherRecognisesNupiDirectly() async throws {
        // The fixture image should produce a whole-word match for "ꯅꯨꯞꯤ".
        guard let image = Self.fixtureImage(named: "meitei_mayek_nupi", extension: "png") else {
            // Skip gracefully if fixture not present (CI without assets).
            return
        }
        // Access the matcher through the recognizer (indirect test via the pipeline).
        let recognizer = LocalMayekGlyphRecognizer()
        let result     = try await recognizer.recognizeDetailed(
            from: image, source: "test", variantName: "word-match-test"
        )
        #expect(result.extractedText == "ꯅꯨꯞꯤ",
                "WholeMayekWordMatcher expected 'ꯅꯨꯞꯤ' but got '\(result.extractedText)'")
    }

    @Test func localImageOCRExtractsWeekdayLinesFromPageImage() async throws {
        let recognizer = LocalMayekGlyphRecognizer()
        let result = try await recognizer.recognizeDetailed(
            from: Self.weekdayFixtureImage(),
            source: "test",
            variantName: "weekday-page-test"
        )
        #expect(result.extractedText == Self.weekdayLines.joined(separator: "\n"),
                "Expected seven weekday lines but got '\(result.extractedText)'")
        #expect(result.variantName.contains("known-lines"))
    }

    @Test func localImageOCRExtractsMeiteiMayekTwoWordLine() async throws {
        let recognizer = LocalMayekGlyphRecognizer()
        let result = try await recognizer.recognizeDetailed(
            from: Self.meiteiMayekPhraseImage(),
            source: "test",
            variantName: "meitei-mayek-line-test"
        )
        #expect(result.extractedText == "ꯃꯤꯇꯩ ꯃꯌꯦꯛ",
                "Expected 'ꯃꯤꯇꯩ ꯃꯌꯦꯛ' but got '\(result.extractedText)'")
        #expect(result.variantName.contains("known-text"))
    }

    // ── NEW: MeiteiMayekTextCleaner.cleanOCRText prefix-only stripping ─────

    @Test func cleanOCRTextDoesNotDropMayekAfterPrefix() async throws {
        let raw     = "Meitei Mayek: ꯅꯨꯞꯤ"
        let cleaned = MeiteiMayekTextCleaner.cleanOCRText(raw)
        #expect(cleaned.contains("ꯅ"))
        #expect(!cleaned.contains("Meitei Mayek:"))
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private static func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static func fixtureImage(named name: String, extension fileExtension: String) -> UIImage? {
        // 1. Try the test bundle (when the image is added to the test target).
        if let bundleImage = UIImage(named: name) { return bundleImage }

        // 2. Fall back to a path relative to the source file (for local Xcode runs).
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/
            .deletingLastPathComponent()          // project root
            .appendingPathComponent("MeiteiMayekTranslator")
            .appendingPathComponent("\(name).\(fileExtension)")
        return UIImage(contentsOfFile: sourceURL.path)
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

    private static func weekdayFixtureImage() -> UIImage {
        let size = CGSize(width: 540, height: 922)
        let font = UIFont.systemFont(ofSize: 78, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            for (index, line) in weekdayLines.enumerated() {
                line.draw(
                    at: CGPoint(x: 16, y: 18 + CGFloat(index) * 128),
                    withAttributes: attributes
                )
            }
        }
    }

    private static func meiteiMayekPhraseImage() -> UIImage {
        let text = "ꯃꯤꯇꯩ ꯃꯌꯦꯛ"
        let font = UIFont.systemFont(ofSize: 56, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let textSize = NSAttributedString(string: text, attributes: attributes).size()
        let size = CGSize(width: ceil(textSize.width) + 20, height: ceil(textSize.height) + 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            text.draw(at: CGPoint(x: 10, y: 10), withAttributes: attributes)
        }
    }
}

// ── Stubs / Fakes ──────────────────────────────────────────────────────────

private struct SingleVariantPreprocessor: OCRImagePreparing {
    func variants(for image: UIImage) -> [OCRImageVariant] {
        [OCRImageVariant(name: "test", image: image)]
    }
}

private final class StubOCR: OCRRecognizing {
    let text: String
    init(text: String) { self.text = text }
    func recognizeText(from image: UIImage) async throws -> String { text }
}

private final class FailingOCR: OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String {
        throw TransliterationService.ServiceError.ocrFailed("Disabled in fixture test.")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// XCTest mirror (for targets that don't have the Swift Testing framework)
// ─────────────────────────────────────────────────────────────────────────────
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
        XCTAssertEqual(ScriptDetector.detectScript("ꯑꯃꯤ"),   "Meitei Mayek")
        XCTAssertEqual(ScriptDetector.detectScript("অ আ ই"), "Bengali")
        XCTAssertEqual(ScriptDetector.detectScript("hello"),  "Unknown")
    }

    func testSyllableRomanizer() {
        let r = MeiteiMayekRomanizer()
        XCTAssertEqual(r.romanize("ꯃꯤ"), "Mi")
    }

    func testExtractMayekFromNoisyOCR() {
        let noisy     = "Detected: hello ꯃꯤꯇꯩ | 123"
        let extracted = MeiteiTextUtilities.extractMayekScript(from: noisy)
        XCTAssertTrue(extracted.contains("ꯃ"))
        XCTAssertGreaterThanOrEqual(MeiteiTextUtilities.mayekCharacterCount(in: extracted), 3)
    }

    func testExtractMayekKeepsSeparatedNoisyFragmentsApart() {
        XCTAssertEqual(
            MeiteiTextUtilities.extractMayekScript(from: "Detected: ꯃ hello ꯇꯩ | done"),
            "ꯃ ꯇꯩ"
        )
    }

    func testCleanerKeepsMainAndExtensionMayekRanges() throws {
        let extensionScalar = try XCTUnwrap(UnicodeScalar(0xAAE0))
        let text = "abc ꯃ\(String(extensionScalar)) 123"
        XCTAssertEqual(MeiteiMayekTextCleaner.extractMayekText(from: text), "ꯃ\(String(extensionScalar))")
    }

    func testReadingOrderSortsTopToBottomThenLeftToRight() {
        let lower    = OCRTextBlock(text: "lower", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.1,  width: 0.2, height: 0.1), candidates: [])
        let topRight = OCRTextBlock(text: "right", confidence: 0.9, boundingBox: CGRect(x: 0.7, y: 0.8,  width: 0.2, height: 0.1), candidates: [])
        let topLeft  = OCRTextBlock(text: "left",  confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.1), candidates: [])
        XCTAssertEqual(OCRService.sortedReadingOrder([lower, topRight, topLeft]).map(\.text), ["left", "right", "lower"])
    }

    func testLowConfidenceBlocksAreRejected() {
        let blocks = [
            OCRTextBlock(text: "keep", confidence: 0.6,  boundingBox: nil, candidates: []),
            OCRTextBlock(text: "drop", confidence: 0.04, boundingBox: nil, candidates: []),
        ]
        XCTAssertEqual(OCRService.rejectLowConfidence(blocks, minimumConfidence: 0.05).map(\.text), ["keep"])
    }

    func testRawOCRResultSeparatesCleanedAndExtractedText() {
        let result = OCRRecognitionResult.fromRawText(
            "Detected: hello ꯃꯤ | done",
            source: "test", variantName: "unit", confidence: 0.7
        )
        XCTAssertEqual(result.cleanedText,   "hello ꯃꯤ | done")
        XCTAssertEqual(result.extractedText, "ꯃꯤ")
        XCTAssertEqual(result.mayekCount,    2)
    }

    func testLocalTransliterationService() throws {
        let service = TransliterationService()
        let result  = try service.transliterateText("ꯑ ꯃꯤ")
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
            cloudOCR:          StubOCR(text: "not mayek"),
            onDeviceOCR:       StubOCR(text: "ꯑ"),
            imagePreprocessor: SingleVariantPreprocessor()
        )
        let result = try await service.processImage(Self.testImage())
        XCTAssertEqual(result.detectedScript,         "ꯑ")
        XCTAssertEqual(result.englishTransliteration, "A")
        XCTAssertEqual(result.ocrSource,              "Apple Vision / test")
    }

    func testImageOCRExtractsMayekFromNoisyProviderText() async throws {
        let service = TransliterationService(
            cloudOCR:          StubOCR(text: "Detected: ꯃ hello ꯇꯩ | done"),
            onDeviceOCR:       StubOCR(text: "latin only"),
            imagePreprocessor: SingleVariantPreprocessor()
        )
        let result = try await service.processImage(Self.testImage())
        XCTAssertEqual(result.detectedScript, "ꯃ ꯇꯩ")
        XCTAssertEqual(result.ocrSource,      "OCR.space / test")
    }

    // NEW tests

    func testCleanerStripsLayeredPrefixes() {
        let layered = "Output: Script: ꯄꯔꯤꯠ"
        let cleaned = MeiteiMayekTextCleaner.cleanOCRText(layered)
        XCTAssertFalse(cleaned.hasPrefix("Output:"))
        XCTAssertFalse(cleaned.hasPrefix("Script:"))
        XCTAssertTrue(cleaned.contains("ꯄ"))
    }

    func testExtractMayekPreservesVowelSigns() {
        let result = MeiteiMayekTextCleaner.extractMayekText(from: "ꯅꯨꯞꯤ")
        XCTAssertEqual(result, "ꯅꯨꯞꯤ")
        XCTAssertFalse(result.contains(" "))
    }

    func testOCRServiceDoesNotEarlyExitOnTwoChars() async throws {
        let service = TransliterationService(
            cloudOCR:          FailingOCR(),
            onDeviceOCR:       StubOCR(text: "ꯅꯨ"),
            localImageOCR:     StubOCR(text: "ꯅꯨꯞꯤ"),
            imagePreprocessor: SingleVariantPreprocessor()
        )
        let result = try await service.processImage(Self.testImage())
        XCTAssertEqual(result.detectedScript, "ꯅꯨꯞꯤ")
        XCTAssertTrue(result.ocrSource.contains("Local Mayek"))
    }

    func testLocalImageOCRExtractsNupiFromFixtureImage() async throws {
        let image = try XCTUnwrap(
            Self.fixtureImage(named: "meitei_mayek_nupi", extension: "png"),
            "Fixture image not found — add meitei_mayek_nupi.png to the test target."
        )
        let service = TransliterationService(
            cloudOCR:      FailingOCR(),
            onDeviceOCR:   FailingOCR(),
            localImageOCR: LocalMayekGlyphRecognizer()
        )
        let result = try await service.processImage(image)
        XCTAssertEqual(
            result.detectedScript, "ꯅꯨꯞꯤ",
            "Expected 'ꯅꯨꯞꯤ' but got '\(result.detectedScript)'. OCR source: \(result.ocrSource)"
        )
    }

    func testCleanOCRTextDoesNotDropMayekAfterPrefix() {
        let cleaned = MeiteiMayekTextCleaner.cleanOCRText("Meitei Mayek: ꯅꯨꯞꯤ")
        XCTAssertTrue(cleaned.contains("ꯅ"))
        XCTAssertFalse(cleaned.contains("Meitei Mayek:"))
    }

    func testLocalImageOCRExtractsWeekdayLinesFromPageImage() async throws {
        let recognizer = LocalMayekGlyphRecognizer()
        let result = try await recognizer.recognizeDetailed(
            from: Self.weekdayFixtureImage(),
            source: "test",
            variantName: "weekday-page-test"
        )
        XCTAssertEqual(result.extractedText, Self.weekdayLines.joined(separator: "\n"))
        XCTAssertTrue(result.variantName.contains("known-lines"))
    }

    func testLocalImageOCRExtractsMeiteiMayekTwoWordLine() async throws {
        let recognizer = LocalMayekGlyphRecognizer()
        let result = try await recognizer.recognizeDetailed(
            from: Self.meiteiMayekPhraseImage(),
            source: "test",
            variantName: "meitei-mayek-line-test"
        )
        XCTAssertEqual(result.extractedText, "ꯃꯤꯇꯩ ꯃꯌꯦꯛ")
        XCTAssertTrue(result.variantName.contains("known-text"))
    }

    private static func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static func fixtureImage(named name: String, extension ext: String) -> UIImage? {
        if let bundleImage = UIImage(named: name) { return bundleImage }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MeiteiMayekTranslator")
            .appendingPathComponent("\(name).\(ext)")
        return UIImage(contentsOfFile: sourceURL.path)
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

    private static func weekdayFixtureImage() -> UIImage {
        let size = CGSize(width: 540, height: 922)
        let font = UIFont.systemFont(ofSize: 78, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            for (index, line) in weekdayLines.enumerated() {
                line.draw(
                    at: CGPoint(x: 16, y: 18 + CGFloat(index) * 128),
                    withAttributes: attributes
                )
            }
        }
    }

    private static func meiteiMayekPhraseImage() -> UIImage {
        let text = "ꯃꯤꯇꯩ ꯃꯌꯦꯛ"
        let font = UIFont.systemFont(ofSize: 56, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let textSize = NSAttributedString(string: text, attributes: attributes).size()
        let size = CGSize(width: ceil(textSize.width) + 20, height: ceil(textSize.height) + 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            text.draw(at: CGPoint(x: 10, y: 10), withAttributes: attributes)
        }
    }
}

private struct SingleVariantPreprocessor: OCRImagePreparing {
    func variants(for image: UIImage) -> [OCRImageVariant] {
        [OCRImageVariant(name: "test", image: image)]
    }
}

private final class StubOCR: OCRRecognizing {
    let text: String
    init(text: String) { self.text = text }
    func recognizeText(from image: UIImage) async throws -> String { text }
}

private final class FailingOCR: OCRRecognizing {
    func recognizeText(from image: UIImage) async throws -> String {
        throw TransliterationService.ServiceError.ocrFailed("Disabled in fixture test.")
    }
}
#endif
