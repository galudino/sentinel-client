//
//  SnapshotConfigurationRowView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotConfigurationRowView

/// One row in the Configurations section: name, capture mode + interval, created
/// date, and a Start Session action. The Snapshots tab only exists while
/// connected, so starting a session needs no connection gate.
struct SnapshotConfigurationRowView<Provider: SnapshotDataProvider>: View {
    // swiftlint:disable:next type_name
    typealias S = Provider.S

    let configuration: SnapshotLoggingConfiguration<S>
    @State private var showingStartSession = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(configuration.name)
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Label(
                            configuration.captureMode.displayName,
                            systemImage: configuration.captureMode.systemImageName
                        )
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(modeTint.opacity(0.1))
                        .foregroundStyle(modeTint)
                        .cornerRadius(4)

                        if configuration.captureMode == .polling {
                            Text("\(String(format: "%.2f", configuration.pollingInterval))s interval")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Created: \(formatTimestamp(configuration.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Start Session") { showingStartSession = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingStartSession) {
            SnapshotStartSessionView<Provider>(configuration: configuration)
        }
    }

    private var modeTint: Color {
        configuration.captureMode == .polling ? .blue : .purple
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
