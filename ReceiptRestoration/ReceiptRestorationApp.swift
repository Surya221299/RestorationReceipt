//
//  ReceiptRestorationApp.swift
//  ReceiptRestoration
//
//  Created by Nicholas Tristandi on 17/05/26.
//

import SwiftUI

@main
struct VisionMLReceiptOCRApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
        }
    }
}
