//
//  SnapshotExportSessionView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - PreviewEntryCount

nonisolated enum PreviewEntryCount: Int, CaseIterable, Identifiable {
    case entries5 = 5
    case entries10 = 10
    case entries25 = 25
    case entries50 = 50
    case entries100 = 100
    case entries200 = 200

    var id: Int { rawValue }

    /// JSON is verbose, so its preview is limited to small counts.
    static let jsonAllowedCases: [PreviewEntryCount] = [.entries5, .entries10]
    static let csvAllowedCases: [PreviewEntryCount] = [.entries25, .entries50, .entries100, .entries200]
}

// MARK: - SnapshotExportSessionView

/// Configure and run an export of a completed session: choose a format
/// (JSON / CSV / binary), select which data and timing fields to include, preview
/// the output, name the file, and share it. Preview and export both go through
/// ``SnapshotLoggingManager/exportSession(_:format:selectedFieldKeyPaths:selectedTimingFieldIds:)``
/// (the preview on a truncated copy), so what you see is exactly what you get.
struct SnapshotExportSessionView<Provider: SnapshotDataProvider>: View {
    // swiftlint:disable:next type_name
    typealias S = Provider.S

    let session: SnapshotLoggingSession

    @Environment(SnapshotLoggingManager<Provider>.self) var loggingManager
    @Environment(\.dismiss) private var dismiss

    // Non-private so the +Logic extension (separate file) can drive preview/export.
    @State var selectedFormat: LoggingExportFormat = .csv
    @State var previewEntryCount: PreviewEntryCount = .entries25
    @State var selectedExportFieldKeyPaths: Set<String> = []
    @State var selectedTimingFieldIds: Set<String> = []
    @State var exportFileName = ""
    @State private var exportNameValidationError: String?
    @State var exportedFileURL: URL?
    @State var errorMessage: String?

    @State var showingShareSheet = false
    @State private var showingFullPreview = false
    @State private var showingFieldSelection = false
    @State private var showingTimingFieldSelection = false

    var body: some View {
        NavigationStack {
            Form {
                sessionInfoSection
                if !timingRows.isEmpty {
                    Section("Timing Metrics") {
                        TimingMetricsTable(columnHeaders: ["avg (ms)", "min (ms)", "max (ms)"], rows: timingRows)
                    }
                }
                dataOutputSection
            }
            .navigationTitle("Export Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL { SnapshotShareSheet(items: [url]) }
            }
            .sheet(isPresented: $showingFullPreview) {
                FullExportPreviewView(text: fullPreviewText, title: "\(exportFileName).\(selectedFormat.fileExtension)")
            }
            .sheet(isPresented: $showingFieldSelection) {
                SnapshotSelectExportFieldsView<S>(
                    availableFieldKeyPaths: availableFieldKeyPaths,
                    selectedFieldKeyPaths: $selectedExportFieldKeyPaths
                )
            }
            .sheet(isPresented: $showingTimingFieldSelection) {
                SnapshotSelectTimingFieldsView(
                    captureMode: session.captureMode,
                    selectedFieldIds: $selectedTimingFieldIds
                )
            }
            .onAppear(perform: seedDefaults)
            .onChange(of: selectedFormat) { _, _ in clampPreviewEntryCount() }
        }
    }

    // MARK: Sections

    private var sessionInfoSection: some View {
        Section("Session Information") {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.name).font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    labeledCaption("Started:", SessionFormat.timestamp(session.startTime))
                    if let endTime = session.endTime {
                        labeledCaption("Ended:", SessionFormat.timestamp(endTime))
                    }
                }
                HStack {
                    Text("Duration: \(SessionFormat.clockWithMillis(session.actualDuration))")
                    Spacer()
                    Text("\(session.logEntries.count) entries")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                SessionModeChip(session: session)
            }
        }
    }

    private var dataOutputSection: some View {
        Section("Data Output") {
            Button { showingFieldSelection = true } label: {
                selectorRow(
                    "Select Data Fields",
                    "\(selectedExportFieldKeyPaths.count) of \(availableFieldKeyPaths.count)"
                )
            }
            Button { showingTimingFieldSelection = true } label: {
                let total = SnapshotTimingFieldConfig.fields(for: session.captureMode).count
                selectorRow("Select Timing Fields", "\(selectedTimingFieldIds.count) of \(total)")
            }

            Picker("Format", selection: $selectedFormat) {
                ForEach(LoggingExportFormat.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            if selectedFormat == .binary {
                Text("Binary is the raw, loss-free \(SessionBinaryFormat.fileExtension) file — no text preview.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                previewControls
            }

            fileNameField

            Button(action: exportSession) {
                Text("Export").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!SessionNameValidator.validate(exportFileName).isValid)
        }
    }

    @ViewBuilder private var previewControls: some View {
        Picker("Preview Entries", selection: $previewEntryCount) {
            ForEach(availablePreviewCounts) { Text("\($0.rawValue)").tag($0) }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Tap for full preview").font(.caption2).foregroundStyle(.blue)
            }
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(sampleOutputPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .frame(height: 150)
            .onTapGesture { showingFullPreview = true }

            if session.logEntries.count > previewEntryCount.rawValue {
                Text("Showing first \(previewEntryCount.rawValue) of \(session.logEntries.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var fileNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export File Name").font(.caption).foregroundStyle(.secondary)
            TextField("File name", text: $exportFileName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: exportFileName) { _, newValue in
                    exportNameValidationError = SessionNameValidator.validate(newValue).errorMessage
                }
            if let error = exportNameValidationError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
            }
            Text("Extension .\(selectedFormat.fileExtension) is added automatically")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Small helpers

    private func selectorRow(_ title: String, _ trailing: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(trailing).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledCaption(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 60, alignment: .leading)
            Text(value)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
