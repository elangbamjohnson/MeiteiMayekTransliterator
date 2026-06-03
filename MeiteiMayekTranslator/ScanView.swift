//
//  ScanView.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import SwiftUI
import PhotosUI

struct ScanView: View {
    @EnvironmentObject var viewModel: TranslatorViewModel

    @State private var showImagePicker = false
    @State private var showPhotoPicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Header script display
                    VStack(spacing: 4) {
                        Text("ꯃꯤꯇꯩ ꯃꯌꯦꯛ")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.purple)
                        Text(viewModel.mode == .mayekToEnglish ? "Meitei Mayek → English transliteration" : "English → Meitei Mayek (to Meitei Mayek script)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Link("Same spelling rules as Meitei Mayek transliteration tool",
                             destination: URL(string: "https://abhisanoujam.github.io/meitei_mayek/")!)
                            .font(.caption2)
                    }
                    .padding(.top, 8)
                    
                    Picker("Mode", selection: $viewModel.mode) {
                        Text("Mayek → English").tag(TranslatorViewModel.TransliterationMode.mayekToEnglish)
                        Text("English → Mayek").tag(TranslatorViewModel.TransliterationMode.englishToMayek)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Camera capture card
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            imagePickerSource = .camera
                            showImagePicker = true
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemGray6))
                                .frame(height: 180)
                                .opacity(UIImagePickerController.isSourceTypeAvailable(.camera) ? 1 : 0.5)

                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.purple)
                                Text("Tap to scan script")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(UIImagePickerController.isSourceTypeAvailable(.camera) ? "Point camera at Meitei Mayek text" : "Camera not available on this device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    .padding(.horizontal)

                    // Secondary options
                    HStack(spacing: 12) {
                        // Gallery picker
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Gallery", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal)

                    // Inline type-to-transliterate section
                    VStack(spacing: 12) {
                        Text(viewModel.mode == .mayekToEnglish ? "Type Meitei Mayek text to transliterate" : "Type English text to convert to Meitei Mayek")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        TextEditor(text: $viewModel.typedText)
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
                        .disabled(viewModel.isLoading || viewModel.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                                    Label("Transliteration (Latin)", systemImage: "character.book.closed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(result.romanizedText)
                                        .font(.title3)
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack { Spacer() }
                                }
                                .padding()
                                .background(Color.purple.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal)

                                // Pronunciation card
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Pronunciation", systemImage: "waveform")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(result.englishPronunciation)
                                        .font(.title3)
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack { Spacer() }
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
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(sourceType: imagePickerSource) { image in
                    Task {
                        await viewModel.translateImage(image)
                    }
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerView { image in
                    Task {
                        await viewModel.translateImage(image)
                    }
                }
            }
        }
    }
    
    private var confidenceColor: Color {
        guard let result = viewModel.currentResult else { return .gray }
        switch result.confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default:     return .red
        }
    }
}

// MARK: - UIImagePickerController wrapper

struct ImagePickerView: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onImagePicked: (UIImage) -> Void
        init(onImagePicked: @escaping (UIImage) -> Void) { self.onImagePicked = onImagePicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
    }
}

import PhotosUI

struct PhotoPickerView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void

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
        Coordinator(onImagePicked: onImagePicked)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.onImagePicked(image)
                    }
                }
            }
        }
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
                    TextEditor(text: $viewModel.typedText)
                        .font(.system(size: 22))
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .focused($isEditorFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if viewModel.typedText.isEmpty {
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
                        if viewModel.currentResult != nil {
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

