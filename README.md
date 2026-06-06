# Meitei Mayek Transliterator

Meitei Mayek Translator is a SwiftUI app for transliterating between Meitei Mayek script and English/Roman spelling. It supports typed text, camera/photo-library image input, OCR-assisted script extraction, result sharing, speech playback, and a lightweight local history of previous transliterations.

The app is focused on transliteration and pronunciation-style Roman output. It does not perform semantic translation from Manipuri/Meitei into English meaning; instead, it converts script forms into readable English letters and can convert Romanized input back into Meitei Mayek.

## What the Project Does

- Scans Meitei Mayek text from camera images or selected photos.
- Runs OCR across normalized/enhanced image variants using Apple Vision, local glyph/cluster recognition, and OCR.space.
- Cleans, ranks, and extracts Meitei Mayek Unicode text from noisy recognition results.
- Converts Meitei Mayek script to English/Roman transliteration using local rule-based logic.
- Converts English/Romanized input to Meitei Mayek using a reference phoneme table.
- Displays OCR source, confidence score, original script, and transliterated output.
- Lets users copy, speak, and share transliteration results.
- Saves recent Meitei Mayek-to-English transliterations in local history using `UserDefaults`.

## Technology Stack

- **Language**: Swift
- **UI framework**: SwiftUI
- **Architecture pattern**: MVVM with service-oriented core logic
- **Concurrency**: Swift async/await for OCR and transliteration workflows
- **Image input**: UIKit `UIImagePickerController` and PhotosUI `PHPickerViewController`
- **OCR**:
  - Apple Vision `VNRecognizeTextRequest` for on-device OCR
  - Local Meitei Mayek glyph/cluster recognition with adaptive image thresholding
  - OCR.space API for cloud OCR fallback
- **Image preparation**: Core Image and Core Graphics preprocessing for normalization, enhancement, binarization, upscaling, and text-region cropping
- **Speech**: AVFoundation `AVSpeechSynthesizer`
- **Persistence**: `UserDefaults` with Codable translation records
- **Testing**: XCTest and Swift Testing-compatible test definitions
- **Project system**: Xcode project (`.xcodeproj`)

## Project Architecture

The app follows a simple MVVM/service architecture:

```text
SwiftUI Views
    |
    v
TranslatorViewModel
    |
    v
TransliterationService
    |
    +-- OCRService
    +-- OCRRecognitionResult / OCRTextBlock
    +-- OCRSpaceService
    +-- VisionOCRService
    +-- LocalMayekGlyphRecognizer
    +-- DefaultOCRImagePreprocessor
    +-- MeiteiMayekRomanizer
    +-- MeiteiMayekReferenceForwardTransliterator
    +-- MeiteiTextUtilities
```

### Main Flow

1. A user types text, captures an image, or selects an image from the photo library.
2. `TranslatorViewModel` receives the user action and starts the correct async workflow.
3. For images, `TransliterationService` creates original, enhanced, and high-contrast image variants.
4. Apple Vision, local glyph/cluster recognition, and OCR.space recognize text from those variants.
5. OCR output is returned as structured results containing raw candidates, cleaned text, confidence, and bounding boxes.
6. The best Meitei Mayek candidate is selected and passed to the transliteration engine.
7. The result is shown in SwiftUI, optionally spoken with AVFoundation, and saved to history.

## Source File Responsibilities

### App Entry and Navigation

| File | Responsibility |
| --- | --- |
| `MeiteiMayekTranslatorApp.swift` | App entry point. Creates the main `WindowGroup` and loads `ContentView`. |
| `ContentView.swift` | Root tab interface. Hosts the Scan and History tabs and injects `TranslatorViewModel` into the environment. |

### UI Layer

