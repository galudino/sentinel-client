//
//  SettingsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Settings** tab — strictly *app-side* preferences (theme, units,
/// notifications, paired peers). Device-side concerns live in the Device tab.
///
/// **Stub for #14.** The real preferences (backed by `AppPreferences` +
/// `PairedPeerStore` #23) land in **#19**.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "App Settings",
                systemImage: "gearshape.fill",
                description: Text("Theme, units, notifications, and paired-device management arrive in #19.")
            )
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
