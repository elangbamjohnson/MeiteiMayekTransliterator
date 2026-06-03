//
//  ResultView.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import SwiftUI

struct ResultView: View {
    @EnvironmentObject var viewModel: TranslatorViewModel
    @Environment(\.dismiss) var dismiss

    @State private var scriptCopied = false
    @State private var englishCopied = false
    @State private var showTextInput = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let result = viewModel.currentResult {

                    if let image = viewModel.selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Detected Meitei Mayek", systemImage: "text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(result.detectedScript)
                            .font(.system(size: 24))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
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
                                viewModel.speak(result.englishTransliteration)
                            } label: {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .foregroundStyle(.purple)
                            }

                            Button {
                                UIPasteboard.general.string = result.detectedScript
                                withAnimation { scriptCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    scriptCopied = false
                                }
                            } label: {
                                Image(systemName: scriptCopied ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(scriptCopied ? .green : .secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            if let source = result.ocrSource {
                                Text("OCR: \(source)")
                            }
                            Text("· \(result.transliterationEngine)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("English transliteration", systemImage: "textformat.abc")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(result.englishTransliteration)
                            .font(.title3)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("English pronunciation spelling — not word-for-word translation.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        HStack {
                            Button {
                                viewModel.speak(result.englishTransliteration)
                            } label: {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.purple)
                            }

                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = result.englishTransliteration
                                withAnimation { englishCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    englishCopied = false
                                }
                            } label: {
                                Label(englishCopied ? "Copied!" : "Copy",
                                      systemImage: englishCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(englishCopied ? .green : .purple)
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

                    HStack(spacing: 12) {
                        Button {
                            shareResult(result)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            viewModel.prepareForAnotherTypedTransliteration()
                            showTextInput = true
                        } label: {
                            Label("Type more", systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        if viewModel.selectedImage != nil {
                            viewModel.reset()
                        }
                        dismiss()
                    } label: {
                        Label(
                            viewModel.selectedImage != nil ? "Scan again" : "Back to home",
                            systemImage: viewModel.selectedImage != nil ? "camera.viewfinder" : "house"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .padding(.top)
        }
        .navigationTitle("Transliteration")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTextInput) {
            TextInputView {
                showTextInput = false
            }
            .environmentObject(viewModel)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    private func shareResult(_ result: TransliterationResult) {
        let text = """
        Meitei Mayek:
        \(result.detectedScript)

        English transliteration:
        \(result.englishTransliteration)
        """
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let vc = windowScene.windows.first?.rootViewController {
            vc.present(av, animated: true)
        }
    }
}
