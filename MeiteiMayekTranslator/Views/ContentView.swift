//
//  ContentView.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = TranslatorViewModel()
    @State private var didStartUITestSampleImport = false

    var body: some View {
        TabView {
            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
        }
        .environmentObject(viewModel)
        .tint(.purple)
#if DEBUG
        .task {
            guard !didStartUITestSampleImport else { return }
            didStartUITestSampleImport = true
            await loadUITestSampleImageIfRequested()
        }
#endif
    }

#if DEBUG
    @MainActor
    private func loadUITestSampleImageIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-uiTestLoadSampleImage") else {
            return
        }

        let imageNameIndex = arguments.index(after: flagIndex)
        let imageName = arguments.indices.contains(imageNameIndex) ? arguments[imageNameIndex] : "meitei_mayek_nupi"

        guard let imageURL = Bundle.main.url(forResource: imageName, withExtension: "png"),
              let image = UIImage(contentsOfFile: imageURL.path) else {
            return
        }

        await viewModel.transliterateImage(image)
    }
#endif
}
