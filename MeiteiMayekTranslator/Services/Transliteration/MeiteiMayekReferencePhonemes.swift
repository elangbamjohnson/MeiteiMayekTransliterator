//
//  MeiteiMayekReferencePhonemes.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

/// Phoneme data aligned with abhisanoujam/meitei_mayek (`meitei_mayek_transliteration.js`).
nonisolated enum MeiteiMayekReferencePhonemes {

    struct Definition {
        let phoneme: String
        let isVowel: Bool
        let asVowel: String
        let asConsonant: String
        let canBeLonsum: Bool
        let asLonsum: String
        let isNumeric: Bool

        init(
            phoneme: String,
            isVowel: Bool = false,
            asVowel: String = "",
            asConsonant: String = "",
            canBeLonsum: Bool = false,
            asLonsum: String = "",
            isNumeric: Bool = false
        ) {
            self.phoneme = phoneme
            self.isVowel = isVowel
            self.asVowel = asVowel
            self.asConsonant = asConsonant
            self.canBeLonsum = canBeLonsum
            self.asLonsum = asLonsum
            self.isNumeric = isNumeric
        }
    }

    /// Same ordering and rules as the reference JavaScript implementation.
    static let definitions: [Definition] = [
        .init(phoneme: "a", isVowel: true, asVowel: "\u{ABE5}", asConsonant: "ꯑ"),
        .init(phoneme: "aa", isVowel: true, asVowel: "\u{ABE5}", asConsonant: "ꯑ"),
        .init(phoneme: "b", asConsonant: "ꯕ"),
        .init(phoneme: "bh", asConsonant: "ꯚ"),
        .init(phoneme: "c", asConsonant: "ꯆ"),
        .init(phoneme: "ch", asConsonant: "ꯆ"),
        .init(phoneme: "d", asConsonant: "ꯗ"),
        .init(phoneme: "dh", asConsonant: "ꯙ"),
        .init(phoneme: "e", isVowel: true, asVowel: "\u{ABE6}", asConsonant: "ꯑ\u{ABE6}"),
        .init(phoneme: "ee", isVowel: true, asVowel: "\u{ABE4}", asConsonant: "ꯏ"),
        .init(phoneme: "ei", isVowel: true, asVowel: "\u{ABE9}", asConsonant: "ꯑ\u{ABE9}"),
        .init(phoneme: "f", asConsonant: "ꯐ"),
        .init(phoneme: "g", asConsonant: "ꯒ"),
        .init(phoneme: "gh", asConsonant: "ꯘ"),
        .init(phoneme: "h", asConsonant: "ꯍ"),
        .init(phoneme: "i", isVowel: true, asVowel: "\u{ABE4}", asConsonant: "ꯏ", canBeLonsum: true, asLonsum: "ꯢ"),
        .init(phoneme: "j", asConsonant: "ꯖ"),
        .init(phoneme: "jh", asConsonant: "ꯓ"),
        .init(phoneme: "k", asConsonant: "ꯀ", canBeLonsum: true, asLonsum: "ꯛ"),
        .init(phoneme: "kh", asConsonant: "ꯈ"),
        .init(phoneme: "l", asConsonant: "ꯂ", canBeLonsum: true, asLonsum: "ꯜ"),
        .init(phoneme: "m", asConsonant: "ꯃ", canBeLonsum: true, asLonsum: "ꯝ"),
        .init(phoneme: "n", asConsonant: "ꯅ", canBeLonsum: true, asLonsum: "ꯟ"),
        .init(phoneme: "ng", isVowel: true, asVowel: "\u{ABEA}", asConsonant: "ꯉ", canBeLonsum: true, asLonsum: "ꯡ"),
        .init(phoneme: "o", isVowel: true, asVowel: "\u{ABE3}", asConsonant: "ꯑ\u{ABE3}"),
        .init(phoneme: "oo", isVowel: true, asVowel: "\u{ABE8}", asConsonant: "ꯎ"),
        .init(phoneme: "ou", isVowel: true, asVowel: "\u{ABE7}", asConsonant: "ꯑ\u{ABE7}"),
        .init(phoneme: "p", asConsonant: "ꯄ", canBeLonsum: true, asLonsum: "ꯞ"),
        .init(phoneme: "ph", asConsonant: "ꯐ"),
        .init(phoneme: "r", asConsonant: "ꯔ"),
        .init(phoneme: "s", asConsonant: "ꯁ"),
        .init(phoneme: "t", asConsonant: "ꯇ", canBeLonsum: true, asLonsum: "ꯠ"),
        .init(phoneme: "th", asConsonant: "ꯊ"),
        .init(phoneme: "u", isVowel: true, asVowel: "\u{ABE8}", asConsonant: "ꯎ"),
        .init(phoneme: "v", asConsonant: "ꯚ"),
        .init(phoneme: "w", asConsonant: "ꯋ"),
        .init(phoneme: "y", asConsonant: "ꯌ"),
        .init(phoneme: "z", asConsonant: "ꯖ"),
        .init(phoneme: ".", asConsonant: "\u{ABEB}"),
        .init(phoneme: "q", asConsonant: "ꯀ\u{ABED}ꯋ"),
        .init(phoneme: "x", asConsonant: "ꯀ\u{ABED}ꯁ"),
    ]

    static let numbers: [(mayek: Character, digit: String)] = [
        ("꯰", "0"), ("꯱", "1"), ("꯲", "2"), ("꯳", "3"), ("꯴", "4"),
        ("꯵", "5"), ("꯶", "6"), ("꯷", "7"), ("꯸", "8"), ("꯹", "9"),
    ]

    static let apunMayekCombinations: [(String, String)] = [
        ("b", "r"), ("dh", "r"), ("dh", "y"), ("f", "r"), ("g", "r"), ("g", "y"),
        ("j", "r"), ("j", "y"), ("k", "w"), ("k", "y"), ("kh", "r"), ("kh", "w"),
        ("n", "y"), ("p", "r"), ("p", "y"), ("ph", "r"), ("s", "w"), ("s", "y"),
        ("sh", "w"), ("sh", "y"), ("t", "r"), ("th", "r"), ("v", "y"),
    ]

    static let apunMayekCharacter = "\u{ABED}"
}
