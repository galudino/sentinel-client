//
//  SnapshotShareSheet.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotShareSheet

/// Thin `UIActivityViewController` wrapper for sharing exported session files.
struct SnapshotShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
