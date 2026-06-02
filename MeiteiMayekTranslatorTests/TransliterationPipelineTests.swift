#if canImport(Testing)
import Testing

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
}
#elseif canImport(XCTest)
import XCTest
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
}
#endif
