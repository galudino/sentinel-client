//
//  SentinelApp.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 5/11/26.
//

import SwiftUI

@main
struct SentinelApp: App {
    /// Whether the launch splash (#26) has finished. Once true, the scene swaps
    /// `SplashView` for the app's root. `RootView` (the AppRouter-driven state
    /// machine, #7) replaces `ContentView` here once it lands.
    @State private var hasSplashed = false

    var body: some Scene {
        WindowGroup {
            if hasSplashed {
                ContentView()
            } else {
                SplashView(onComplete: { hasSplashed = true })
            }
        }
    }
}
