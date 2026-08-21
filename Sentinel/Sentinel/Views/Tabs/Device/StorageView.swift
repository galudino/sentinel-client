//
//  StorageView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import SwiftUI

/// **Storage** (#18) — the device's two flash-backed record stores: the System
/// Event Log and the Snapshot History. Shows each store's record count and
/// offers a destructive **Clear** guarded by a confirmation alert.
struct StorageView: View {
    let eventLog: any SystemEventLogService
    let snapshots: any SnapshotHistoryService

    @State private var eventCount: UInt32?
    @State private var snapshotCount: UInt32?
    @State private var pendingClear: Store?
    @State private var isClearing = false
    @State private var errorMessage: String?

    private enum Store: Identifiable {
        case eventLog, snapshots
        var id: Self { self }
        var title: String {
            switch self {
            case .eventLog: "System Event Log"
            case .snapshots: "Snapshot History"
            }
        }
    }

    var body: some View {
        List {
            Section("System Event Log") {
                LabeledContent("Records", value: countText(eventCount))
                Button(role: .destructive) { pendingClear = .eventLog } label: {
                    Label("Clear System Event Log", systemImage: "trash")
                }
            }

            Section("Snapshot History") {
                LabeledContent("Records", value: countText(snapshotCount))
                Button(role: .destructive) { pendingClear = .snapshots } label: {
                    Label("Clear Snapshot History", systemImage: "trash")
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isClearing)
        .overlay { if isClearing { ProgressView().controlSize(.large) } }
        .task { await loadCounts() }
        .refreshable { await loadCounts() }
        .alert(item: $pendingClear) { store in
            Alert(
                title: Text("Clear \(store.title)?"),
                message: Text(
                    "This permanently erases all records from the device's \(store.title.lowercased()). "
                        + "This cannot be undone."
                ),
                primaryButton: .destructive(Text("Clear")) { Task { await clear(store) } },
                secondaryButton: .cancel()
            )
        }
    }

    private func countText(_ value: UInt32?) -> String {
        value.map { "\($0)" } ?? "—"
    }

    private func loadCounts() async {
        eventCount = try? await eventLog.readRecordCount()
        snapshotCount = try? await snapshots.readRecordCount()
    }

    private func clear(_ store: Store) async {
        isClearing = true
        errorMessage = nil
        defer { isClearing = false }
        do {
            switch store {
            case .eventLog:
                try await eventLog.clearStore()
            case .snapshots:
                try await snapshots.clearStore()
            }
            await loadCounts()
        } catch {
            errorMessage = "Failed to clear \(store.title.lowercased()): \(error.localizedDescription)"
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview {
        NavigationStack {
            StorageView(eventLog: MockSystemEventLogService(), snapshots: MockSnapshotHistoryService())
        }
    }
#endif
