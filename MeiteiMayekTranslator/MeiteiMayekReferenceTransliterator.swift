//
//  MeiteiMayekReferenceTransliterator.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

// MARK: - Forward (English → Mayek), matches abhisanoujam/meitei_mayek

enum MeiteiMayekReferenceForwardTransliterator {

    private enum CVCState { case none, consonant, vowel }
    private enum OutputMode { case vowel, consonant, lonsum }

    private struct RuntimePhoneme {
        let phoneme: String
        let isVowel: Bool
        let asVowel: String
        let asConsonant: String
        let canBeLonsum: Bool
        let asLonsum: String
        let isNumeric: Bool
        let isUnknown: Bool

        init(definition: MeiteiMayekReferencePhonemes.Definition) {
            phoneme = definition.phoneme
            isVowel = definition.isVowel
            asVowel = definition.asVowel
            asConsonant = definition.asConsonant
            canBeLonsum = definition.canBeLonsum
            asLonsum = definition.asLonsum
            isNumeric = definition.isNumeric
            isUnknown = false
        }

        init(unknown: String) {
            phoneme = unknown
            isVowel = false
            asVowel = ""
            asConsonant = unknown
            canBeLonsum = false
            asLonsum = ""
            isNumeric = false
            isUnknown = true
        }
    }

    private struct PhonemeOutput {
        let phoneme: RuntimePhoneme
        var outputMode: OutputMode

        func rendered() -> String {
            switch outputMode {
            case .vowel: return phoneme.asVowel
            case .consonant: return phoneme.asConsonant
            case .lonsum: return phoneme.asLonsum
            }
        }
    }

    private static let emptyPhoneme = RuntimePhoneme(definition: .init(phoneme: ""))
    private static let apunMayekPhoneme = RuntimePhoneme(
        definition: .init(phoneme: MeiteiMayekReferencePhonemes.apunMayekCharacter, asConsonant: MeiteiMayekReferencePhonemes.apunMayekCharacter)
    )

    private static let phonemeMap: [String: RuntimePhoneme] = {
        var map: [String: RuntimePhoneme] = [:]
        for definition in MeiteiMayekReferencePhonemes.definitions {
            map[definition.phoneme] = RuntimePhoneme(definition: definition)
        }
        for entry in MeiteiMayekReferencePhonemes.numbers {
            map[entry.digit] = RuntimePhoneme(
                definition: .init(phoneme: entry.digit, asConsonant: String(entry.mayek), isNumeric: true)
            )
        }
        return map
    }()

    private static let apunMayekPairs: Set<String> = {
        Set(MeiteiMayekReferencePhonemes.apunMayekCombinations.map { "\($0.0)-\($0.1)" })
    }()

    static func transliterate(_ text: String) -> String {
        let lowered = text.lowercased()
        var phonemes: [RuntimePhoneme] = []
        var previous = emptyPhoneme

        for character in lowered {
            let next = String(character)
            let isAlphaNumeric = (character >= "a" && character <= "z")
                || (character >= "0" && character <= "9")
                || character == "."

            if !isAlphaNumeric {
                phonemes.append(RuntimePhoneme(unknown: next))
                previous = phonemes.last!
                continue
            }

            if let digraph = phonemeMap[previous.phoneme + next] {
                if !phonemes.isEmpty { phonemes.removeLast() }
                phonemes.append(digraph)
                previous = digraph
            } else if let mapped = phonemeMap[next] {
                phonemes.append(mapped)
                previous = mapped
            } else {
                let unknown = RuntimePhoneme(unknown: next)
                phonemes.append(unknown)
                previous = unknown
            }
        }

        return convertToMayek(phonemes)
    }