| File | Responsibility |
| --- | --- |
| `ScanView.swift` | Main user interface for scanning, selecting photos, typing input, switching transliteration mode, and displaying inline results. Also contains UIKit/PhotosUI picker wrappers and `TextInputView`. |
| `ResultView.swift` | Detailed result screen for a completed Meitei Mayek-to-English transliteration. Shows source image, detected script, confidence, OCR source, English transliteration, copy/share/speak actions, and navigation actions. |
| `HistoryView.swift` | History tab. Displays saved translation records, empty states, delete actions, and clear-all confirmation. |

### View Model

| File | Responsibility |
| --- | --- |
| `TranslatorViewModel.swift` | Main observable state container. Tracks loading/error/result state, selected image, typed input, mode, forward output, history, and speech synthesis. Coordinates calls into `TransliterationService`, persists history, and exposes UI helper values like confidence text/color. |

### Transliteration and OCR Services

| File | Responsibility |
| --- | --- |
| `TransliterationService.swift` | Transliteration-facing service layer. It asks `OCRService` for extracted Meitei Mayek text, validates script content, builds `MMTransliterationResult`, and exposes typed-text transliteration in both directions. |
| `OCRService.swift` | OCR orchestration layer. Runs image variants through Apple Vision, local glyph recognition, and OCR.space; ranks candidates by Meitei Mayek content and confidence; rejects low-confidence blocks; and preserves reading order. |
| `OCRModels.swift` | Shared OCR protocols and structured models such as `OCRRecognitionResult`, `OCRTextBlock`, `OCRTextCandidate`, and `OCRImageVariant`. |
| `OCRImagePreprocessor.swift` | Image preparation pipeline. Normalizes orientation, upscales small text, creates enhanced and binarized variants, crops dark text regions, and avoids lossy compression before local/Vision OCR. |
| `MeiteiMayekTextCleaner.swift` | Meitei Mayek-specific text cleaner. Keeps valid `U+ABC0-U+ABFF` and `U+AAE0-U+AAFF` Unicode scalars, preserves line breaks, strips OCR wrappers/noise, and avoids unsafe character replacement. |
| `OCRDebugLogger.swift` | Debug helper. When `OCRDebugEnabled` is set in `UserDefaults` on a debug build, writes OCR image variants to the temporary directory and logs raw/cleaned OCR output. |
| `OCRSpaceService` in `TransliterationService.swift` | Cloud OCR adapter. Compresses images, submits them to OCR.space, decodes responses, retries on timeout with smaller image data, and reports OCR errors. |
| `VisionOCRService` in `TransliterationService.swift` | On-device OCR adapter using Apple Vision text recognition. It uses accurate mode, disables language correction, passes image orientation, captures top candidates, and sorts text blocks by reading order. |
| `LocalMayekGlyphRecognizer` in `TransliterationService.swift` | Local visual OCR fallback. It adaptively thresholds the image, crops dark glyph clusters, classifies each cluster, and returns Meitei Mayek Unicode text before the romanizer runs. |
| `MeiteiMayekRomanizer.swift` | Small adapter that converts Meitei Mayek text to Roman/English spelling through `MeiteiMayekReferenceReverseTransliterator`. |

### Reference Transliteration Engine

| File | Responsibility |
| --- | --- |
| `MeiteiMayekReferencePhonemes.swift` | Reference phoneme table for vowels, consonants, lonsum letters, digits, and apun mayek combinations. |
| `MeiteiMayekReferenceTransliterator.swift` | Bidirectional rule engine. `MeiteiMayekReferenceForwardTransliterator` converts English/Roman input to Meitei Mayek, while `MeiteiMayekReferenceReverseTransliterator` tokenizes Meitei Mayek and converts it back to Roman output. |
| `MeiteiMayekEnglishFormatter.swift` | Normalizes raw romanization into display-friendly English spelling, including whitespace cleanup, simple spelling normalization, and title-casing for display output. |
| `MeiteiTextUtilities.swift` | Text helper methods for Meitei Mayek Unicode detection, Mayek character counting, Mayek ratio scoring, OCR cleanup, Mayek-only extraction, and English transliteration validation. |
| `ScriptDetector.swift` | Detects whether text contains Meitei Mayek, Bengali, or unknown script based on Unicode scalar ranges. |

