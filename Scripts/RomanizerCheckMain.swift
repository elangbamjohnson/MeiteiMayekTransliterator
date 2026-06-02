import Foundation

@main
enum RomanizerCheckMain {
    static func main() {
        let r = MeiteiMayekRomanizer()
        let cases: [(String, String)] = [
            ("ꯃꯤ", "Mi"),
            ("ꯑ", "A"),
            ("ꯖꯣꯍꯟꯁꯣꯟ", "Johnson"),
            ("ꯑꯦꯂꯥꯡꯕꯥꯝ", "Elangbam"),
            ("ꯁꯤꯗꯤ ꯑꯩꯁꯨ ꯃꯩꯇꯩ ꯃꯌꯦꯛ ꯏꯕ ꯍꯩꯔꯅꯤ ꯕꯨ ꯫", "Sidi Eisu Meitei Myek Eeb Heirni Bu ."),
        ]

        var failed = 0
        for (input, expected) in cases {
            let out = r.romanize(input)
            let ok = out == expected
            print("\(ok ? "PASS" : "FAIL") -> \"\(out)\" (want \"\(expected)\")")
            if !ok { failed += 1 }
        }

        let roundtrip = [
            "johnson", "elangbam", "kang", "sidi eisu meitei myek eeb heirni bu .",
        ]
        for word in roundtrip {
            let mayek = MeiteiMayekReferenceForwardTransliterator.transliterate(word)
            let back = r.romanize(mayek).lowercased()
            let ok = back == word.lowercased()
            print("\(ok ? "RT PASS" : "RT FAIL") \(word) -> \(mayek) -> \(back)")
            if !ok { failed += 1 }
        }

        exit(failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
