//
//  SnapshotStartSessionView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotStartSessionView

/// Configure and launch a logging session from a saved configuration: name,
/// optional fixed duration, stop-on-disconnect, and autosave cadence.
struct SnapshotStartSessionView<Provider: SnapshotDataProvider>: View {
    typealias SnapshotType = Provider.SnapshotType

    let configuration: SnapshotLoggingConfiguration<SnapshotType>

    @Environment(SnapshotLoggingManager<Provider>.self) private var loggingManager
    @Environment(\.dismiss) private var dismiss

    @State private var sessionName = ""
    @State private var captureMode: SnapshotCaptureMode
    @State private var enableFixedDuration = false
    @State private var maxDuration = DurationComponents(minutes: 5)
    @State private var useManualInput = false
    @State private var stopOnDisconnect = true
    @State private var enableAutoSave = true
    @State private var autoSaveMinutes: Double = 5
    @State private var nameValidationError: String?
    @State private var errorMessage: String?
    @State private var isStarting = false

    init(configuration: SnapshotLoggingConfiguration<SnapshotType>) {
        self.configuration = configuration
        _captureMode = State(initialValue: configuration.captureMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                durationSection
                autoSaveSection
                startSection
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: seedDefaultName)
        }
    }

    // MARK: Sections

    private var detailsSection: some View {
        Section("Session Details") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Session Name", text: $sessionName)
                    .onChange(of: sessionName) { _, newValue in
                        nameValidationError = SessionNameValidator.validate(newValue).errorMessage
                    }
                if let error = nameValidationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            LabeledContent("Configuration") { Text(configuration.name).foregroundStyle(.secondary) }
            LabeledContent("Capture Mode") { Text(captureMode.displayName).foregroundStyle(.secondary) }
            LabeledContent("Fields to Log") { Text("\(configuration.enabledFields.count)").foregroundStyle(.secondary) }
        }
    }

    private var durationSection: some View {
        Section("Duration") {
            Toggle("Set Fixed Duration", isOn: $enableFixedDuration)
            if enableFixedDuration {
                Toggle("Manual Input", isOn: $useManualInput)
                if useManualInput {
                    DurationTextInputView(duration: $maxDuration)
                } else {
                    DurationPickerView(duration: $maxDuration)
                }
                DurationDisplayView(duration: maxDuration)
            }
            Toggle("Stop on Disconnect", isOn: $stopOnDisconnect)
        }
    }

    private var autoSaveSection: some View {
        Section {
            Toggle("Enable Autosave", isOn: $enableAutoSave)
            if enableAutoSave {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Autosave Interval")
                        Spacer()
                        Text("\(Int(autoSaveMinutes)) min").foregroundStyle(.secondary)
                    }
                    Slider(value: $autoSaveMinutes, in: 1 ... 30, step: 1)
                }
            }
        } header: {
            Text("Autosave")
        } footer: {
            Text("Periodically flush captured data to disk — guards against loss on long captures.")
        }
    }

    private var startSection: some View {
        Section {
            Button(action: startSession) {
                if isStarting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Starting…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Start Logging Session").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(startDisabled)
        } footer: {
            Text(startFooterText)
        }
    }

    private var startFooterText: String {
        if captureMode == .notifications {
            return "The session subscribes to \(SnapshotType.displayName) notifications; the device pushes data."
        }
        let interval = String(format: "%.1f", configuration.pollingInterval)
        return "The session reads the \(SnapshotType.displayName) every \(interval) s."
    }

    private var startDisabled: Bool {
        !SessionNameValidator.validate(sessionName).isValid
            || isStarting
            || (enableFixedDuration && maxDuration.totalSeconds == 0)
    }

    // MARK: Actions

    private func seedDefaultName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        sessionName = "\(SnapshotType.displayName) \(formatter.string(from: Date()))"
    }

    private func startSession() {
        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = SessionNameValidator.validate(trimmedName)
        guard validation.isValid else {
            errorMessage = validation.errorMessage ?? "Invalid session name."
            return
        }

        let duration: TimeInterval? = enableFixedDuration ? TimeInterval(maxDuration.totalSeconds) : nil
        let autoSaveInterval: TimeInterval? = enableAutoSave ? autoSaveMinutes * 60 : nil

        isStarting = true
        Task {
            do {
                try await loggingManager.startLoggingSession(
                    with: configuration,
                    name: trimmedName,
                    captureMode: captureMode,
                    maxDuration: duration,
                    stopOnDisconnect: stopOnDisconnect,
                    autoSaveInterval: autoSaveInterval
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isStarting = false
            }
        }
    }
}

// MARK: - Duration helpers

private struct DurationComponents: Equatable {
    var days = 0
    var hours = 0
    var minutes = 0
    var seconds = 0

    var totalSeconds: Int { (((days * 24) + hours) * 60 + minutes) * 60 + seconds }
    var formattedVerbose: String { "\(days)d \(hours)h \(minutes)m \(seconds)s" }
    var formattedClock: String { String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds) }
}

private struct DurationPickerView: View {
    @Binding var duration: DurationComponents

    var body: some View {
        HStack(spacing: 8) {
            picker(title: "d", range: 0 ... 7, selection: $duration.days)
            picker(title: "h", range: 0 ... 23, selection: $duration.hours)
            picker(title: "m", range: 0 ... 59, selection: $duration.minutes)
            picker(title: "s", range: 0 ... 59, selection: $duration.seconds)
        }
        .frame(height: 120)
    }

    private func picker(title: String, range: ClosedRange<Int>, selection: Binding<Int>) -> some View {
        VStack {
            Picker(title, selection: selection) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DurationDisplayView: View {
    let duration: DurationComponents

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(duration.formattedVerbose)
            Text(duration.formattedClock)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DurationTextInputView: View {
    @Binding var duration: DurationComponents
    @FocusState private var focusedField: Field?

    private enum Field { case days, hours, minutes, seconds }

    var body: some View {
        HStack(spacing: 12) {
            numericField(title: "d", value: $duration.days, field: .days)
            numericField(title: "h", value: $duration.hours, field: .hours)
            numericField(title: "m", value: $duration.minutes, field: .minutes)
            numericField(title: "s", value: $duration.seconds, field: .seconds)
        }
        .onChange(of: duration.days) { _, value in duration.days = max(value, 0) }
        .onChange(of: duration.hours) { _, value in duration.hours = min(max(value, 0), 23) }
        .onChange(of: duration.minutes) { _, value in duration.minutes = min(max(value, 0), 59) }
        .onChange(of: duration.seconds) { _, value in duration.seconds = min(max(value, 0), 59) }
    }

    private func numericField(title: String, value: Binding<Int>, field: Field) -> some View {
        VStack(spacing: 4) {
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .focused($focusedField, equals: field)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