### Models and Compatibility

| File | Responsibility |
| --- | --- |
| `TransliterationResult.swift` | Defines `MMTransliterationResult`, the main result model used by the UI and service layer. Includes script text, English transliteration, confidence, OCR source, engine name, timestamp, and UI convenience accessors. |
| `TranslationRecord.swift` | Defines the Codable history model saved to `UserDefaults`. Also includes compatibility aliases and backward-compatible decoding for older result field names. |
| `TransliterationResult+Compat.swift` | Deprecated compatibility placeholder. Compatibility has moved into the core model. |

### Tests and Scripts

| File | Responsibility |
| --- | --- |
| `MeiteiMayekTranslatorTests/TransliterationPipelineTests.swift` | Tests script detection, Mayek ratio calculation, OCR-noise extraction, local transliteration service behavior, and English transliteration validation. |
| `MeiteiMayekTranslatorTests/RomanizerTests.swift` | Tests basic romanizer behavior, digits, whitespace, zero-width joiners, names, demo sentences, and round-trip behavior against the reference forward transliterator. |
| `MeiteiMayekTranslatorTests/MeiteiMayekTranslatorTests.swift` | Default XCTest placeholder/performance test file. |
| `MeiteiMayekTranslatorUITests/*` | Default UI launch and launch performance test files. |
| `Scripts/RomanizerCheckMain.swift` | Command-style romanizer check program with expected examples and round-trip checks. |
| `Scripts/MeiteiRomanizingStub.swift` | Minimal protocol stub for script/check contexts. |

## Data Models

### `MMTransliterationResult`

Represents a transliteration result shown in the UI:

- `detectedScript`: Meitei Mayek text used as input.
- `englishTransliteration`: Roman/English spelling output.
- `confidence`: Confidence score derived from OCR source and Mayek-character ratio.
- `ocrSource`: Source of recognized text, such as `OCR.space`, `Apple Vision`, or `typed`.
- `transliterationEngine`: Current engine label, usually `On-device`.
- `createdAt`: Result creation timestamp.

### `TranslationRecord`

Persisted history record created from a result. It stores the original script, English transliteration, confidence, OCR source, engine name, and creation date. It also decodes several legacy field names so older stored history can still load.

## OCR and Transliteration Pipeline

### Image Input

For camera or gallery images:

1. The image is passed to `TranslatorViewModel.translateImage(_:)`.
2. `TransliterationService.processImage(_:)` creates multiple OCR-ready image variants.
3. Apple Vision, local glyph/cluster recognition, and OCR.space each try to recognize text from those variants.
4. Vision results are sorted by normalized bounding boxes so lines read top-to-bottom and left-to-right.
5. Each OCR attempt is converted into `OCRRecognitionResult`, with raw candidates, cleaned text, extracted Meitei Mayek text, confidence, and optional bounding boxes.
6. Text cleanup keeps only Meitei Mayek `U+ABC0-U+ABFF` and extension `U+AAE0-U+AAFF` scalars plus safe whitespace; it does not blindly substitute look-alike characters.
7. Attempts are ranked by Meitei Mayek character count, Mayek ratio, confidence, and text length.
8. The best extracted script is transliterated only after OCR has returned clean Meitei Mayek text.

### OCR Debugging

In a debug build, enable OCR debug output with:

```swift
UserDefaults.standard.set(true, forKey: "OCRDebugEnabled")
```

When enabled, `OCRDebugLogger` writes original and preprocessed images under the app's temporary `MeiteiMayekOCR` directory and logs raw OCR text, cleaned OCR text, extracted script, source, variant, and confidence. Use this when comparing why a scan fails: inspect the original image, enhanced variants, binarized variants, cropped text region, raw candidates, and final cleaned output.

### Typed Input

For typed text:

- **Mayek to English**: `transliterateText(_:)` validates Meitei Mayek content and calls `MeiteiMayekRomanizer`.
- **English to Mayek**: `transliterateEnglishToMayek(_:)` calls `MeiteiMayekReferenceForwardTransliterator`.

