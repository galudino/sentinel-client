//
//  SnapshotRenameSessionView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotRenameSessionView

/// Rename a completed session, validating the new name against the same
/// filesystem-safe rules used at session creation.
struct SnapshotRenameSessionView<Provider: SnapshotDataProvider>: View {
    let session: SnapshotLoggingSession

    @Environment(SnapshotLoggingManager<Provider>.self) private var loggingManager
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Name") {
                    Text(session.name).foregroundStyle(.secondary)
                }

                Section("New Name") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Enter new name", text: $newName)
                            .onChange(of: newName) { _, newValue in
                                validationError = SessionNameValidator.validate(newValue).errorMessage
                            }
                        if let error = validationError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button(action: rename) {
                        Text("Rename").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SessionNameValidator.validate(newName).isValid)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .navigationTitle("Rename Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { newName = session.name }
        }
    }

    private func rename() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = SessionNameValidator.validate(trimmed)
        guard validation.isValid else {
            validationError = validation.errorMessage
            return
        }
        loggingManager.renameSession(session.id, to: trimmed)
        dismiss()
    }
}
