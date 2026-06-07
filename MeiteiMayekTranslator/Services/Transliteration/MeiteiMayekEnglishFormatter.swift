//
//  MeiteiMayekEnglishFormatter.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import Foundation

/// Normalizes raw romanization into readable English spelling (e.g. names and common words).
nonisolated enum MeiteiMayekEnglishFormatter {

    static func format(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +\\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { polishLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func polishLine(_ line: String) -> String {
        var text = line.lowercased()
        text = text.replacingOccurrences(of: "aa", with: "a")
        text = text.replacingOccurrences(of: "ae", with: "e")
        return text
    }

    /// Title-cased display form (e.g. names), after reference-accurate transliteration.
    static func formatForDisplay(_ raw: String) -> String {
        format(raw)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                line.split(separator: " ", omittingEmptySubsequences: false)
                    .map { word -> String in
                        guard let first = word.first else { return String(word) }
                        return String(first).uppercased() + word.dropFirst()
                    }
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}
