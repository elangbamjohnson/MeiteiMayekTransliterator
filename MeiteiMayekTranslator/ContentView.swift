//
//  ContentView.swift
//  MeiteiMayekTranslator
//
//  Created by Johnson Elangbam on 01/06/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranslatorViewModel()

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
    }
}
