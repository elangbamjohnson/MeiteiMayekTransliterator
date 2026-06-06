//
//  MeiteiMayekTextCleaner.swift
//  MeiteiMayekTranslator
//
//  Changes from original:
//  FIX-10  cleanOCRText prefix-stripping loop
//          The original for-loop iterated artifactPrefixes once and only stripped
//          the first match it found.  A string like "Output: Script: ꯄꯔꯤꯠ"
//          left "Script:" in place after stripping "Output:".
//          Fixed with a while-loop that restarts from the beginning of
//          artifactPrefixes whenever a prefix is stripped, until no prefix
//          matches in a full pass.

import Foundation

enum MeiteiMayekTextCleaner {

    // MARK: - Private constants

    private static let zeroWidthJoiners: Set<UInt32> = [
        0x200C,  // ZERO WIDTH NON-JOINER
        0x200D,  // ZERO WIDTH JOINER
    ]

    private static let artifactPrefixes = [
        "Meitei Mayek:", "Mayek:", "Script:", "Output:", "Detected:",
    ]

    // MARK: - Public API

    static func isMayekScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0xABC0...0xABFF,   // Meetei Mayek
             0xAAE0...0xAAFF:   // Meetei Mayek Extensions
            return true
        default:
            return false
        }
    }

    static func cleanOCRText(_ text: String) -> String {
        var value = text
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip code-fence markers
        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // FIX-10: restart the prefix scan after every successful strip so that
        // layered prefixes like "Output: Script: ..." are fully unwrapped.
        var stripped = true
        while stripped {
            stripped = false
            for prefix in artifactPrefixes {
                if let range = value.range(of: prefix, options: .caseInsensitive),
                   range.lowerBound == value.startIndex {
                    value = String(value[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    stripped = true
                    break   // restart outer while loop
                }
            }
        }

        // Normalise line endings then collapse intra-line whitespace.
        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        value = value.replacingOccurrences(of: "\r",   with: "\n")
        value = value.replacingOccurrences(of: "[ \\t]+",  with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: " *\\n *",  with: "\n", options: .regularExpression)

        return value
    }

    static func extractMayekText(from text: String) -> String {
        var lines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            var output        = ""
            var needsSeparator = false

            for scalar in line.unicodeScalars {
                if isMayekScalar(scalar) {
                    if needsSeparator, !output.isEmpty {
                        output.append(" ")
                    }
                    output.unicodeScalars.append(scalar)
                    needsSeparator = false

                } else if zeroWidthJoiners.contains(scalar.value) {
                    continue

                } else if CharacterSet.whitespaces.contains(scalar) {
                    needsSeparator = !output.isEmpty

                } else {
                    if !output.isEmpty {
                        needsSeparator = true
                    }
                }
            }

            let trimmed = output.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }

        return lines.joined(separator: "\n")
    }
}
