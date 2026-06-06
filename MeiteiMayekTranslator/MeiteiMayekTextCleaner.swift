//
//  MeiteiMayekTextCleaner.swift
//  MeiteiMayekTranslator
//

import Foundation

enum MeiteiMayekTextCleaner {
    private static let zeroWidthJoiners: Set<UInt32> = [0x200C, 0x200D]

    static func isMayekScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0xABC0...0xABFF, 0xAAE0...0xAAFF:
            return true
        default:
            return false
        }
    }

    static func cleanOCRText(_ text: String) -> String {
        var value = text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for prefix in ["Meitei Mayek:", "Mayek:", "Script:", "Output:", "Detected:"] {
            if let range = value.range(of: prefix, options: .caseInsensitive) {
                value = String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        value = value.replacingOccurrences(of: "\r", with: "\n")
        value = value.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        return value
    }

    static func extractMayekText(from text: String) -> String {
        var lines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            var output = ""
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
                } else if !output.isEmpty {
                    needsSeparator = true
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

