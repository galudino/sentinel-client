//
//  DebugConsoleRows.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/17/26.
//

import SwiftUI

// MARK: - Row

/// One log line: fixed-width timestamp, color-coded source glyph + severity, then
/// the wrapping message. Monospaced so columns line up like a console.
struct DebugLogLineRow: View {
    let line: DebugLogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: line.timestamp))
                .foregroundStyle(.secondary)
            Text(line.source.glyph)
                .foregroundStyle(sourceColor)
                .frame(width: 10)
            Text(line.severity.label)
                .foregroundStyle(severityColor)
            Text(line.text)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.caption.monospaced())
        .accessibilityElement(children: .combine)
    }

    private var sourceColor: Color {
        switch line.source {
        case .local: .blue
        case .device: .green
        }
    }

    private var severityColor: Color {
        switch line.severity {
        case .info: .secondary
        case .warn: .orange
        case .error: .red
        }
    }

    /// `HH:mm:ss.SSS` in local time — cached; `Date.FormatStyle` has no
    /// milliseconds component.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Filter sheet

/// Sort, source, severity, and per-service controls. The plain-text search lives
/// in the navigation `.searchable` bar; this sheet holds everything else.
struct DebugLogFilterSheet: View {
    @Binding var filter: DebugLogFilter
    @Binding var sortNewestFirst: Bool
    let services: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Order", selection: $sortNewestFirst) {
                        Text("Oldest first").tag(false)
                        Text("Newest first").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Sources") {
                    Toggle("Local BLE events", isOn: $filter.showLocal)
                    Toggle("Device debug output", isOn: $filter.showDevice)
                }
                Section("Severity") {
                    severityToggle(.info, "Info")
                    severityToggle(.warn, "Warnings")
                    severityToggle(.error, "Errors")
                }
                if !services.isEmpty {
                    Section("Services") {
                        ForEach(services, id: \.self) { service in
                            Toggle(service, isOn: serviceBinding(service))
                        }
                    }
                }
                Section {
                    Button("Reset Filters") { filter = DebugLogFilter() }
                        .disabled(!filter.isActive)
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func severityToggle(_ severity: DebugLogLine.Severity, _ title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { filter.severities.contains(severity) },
            set: { enabled in
                if enabled { filter.severities.insert(severity) } else { filter.severities.remove(severity) }
            }
        ))
    }

    /// A service toggle reads *on = visible*; toggling off mutes the service.
    private func serviceBinding(_ service: String) -> Binding<Bool> {
        Binding(
            get: { !filter.mutedServices.contains(service) },
            set: { visible in
                if visible { filter.mutedServices.remove(service) } else { filter.mutedServices.insert(service) }
            }
        )
    }
}
