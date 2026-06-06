//
//  HistoryView.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var viewModel: TranslatorViewModel
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 56))
                            .foregroundStyle(.tertiary)
                        Text("No transliterations yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Your transliteration history will appear here.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.history) { record in
                            HistoryRowView(record: record)
                        }
                        .onDelete(perform: viewModel.deleteHistory)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !viewModel.history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear all") {
                            showClearConfirm = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .confirmationDialog("Clear all history?",
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("Clear all", role: .destructive) {
                    viewModel.clearHistory()
                }
            }
        }
    }
}

struct HistoryRowView: View {
    let record: TranslationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.originalScript)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(record.englishTransliteration)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text(record.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let source = record.ocrSource {
                    Text("· \(source)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Circle()
                    .fill(confidenceColor(record.confidence))
                    .frame(width: 7, height: 7)
                Text("\(Int(record.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default:     return .red
        }
    }
}
