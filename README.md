# Meitei Mayek Translator

Meitei Mayek Translator is a SwiftUI app for transliterating between Meitei Mayek script and English/Roman spelling. It supports typed text, camera/photo-library image input, OCR-assisted script extraction, result sharing, speech playback, and a lightweight local history of previous transliterations.

The app is focused on transliteration and pronunciation-style Roman output. It does not perform semantic translation from Manipuri/Meitei into English meaning; instead, it converts script forms into readable English letters and can convert Romanized input back into Meitei Mayek.

## What the Project Does

- Scans Meitei Mayek text from camera images or selected photos.
- Runs OCR using OCR.space first and Apple Vision as an on-device OCR fallback.
- Cleans OCR output and extracts Meitei Mayek Unicode text from noisy recognition results.
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
  - OCR.space API for cloud OCR
  - Apple Vision `VNRecognizeTextRequest` for on-device OCR fallback
- **Image processing**: Core Image filters through `CIImage`, `CIContext`, and built-in Core Image filters
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
    +-- OCRSpaceService
    +-- VisionOCRService
    +-- MeiteiMayekRomanizer
    +-- MeiteiMayekReferenceForwardTransliterator
    +-- MeiteiTextUtilities
```

### Main Flow

1. A user types text, captures an image, or selects an image from the photo library.
2. `TranslatorViewModel` receives the user action and starts the correct async workflow.
3. For images, `TransliterationService` asks OCR.space and Apple Vision for text recognition.
4. OCR output is cleaned and ranked by how much Meitei Mayek script it contains.
5. The selected text is transliterated locally using the rule-based romanizer.
6. The result is shown in SwiftUI, optionally spoken with AVFoundation, and saved to history.

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
| `TransliterationService.swift` | Core service layer. Defines OCR and romanizer protocols, runs image OCR, ranks OCR attempts, validates script content, builds `MMTransliterationResult`, and exposes typed-text transliteration in both directions. |
| `OCRSpaceService` in `TransliterationService.swift` | Cloud OCR adapter. Compresses images, submits them to OCR.space, decodes responses, retries on timeout with smaller image data, and reports OCR errors. |
| `VisionOCRService` in `TransliterationService.swift` | On-device OCR adapter using Apple Vision text recognition. |
| `MeiteiMayekRomanizer.swift` | Small adapter that converts Meitei Mayek text to Roman/English spelling through `MeiteiMayekReferenceReverseTransliterator`. |
| `MeiteiImageProcessor.swift` | Core Image preprocessing utility. Applies grayscale, contrast/brightness, exposure, and sharpening filters to improve OCR readability. |

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
2. `TransliterationService.processImage(_:)` asks OCR.space and Apple Vision to recognize text.
3. Each OCR attempt is cleaned using `MeiteiTextUtilities.cleanOCRText(_:)`.
4. Meitei Mayek script is extracted using `extractMayekScript(from:)`.
5. Attempts are ranked by Meitei Mayek character count.
6. The best result is transliterated if it contains enough Meitei Mayek characters.

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
│   ├── TransliterationResult.swift
│   ├── TranslationRecord.swift
│   ├── MeiteiMayekRomanizer.swift
│   ├── MeiteiMayekReferencePhonemes.swift
│   ├── MeiteiMayekReferenceTransliterator.swift
│   ├── MeiteiMayekEnglishFormatter.swift
│   ├── MeiteiTextUtilities.swift
│   ├── ScriptDetector.swift
│   ├── MeiteiImageProcessor.swift
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
- History is intentionally lightweight and stored locally in `UserDefaults`.
- Some UI test files are still default generated placeholders.

## Purpose

This project helps users read, learn, preserve, and work with Meitei Mayek by making script conversion more accessible through typed input, camera/photo OCR, and local rule-based transliteration.
