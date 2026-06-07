//
//  ScanView.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct ScanView: View {
    @EnvironmentObject var viewModel: TranslatorViewModel

    @State private var showImagePicker = false
    @State private var showPhotoPicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    @State private var activeImageImportSource: ImageImportSource?

    private var isImageImporting: Bool {
        activeImageImportSource != nil
    }

    private var isImageBusy: Bool {
        isImageImporting || viewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed Header (Expert UX: Stays fixed to top with glassmorphism effect)
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("ꯃꯤꯇꯩ ꯃꯌꯦꯛ")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.purple)
                        Text(viewModel.mode == .mayekToEnglish ? "Meitei Mayek → English transliteration" : "English → Meitei Mayek")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Mode", selection: $viewModel.mode) {
                        Text("Mayek → English").tag(TranslatorViewModel.TransliterationMode.mayekToEnglish)
                        Text("English → Mayek").tag(TranslatorViewModel.TransliterationMode.englishToMayek)
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(.ultraThinMaterial)
                .zIndex(1) // Ensure header stays on top of scroll content
                
                Divider()

                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Reference Link (Moved to top of scroll area to keep header compact)
                        Link("Same spelling rules as abhisanoujam/meitei_mayek",
                             destination: URL(string: "https://abhisanoujam.github.io/meitei_mayek/")!)
                            .font(.caption2)
                            .padding(.top, 12)

                        // Camera capture card
                        Button {
                            guard UIImagePickerController.isSourceTypeAvailable(.camera), !isImageBusy else { return }
                            imagePickerSource = .camera
                            activeImageImportSource = .camera
                            showImagePicker = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(.systemGray6))
                                    .frame(height: 180)
                                    .opacity(UIImagePickerController.isSourceTypeAvailable(.camera) && !isImageBusy ? 1 : 0.5)

                                VStack(spacing: 12) {
                                    if activeImageImportSource == .camera {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                    } else {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 44))
                                            .foregroundStyle(.purple)
                                    }
                                    Text(activeImageImportSource == .camera ? "Loading captured image…" : "Tap to scan script")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(UIImagePickerController.isSourceTypeAvailable(.camera) ? "Point camera at Meitei Mayek text" : "Camera not available on this device")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("cameraImportButton")
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || isImageBusy)
                        .padding(.horizontal)

                        // Secondary options
                        HStack(spacing: 12) {
                            // Gallery picker
                            Button {
                                guard !isImageBusy else { return }
                                activeImageImportSource = .gallery
                                showPhotoPicker = true
                            } label: {
                                Label {
                                    Text(activeImageImportSource == .gallery ? "Loading photo…" : "Gallery")
                                } icon: {
                                    if activeImageImportSource == .gallery {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "photo.on.rectangle")
                                    }
                                }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .foregroundStyle(isImageBusy ? .secondary : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(isImageBusy)
                        }
                        .accessibilityIdentifier("galleryImportButton")
                        .padding(.horizontal)

                        // Inline type-to-transliterate section
                        VStack(spacing: 12) {
                            Text(viewModel.mode == .mayekToEnglish ? "Type Meitei Mayek text to transliterate" : "Type English text to convert to Meitei Mayek")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)

                            TextEditor(text: viewModel.mode == .mayekToEnglish ? $viewModel.mayekTypedText : $viewModel.englishTypedText)
                                .font(.system(size: 20))
                                .frame(height: 120)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal)

                            Button {
                                Task { await viewModel.translateTypedText() }
                            } label: {
                                Text(viewModel.isLoading ? "Transliterating…" : "Transliterate")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.purple)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal)
                            }
                            .disabled(viewModel.isLoading || (viewModel.mode == .mayekToEnglish ? viewModel.mayekTypedText : viewModel.englishTypedText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        // Selected image preview
                        if let image = viewModel.selectedImage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected image")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)

                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal)
                            }
                            .accessibilityIdentifier("selectedImagePreview")
                        }

                        // Error message
                        if let error = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }

                        // Loading state
                        if viewModel.isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Reading script and transliterating on-device…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .accessibilityIdentifier("translationLoadingView")
                        }

                        // Inline result area
                        if viewModel.mode == .mayekToEnglish {
                            if let result = viewModel.currentResult {
                                VStack(spacing: 20) {
                                    // Original script card
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Detected Meitei Mayek", systemImage: "text.viewfinder")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(result.detectedScript)
                                            .font(.system(size: 24))
                                            .lineSpacing(6)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        HStack {
                                            // Confidence bar
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color(.systemGray5))
                                                        .frame(height: 6)
                                                    Capsule()
                                                        .fill(confidenceColor)
                                                        .frame(width: geo.size.width * result.confidence, height: 6)
                                                }
                                            }
                                            .frame(height: 6)

                                            Text(viewModel.confidencePercent)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 40, alignment: .trailing)

                                            Button {
                                                viewModel.speak(result.romanizedText)
                                            } label: {
                                                Image(systemName: "speaker.wave.2.circle.fill")
                                                    .foregroundStyle(.purple)
                                            }

                                            Button {
                                                UIPasteboard.general.string = result.detectedScript
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal)

                                    // Arrow
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.purple)

                                    // Transliteration card
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Transliteration (English)", systemImage: "character.book.closed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(result.romanizedText)
                                            .font(.title3)
                                            .lineSpacing(6)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        HStack {
                                            Spacer()
                                            Button {
                                                viewModel.speak(result.romanizedText)
                                            } label: {
                                                Image(systemName: "speaker.wave.2.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.purple)
                                            }
                                        }

                                    }
                                    .padding()
                                    .background(Color.purple.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                }
                                .padding(.bottom, 32)
                            }
                        } else {
                            if let output = viewModel.forwardOutput {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Meitei Mayek", systemImage: "character")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(output)
                                        .font(.system(size: 28))
                                        .lineSpacing(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack {
                                        Button {
                                            viewModel.speak(viewModel.englishTypedText)
                                        } label: {
                                            Label("Listen", systemImage: "speaker.wave.2.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.purple)
                                        }

                                        Spacer()
                                        Button {
                                            UIPasteboard.general.string = output
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                                .font(.caption)
                                                .foregroundStyle(.purple)
                                        }
                                    }

                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                                .padding(.bottom, 32)
                            }
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(
                    sourceType: imagePickerSource,
                    onImportFinished: {
                        activeImageImportSource = nil
                    },
                    onImagePicked: { image in
                        processPickedImage(image)
                    }
                )
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerView(
                    onImportFinished: {
                        activeImageImportSource = nil
                    }, onImagePicked: { pickedImage in
                        processPickedGalleryImage(pickedImage)
                    }
                )
            }
            .safeAreaInset(edge: .bottom) {
                if let activeImageImportSource {
                    ImageImportBanner(message: activeImageImportSource.loadingMessage)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeImageImportSource)
    }
    
    private var confidenceColor: Color {
        guard let result = viewModel.currentResult else { return .gray }
        switch result.confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default:     return .red
        }
    }

    private func processPickedImage(_ image: UIImage) {
        Task {
            await viewModel.prepareImageForTranslation(image)
            activeImageImportSource = nil
            await Task.yield()
            try? await Task.sleep(nanoseconds: 120_000_000)
            await viewModel.transliteratePreparedImage(image)
        }
    }

    private func processPickedGalleryImage(_ pickedImage: PickedGalleryImage) {
        Task {
            viewModel.prepareImagePreview(pickedImage.previewImage)
            activeImageImportSource = nil
            await Task.yield()
            try? await Task.sleep(nanoseconds: 120_000_000)
            await viewModel.transliteratePreparedImage(
                at: pickedImage.originalImageURL,
                cleanupAfterProcessing: true
            )
        }
    }
}

