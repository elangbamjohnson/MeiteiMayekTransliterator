//
//  OCRDebugLogger.swift
//  MeiteiMayekTranslator
//

import Foundation
import UIKit

enum OCRDebugLogger {
    static var isEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "OCRDebugEnabled")
        #else
        false
        #endif
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[OCR] \(message)")
    }

    static func writeImage(_ image: UIImage, name: String) {
        guard isEnabled,
              let data = image.pngData() else {
            return
        }

        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeiteiMayekOCR", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent("\(safeName).png"))
        } catch {
            print("[OCR] Debug image write failed: \(error.localizedDescription)")
        }
    }
}

