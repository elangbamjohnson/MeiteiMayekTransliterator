//
//  MeiteiMayekRomanizer.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

/// Meitei Mayek → English transliteration using the same rules as
/// https://abhisanoujam.github.io/meitei_mayek/ (inverse of its English→Mayek engine).
nonisolated struct MeiteiMayekRomanizer: MeiteiRomanizing {

    func romanize(_ text: String) -> String {
        MeiteiMayekReferenceReverseTransliterator.transliterate(text)
    }
}