// MARK: - UIImagePickerController wrapper

private enum ImageImportSource: Equatable {
    case camera
    case gallery

    var loadingMessage: String {
        switch self {
        case .camera:
            return "Loading captured image…"
        case .gallery:
            return "Loading selected image…"
        }
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImportFinished: () -> Void
    var onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImportFinished: onImportFinished, onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onImportFinished: () -> Void
        var onImagePicked: (UIImage) -> Void

        init(onImportFinished: @escaping () -> Void, onImagePicked: @escaping (UIImage) -> Void) {
            self.onImportFinished = onImportFinished
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                picker.dismiss(animated: true) {
                    self.onImagePicked(image)
                }
            } else {
                picker.dismiss(animated: true) {
                    self.onImportFinished()
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.onImportFinished()
            }
        }
    }
}

struct PickedGalleryImage {
    let previewImage: UIImage
    let originalImageURL: URL
}

struct PhotoPickerView: UIViewControllerRepresentable {
    var onImportFinished: () -> Void
    var onImagePicked: (PickedGalleryImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImportFinished: onImportFinished, onImagePicked: onImagePicked)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImportFinished: () -> Void
        let onImagePicked: (PickedGalleryImage) -> Void

        init(onImportFinished: @escaping () -> Void, onImagePicked: @escaping (PickedGalleryImage) -> Void) {
            self.onImportFinished = onImportFinished
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                DispatchQueue.main.async {
                    self.onImportFinished()
                }
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else {
                    DispatchQueue.main.async {
                        self.onImportFinished()
                    }
                    return
                }

                do {
                    let localURL = try Self.copyPickerFileToTemporaryURL(url)
                    guard let previewImage = Self.thumbnailImage(from: localURL, maxPixelSize: 1_200) else {
                        try? FileManager.default.removeItem(at: localURL)
                        throw CocoaError(.fileReadCorruptFile)
                    }

                    DispatchQueue.main.async {
                        self.onImagePicked(PickedGalleryImage(
                            previewImage: previewImage,
                            originalImageURL: localURL
                        ))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onImportFinished()
                    }
                }
            }
        }

        private static func copyPickerFileToTemporaryURL(_ url: URL) throws -> URL {
            let fileExtension = url.pathExtension.isEmpty ? "image" : url.pathExtension
            let fileName = UUID().uuidString + "." + fileExtension
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName, isDirectory: false)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            return destinationURL
        }

        private static func thumbnailImage(from url: URL, maxPixelSize: CGFloat) -> UIImage? {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
                return nil
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
    }
}

