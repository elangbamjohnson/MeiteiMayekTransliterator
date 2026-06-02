//
//  MeiteiTextUtilities.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

enum MeiteiTextUtilities {

    private static let mayekRange: ClosedRange<UInt32> = 0xABC0...0xABFF

    static func isMayekScalar(_ scalar: UnicodeScalar) -> Bool {
        mayekRange.contains(scalar.value)
    }

    static func mayekCharacterCount(in text: String) -> Int {
        text.unicodeScalars.filter(isMayekScalar).count
    }

    /// Fraction of non-whitespace characters in the Meitei Mayek Unicode block (U+ABC0–U+ABFF).
    static func mayekRatio(in text: String) -> Double {
        let scalars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !scalars.isEmpty else { return 0 }
        let mayekCount = scalars.filter { isMayekScalar($0) }.count
        return Double(mayekCount) / Double(scalars.count)
    }

    static func containsMayek(_ text: String) -> Bool {
        mayekCharacterCount(in: text) > 0
    }

    /// True when every non-whitespace character is ASCII letters, digits, or common punctuation.
    static func isEnglishAlphabetTransliteration(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if containsMayek(trimmed) { return false }

        for scalar in trimmed.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2E, 0x2D, 0x27:
                continue
            default:
                return false
            }
        }
        return true
    }

    /// Keeps only Meitei Mayek letters, digits, and line breaks (drops Latin/OCR noise).
    static func extractMayekScript(from text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var segment = ""
            var lastWasMayek = false
            for scalar in line.unicodeScalars {
                if isMayekScalar(scalar) {
                    segment.unicodeScalars.append(scalar)
                    lastWasMayek = true
                } else if lastWasMayek, scalar.properties.isWhitespace {
                    segment.unicodeScalars.append(scalar)
                    lastWasMayek = false
                }
            }
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Strips common OCR/LLM wrappers and normalizes whitespace.
    static func cleanOCRText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for prefix in ["Meitei Mayek:", "Mayek:", "Script:", "Output:"] {
            if let range = value.range(of: prefix, options: .caseInsensitive) {
                value = String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        return value
    }
}