    private static func convertToMayek(_ phonemes: [RuntimePhoneme]) -> String {
        var output: [PhonemeOutput] = []
        var state = CVCState.none
        var previous = PhonemeOutput(phoneme: emptyPhoneme, outputMode: .consonant)

        for phoneme in phonemes {
            if phoneme.isUnknown {
                output.append(PhonemeOutput(phoneme: phoneme, outputMode: .consonant))
                state = .none
                continue
            }

            switch state {
            case .none:
                let next = PhonemeOutput(phoneme: phoneme, outputMode: .consonant)
                output.append(next)
                state = phoneme.isNumeric ? .none : (phoneme.isVowel ? .vowel : .consonant)
                previous = next

            case .consonant:
                if phoneme.isVowel {
                    let next = PhonemeOutput(phoneme: phoneme, outputMode: .vowel)
                    output.append(next)
                    state = .vowel
                    if previous.outputMode == .lonsum {
                        previous.outputMode = .consonant
                    }
                    previous = next
                } else if phoneme.phoneme == "ng" {
                    let next = PhonemeOutput(phoneme: phoneme, outputMode: .vowel)
                    output.append(next)
                    state = .vowel
                    previous = next
                } else {
                    if apunMayekPairs.contains("\(previous.phoneme.phoneme)-\(phoneme.phoneme)") {
                        output.append(PhonemeOutput(phoneme: apunMayekPhoneme, outputMode: .consonant))
                    }
                    let mode: OutputMode = phoneme.canBeLonsum && previous.outputMode != .lonsum ? .lonsum : .consonant
                    let next = PhonemeOutput(phoneme: phoneme, outputMode: mode)
                    output.append(next)
                    state = .consonant
                    previous = next
                }

            case .vowel:
                if phoneme.isVowel {
                    let next = PhonemeOutput(phoneme: phoneme, outputMode: .consonant)
                    output.append(next)
                    state = .consonant
                    previous = next
                } else {
                    let mode: OutputMode = phoneme.canBeLonsum ? .lonsum : .consonant
                    let next = PhonemeOutput(phoneme: phoneme, outputMode: mode)
                    output.append(next)
                    state = .consonant
                    previous = next
                }
            }
        }

        return output.map { $0.rendered() }.joined()
    }
}

// MARK: - Reverse (Mayek → English), inverse of reference forward rules

enum MeiteiMayekReferenceReverseTransliterator {

    private struct MayekToken {
        let phoneme: String
        let isApunMayek: Bool
    }

    private struct Fragment {
        let mayek: String
        let phoneme: String
        let isApunMayek: Bool
    }

    /// Longest-match fragments derived from the reference phoneme table (last mapping wins on duplicates).
    private static let fragments: [Fragment] = {
        var mayekToPhoneme: [String: (phoneme: String, isApun: Bool)] = [:]

        func register(_ mayek: String, phoneme: String, isApun: Bool = false) {
            guard !mayek.isEmpty else { return }
            mayekToPhoneme[mayek] = (phoneme, isApun)
        }

        for definition in MeiteiMayekReferencePhonemes.definitions {
            register(definition.asConsonant, phoneme: definition.phoneme)
            register(definition.asVowel, phoneme: definition.phoneme)
            register(definition.asLonsum, phoneme: definition.phoneme)
        }

        for entry in MeiteiMayekReferencePhonemes.numbers {
            register(String(entry.mayek), phoneme: entry.digit)
        }

        register(MeiteiMayekReferencePhonemes.apunMayekCharacter, phoneme: "", isApun: true)

        // Prefer common decodings when multiple phonemes share one Mayek letter.
        register("ꯚ", phoneme: "v")
        register("ꯆ", phoneme: "ch")
        register("ꯐ", phoneme: "ph")
        register("ꯖ", phoneme: "j")
        register("ꯏ", phoneme: "ee")
        register("ꯎ", phoneme: "oo")
        register("ꯥꯏ", phoneme: "ai")

        return mayekToPhoneme
            .map { Fragment(mayek: $0.key, phoneme: $0.value.phoneme, isApunMayek: $0.value.isApun) }
            .sorted { $0.mayek.count > $1.mayek.count }
    }()

    static func transliterate(_ text: String) -> String {
        let tokens = tokenize(text)
        let raw = tokens
            .filter { !$0.isApunMayek }
            .map(\.phoneme)
            .joined()

        return MeiteiMayekEnglishFormatter.formatForDisplay(raw)
    }

    private static func tokenize(_ text: String) -> [MayekToken] {
        let scalars = Array(text.unicodeScalars)
        var tokens: [MayekToken] = []
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                tokens.append(MayekToken(phoneme: String(scalar), isApunMayek: false))
                index += 1
                continue
            }

            if let fragment = fragments.first(where: { matchesFragment(scalars, at: index, fragment: $0) }) {
                tokens.append(MayekToken(phoneme: fragment.phoneme, isApunMayek: fragment.isApunMayek))
                index += fragment.mayek.unicodeScalars.count
                continue
            }

            tokens.append(MayekToken(phoneme: String(scalar), isApunMayek: false))
            index += 1
        }

        return tokens
    }

    private static func matchesFragment(_ scalars: [UnicodeScalar], at index: Int, fragment: Fragment) -> Bool {
        let fragmentScalars = Array(fragment.mayek.unicodeScalars)
        guard index + fragmentScalars.count <= scalars.count else { return false }
        for offset in 0..<fragmentScalars.count where scalars[index + offset] != fragmentScalars[offset] {
            return false
        }
        return !fragmentScalars.isEmpty
    }
}

