//
//  ScriptDetector.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

struct ScriptDetector {
    static func detectScript(_ text: String) -> String {
        // Meitei Mayek range U+ABC0–U+ABFF
        if text.unicodeScalars.contains(where: { $0.value >= 0xABC0 && $0.value <= 0xABFF }) {
            return "Meitei Mayek"
        }
        // Bengali range U+0980–U+09FF (sometimes used historically)
        if text.unicodeScalars.contains(where: { $0.value >= 0x0980 && $0.value <= 0x09FF }) {
            return "Bengali"
        }
        return "Unknown"
    }
}
