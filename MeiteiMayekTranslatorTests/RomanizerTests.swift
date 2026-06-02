#if canImport(Testing)
import Testing

@Suite("Romanizer basic behavior")
struct RomanizerTests {

    @Test
    func basicLetters() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯑ") == "A")
        #expect(r.romanize("ꯇ") == "T")
        #expect(r.romanize("ꯃ") == "M")
        #expect(r.romanize("ꯤ") == "I")
    }

    @Test
    func digits() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("꯰꯱꯲꯳꯴") == "01234")
        #expect(r.romanize("꯵꯶꯷꯸꯹") == "56789")
    }

    @Test
    func whitespaceAndNewlines() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯑ ꯃ\nꯤ") == "A M\nI")
    }

    @Test
    func zeroWidthJoinersIgnored() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯑ\u{200C}ꯤ\u{200D}") == "Ai")
    }

    @Test
    func consonantVowelClusterBecomesEnglishLetters() async throws {
        let r = MeiteiMayekRomanizer()
        let out = r.romanize("ꯃꯤ")
        #expect(out == "Mi")
        #expect(MeiteiTextUtilities.isEnglishAlphabetTransliteration(out))
        #expect(!MeiteiTextUtilities.containsMayek(out))
    }

    @Test
    func personalNameJohnson() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯖꯣꯍꯟꯁꯣꯟ") == "Johnson")
    }

    @Test
    func surnameElangbam() async throws {
        let r = MeiteiMayekRomanizer()
        #expect(r.romanize("ꯑꯦꯂꯥꯡꯕꯥꯝ") == "Elangbam")
    }

    @Test
    func referenceToolDemoSentence() async throws {
        let r = MeiteiMayekRomanizer()
        let mayek = "ꯁꯤꯗꯤ ꯑꯩꯁꯨ ꯃꯩꯇꯩ ꯃꯌꯦꯛ ꯏꯕ ꯍꯩꯔꯅꯤ ꯕꯨ ꯫"
        #expect(r.romanize(mayek) == "Sidi Eisu Meitei Myek Eeb Heirni Bu .")
    }

    @Test
    func roundtripMatchesReferenceForward() async throws {
        let english = "johnson"
        let mayek = MeiteiMayekReferenceForwardTransliterator.transliterate(english)
        #expect(MeiteiMayekRomanizer().romanize(mayek).lowercased() == english)
    }
}
#elseif canImport(XCTest)
import XCTest
@testable import MeiteiMayekTranslator
final class RomanizerTests: XCTestCase {

    func testBasicLetters() {
        let r = MeiteiMayekRomanizer()
        XCTAssertEqual(r.romanize("ꯑ"), "A")
        XCTAssertEqual(r.romanize("ꯇ"), "T")
        XCTAssertEqual(r.romanize("ꯃ"), "M")
        XCTAssertEqual(r.romanize("ꯤ"), "I")
    }

    func testDigits() {
        let r = MeiteiMayekRomanizer()
        XCTAssertEqual(r.romanize("꯰꯱꯲꯳꯴"), "01234")
        XCTAssertEqual(r.romanize("꯵꯶꯷꯸꯹"), "56789")
    }

    func testWhitespaceAndNewlines() {
        let r = MeiteiMayekRomanizer()
        XCTAssertEqual(r.romanize("ꯑ ꯃ\nꯤ"), "A M\nI")
    }

    func testZeroWidthJoinersIgnored() {
        let r = MeiteiMayekRomanizer()
        XCTAssertEqual(r.romanize("ꯑ\u{200C}ꯤ\u{200D}"), "Ai")
    }

    func testConsonantVowelClusterBecomesEnglishLetters() {
        let r = MeiteiMayekRomanizer()
        let out = r.romanize("ꯃꯤ")
        XCTAssertEqual(out, "Mi")
        XCTAssertTrue(MeiteiTextUtilities.isEnglishAlphabetTransliteration(out))
        XCTAssertFalse(MeiteiTextUtilities.containsMayek(out))
    }

    func testPersonalNameJohnson() {
        XCTAssertEqual(MeiteiMayekRomanizer().romanize("ꯖꯣꯍꯟꯁꯣꯟ"), "Johnson")
    }

    func testSurnameElangbam() {
        XCTAssertEqual(MeiteiMayekRomanizer().romanize("ꯑꯦꯂꯥꯡꯕꯥꯝ"), "Elangbam")
    }

    func testReferenceToolDemoSentence() {
        let mayek = "ꯁꯤꯗꯤ ꯑꯩꯁꯨ ꯃꯩꯇꯩ ꯃꯌꯦꯛ ꯏꯕ ꯍꯩꯔꯅꯤ ꯕꯨ ꯫"
        XCTAssertEqual(MeiteiMayekRomanizer().romanize(mayek), "Sidi Eisu Meitei Myek Eeb Heirni Bu .")
    }

    func testRoundtripMatchesReferenceForward() {
        let english = "johnson"
        let mayek = MeiteiMayekReferenceForwardTransliterator.transliterate(english)
        XCTAssertEqual(MeiteiMayekRomanizer().romanize(mayek).lowercased(), english)
    }
}
#endif