## Configuration Notes

- The app target currently includes a camera usage description in generated Info.plist settings.
- The project is configured as an Xcode project with app, unit test, and UI test targets.
- The current project file shows Swift 5 settings and an iOS deployment target of 26.5.
- `OCRSpaceService` currently contains an OCR.space API key directly in source. For production use, move this key to a safer configuration mechanism instead of committing it in code.

## Project Structure

```text
MeiteiMayekTranslator/
├── MeiteiMayekTranslator/
│   ├── MeiteiMayekTranslatorApp.swift
│   ├── ContentView.swift
│   ├── ScanView.swift
│   ├── ResultView.swift
│   ├── HistoryView.swift
│   ├── TranslatorViewModel.swift
│   ├── TransliterationService.swift
│   ├── OCRService.swift
│   ├── OCRModels.swift
│   ├── OCRImagePreprocessor.swift
│   ├── OCRDebugLogger.swift
│   ├── MeiteiMayekTextCleaner.swift
│   ├── TransliterationResult.swift
│   ├── TranslationRecord.swift
│   ├── MeiteiMayekRomanizer.swift
│   ├── MeiteiMayekReferencePhonemes.swift
│   ├── MeiteiMayekReferenceTransliterator.swift
│   ├── MeiteiMayekEnglishFormatter.swift
│   ├── MeiteiTextUtilities.swift
│   ├── ScriptDetector.swift
│   └── Assets.xcassets/
├── MeiteiMayekTranslatorTests/
├── MeiteiMayekTranslatorUITests/
├── Scripts/
├── MeiteiMayekTranslator.xcodeproj/
└── README.md
```

## Running the App

1. Open `MeiteiMayekTranslator.xcodeproj` in Xcode.
2. Select the `MeiteiMayekTranslator` scheme.
3. Choose an iOS simulator or a physical device.
4. Build and run.

Camera scanning requires a device or simulator environment that supports camera input. Photo-library selection and typed transliteration can be tested without camera hardware.

## Running Tests

From Xcode, select the test target or press `Command+U`.

From the command line, use an available simulator destination, for example:

```sh
xcodebuild test \
  -project MeiteiMayekTranslator.xcodeproj \
  -scheme MeiteiMayekTranslator \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

If the named simulator is not installed, run `xcrun simctl list devices` and choose an available simulator name.

## Current Limitations

- OCR quality depends heavily on image clarity, crop tightness, lighting, and OCR provider behavior.
- The app performs transliteration, not meaning-based translation.
- OCR.space requires network access, while Apple Vision OCR runs on device.
- Apple Vision does not currently provide reliable native Meitei Mayek OCR, so it is treated as a baseline provider and diagnostic source rather than the only source of truth.
- Local glyph recognition is tuned for high-contrast Meitei Mayek scans and bundled sample clusters. A broader production OCR engine should use a labeled Meitei Mayek image dataset and a character-level Core ML classifier.
- History is intentionally lightweight and stored locally in `UserDefaults`.
- Some UI test files are still default generated placeholders.

## Production OCR Roadmap

For broad handwriting, fonts, and camera conditions, the next production step is a trained OCR model:

1. Collect images per Meitei Mayek character and common clusters across fonts, sizes, lighting, blur, and background conditions.
2. Label each crop with the exact Unicode scalar or cluster.
3. Train a small character classifier using Create ML, PyTorch, or TensorFlow, then export to Core ML.
4. Keep the current segmentation pipeline as the detector: normalize, threshold, crop glyph clusters, classify each crop, then join recognized characters in reading order.
5. Continue using Apple Vision and OCR.space as fallback/diagnostic providers, not as the primary Meitei Mayek engine.

## Purpose

This project helps users read, learn, preserve, and work with Meitei Mayek by making script conversion more accessible through typed input, camera/photo OCR, and local rule-based transliteration.