private struct ImageImportBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Text input sheet

struct TextInputView: View {
    @EnvironmentObject var viewModel: TranslatorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    var onCompleted: () -> Void
    var clearTextOnAppear: Bool

    init(onCompleted: @escaping () -> Void = {}, clearTextOnAppear: Bool = false) {
        self.onCompleted = onCompleted
        self.clearTextOnAppear = clearTextOnAppear
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter Meitei Mayek text below to get English transliteration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: viewModel.mode == .mayekToEnglish ? $viewModel.mayekTypedText : $viewModel.englishTypedText)
                        .font(.system(size: 22))
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .focused($isEditorFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if (viewModel.mode == .mayekToEnglish ? viewModel.mayekTypedText : viewModel.englishTypedText).isEmpty {
                        Text("Tap here and type or paste Meitei Mayek…")
                            .font(.system(size: 17))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isEditorFocused ? Color.purple : Color.clear, lineWidth: 2)
                )
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditorFocused = true
                }

                if viewModel.isLoading {
                    ProgressView("Transliterating…")
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        viewModel.errorMessage = nil
                        await viewModel.translateTypedText()
                        if viewModel.currentResult != nil || viewModel.forwardOutput != nil {
                            onCompleted()
                            dismiss()
                        }
                    }
                } label: {
                    Text("Transliterate")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                }
                .disabled(viewModel.isLoading)

                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("Type Meitei Mayek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
            .onAppear {
                if clearTextOnAppear {
                    viewModel.prepareForAnotherTypedTransliteration()
                } else {
                    viewModel.errorMessage = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isEditorFocused = true
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isLoading)
    }
}
