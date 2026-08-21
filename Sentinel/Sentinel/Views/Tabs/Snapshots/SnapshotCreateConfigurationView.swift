//
//  SnapshotCreateConfigurationView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): full create-configuration flow (field picker, capture mode, interval).
struct SnapshotCreateConfigurationView<Provider: SnapshotDataProvider>: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Create Configuration", systemImage: "slider.horizontal.3")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
