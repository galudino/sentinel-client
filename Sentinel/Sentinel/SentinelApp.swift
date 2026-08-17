//
//  SentinelApp.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 5/11/26.
//

import SwiftUI

@main
struct SentinelApp: App {
    /// App-wide `@Observable` objects — created once here and injected via
    /// `.environment(...)`, read in views via `@Environment`. **No `.shared`
    /// singletons.** Independent objects are created directly; objects that
    /// depend on them are created after, via `_x = State(initialValue:)` (see
    /// `init()`). More arrive as the BLE layer (#8) and stores (#23) land.
    @State private var bluetoothManager: BluetoothManager
    @State private var router: AppRouter
    @State private var pairedPeerStore: PairedPeerStore
    @State private var appPreferences: AppPreferences

    /// Whether the launch splash (#26) has finished. Once true, the scene swaps
    /// `SplashView` for `RootView` (the AppRouter-driven state machine, #7).
    @State private var hasSplashed = false

    init() {
        let bluetoothManager = BluetoothManager()
        self.bluetoothManager = bluetoothManager
        pairedPeerStore = PairedPeerStore()
        appPreferences = AppPreferences()

        // `AppRouter` depends on the manager, so build it once the independent
        // object exists.
        _router = State(initialValue: AppRouter(bluetoothManager: bluetoothManager))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSplashed {
                    RootView()
                        .environment(bluetoothManager)
                        .environment(router)
                        .environment(pairedPeerStore)
                        .environment(appPreferences)
                } else {
                    SplashView(onComplete: { hasSplashed = true })
                }
            }
            .preferredColorScheme(appPreferences.theme.colorScheme)
        }
    }
}
