//
//  SerialNumberEditView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import SwiftUI

/// Pushed editor for the device **serial number** — the device-identity key
/// (#18). Sensitive: a confirmation alert guards the write, and the view
/// re-reads afterward so a device that silently rejects the write surfaces as an
/// unchanged value rather than a false success.
struct SerialNumberEditView: View {
    let system: any SystemService
    let current: UInt32?
    /// Called with the confirmed value after a successful write + re-read.
    let onWritten: (UInt32) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var hexText: String = ""
    @State private var confirming = false
    @State private var isWriting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Serial (hex)", text: $hexText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                Text("Serial Number")
            } footer: {
                Text(
                    "32-bit device-identity key, entered as hex (e.g. 0000ABCD). "
                        + "Changing it re-identifies the device."
                )
            }

            if let parsed {
                LabeledContent("Will write", value: String(format: "0x%08X", parsed))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Edit Serial")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { confirming = true }
                    .disabled(parsed == nil || parsed == current || isWriting)
            }
        }
        .overlay { if isWriting { ProgressView().controlSize(.large) } }
        .onAppear {
            if hexText.isEmpty, let current { hexText = String(format: "%08X", current) }
        }
        .alert("Change serial number?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Write", role: .destructive) { Task { await write() } }
        } message: {
            if let parsed {
                Text("Write \(String(format: "0x%08X", parsed)) to the device? This changes its identity key.")
            }
        }
    }

    /// The hex text parsed to a `UInt32`, or `nil` if malformed / out of range.
    private var parsed: UInt32? {
        let trimmed = hexText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        guard !trimmed.isEmpty, trimmed.count <= 8 else { return nil }
        return UInt32(trimmed, radix: 16)
    }

    private func write() async {
        guard let parsed else { return }
        isWriting = true
        errorMessage = nil
        defer { isWriting = false }
        do {
            try await system.writeSerialNumber(parsed)
            let confirmed = try await system.readSerialNumber()
            guard confirmed == parsed else {
                errorMessage = "Device reported \(String(format: "0x%08X", confirmed)) after the write."
                return
            }
            onWritten(confirmed)
            dismiss()
        } catch {
            errorMessage = "Write failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview {
        NavigationStack {
            SerialNumberEditView(system: MockSystemService(), current: 0x0000_ABCD) { _ in }
        }
    }
#endif
