//
//  FirmwareSelectionView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/18/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// The DFU pre-update screen (#20). Pushed from `DeviceView` → "Update Firmware…".
/// Shows the currently-installed release, the recommended update (newest available
/// image when the device is behind), and a disclosure of every other selectable
/// image — bundled (``FirmwareCatalog``) plus Files imports
/// (``ImportedFirmwareStore``). "Begin update" confirms, then flips the app router
/// to `.updatingFirmware`, replacing the UI with `FirmwareUpdateView` (#21).
///
/// Not a tab — a navigation push from the Device tab (iOS Software-Update pattern).
struct FirmwareSelectionView: View {
    let peer: ConnectedPeer
    /// The device's running release, already read by `DeviceView`. `nil` when
    /// unknown (not yet read / read failed) — the newest image is recommended then.
    let installedVersion: FirmwareVersion?

    @Environment(AppRouter.self) private var router
    @Environment(ImportedFirmwareStore.self) private var importedStore

    @State private var bundledImages: [FirmwareImage] = []
    @State private var selectedID: FirmwareImage.ID?
    @State private var showImporter = false
    @State private var showConfirmation = false
    @State private var importError: String?

    /// Every selectable image, newest first (bundled + imported).
    private var allImages: [FirmwareImage] {
        (bundledImages + importedStore.images).sorted { $0.version > $1.version }
    }

    private var recommended: FirmwareImage? {
        guard let installedVersion else { return allImages.first }
        return FirmwareCatalog.recommended(installed: installedVersion, among: allImages)
    }

    private var selectedImage: FirmwareImage? {
        allImages.first { $0.id == selectedID }
    }

    var body: some View {
        List {
            installedSection
            if let recommended {
                recommendedSection(recommended)
            } else if !allImages.isEmpty {
                upToDateSection
            }
            otherVersionsSection
            importSection
        }
        .navigationTitle("Update Firmware")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { beginBar }
        .onAppear {
            bundledImages = FirmwareCatalog.bundledImages()
            if selectedID == nil { selectedID = recommended?.id }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert("Import failed", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Begin update") {
                if let selectedImage { router.startFirmwareUpdate(selectedImage) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The device will restart during the update. Keep it powered and nearby.")
        }
    }

    // MARK: - Sections

    private var installedSection: some View {
        Section("Currently installed") {
            LabeledContent("Version") {
                Text(installedVersion?.shortVersion ?? "Unknown")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(installedVersion == nil ? .secondary : .primary)
            }
        }
    }

    private func recommendedSection(_ image: FirmwareImage) -> some View {
        Section {
            Button {
                selectedID = image.id
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(image.versionDisplay)
                            .font(.title3.monospaced().bold())
                        Spacer()
                        Text("Update available")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.green.opacity(0.18), in: .capsule)
                            .foregroundStyle(.green)
                    }
                    if let installedVersion {
                        Text("\(installedVersion.shortVersion) → \(image.version.shortVersion)")
                            .font(.subheadline).foregroundStyle(.secondary).monospaced()
                    }
                    HStack(spacing: 12) {
                        Label(image.byteCount.formatted(.byteCount(style: .file)), systemImage: "shippingbox")
                        Label(sourceLabel(image.source), systemImage: sourceIcon(image.source))
                        Spacer()
                        selectionMark(for: image)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Recommended")
        }
    }

    private var upToDateSection: some View {
        Section {
            Label(
                "Your device is up to date with the latest available firmware.",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
        }
    }

    private var otherVersionsSection: some View {
        Section {
            DisclosureGroup("Other versions") {
                if allImages.isEmpty {
                    Text("No firmware images available. Import a .bin file below.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(allImages) { image in
                        firmwareRow(image)
                    }
                }
            }
        } footer: {
            Text(
                "Flash any signed image — e.g. to roll back or test a build. Only the "
                    + "recommended image is verified against your current version."
            )
        }
    }

    private func firmwareRow(_ image: FirmwareImage) -> some View {
        Button {
            selectedID = image.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.versionDisplay)
                        .font(.body.monospaced().weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(image.byteCount.formatted(.byteCount(style: .file)))
                        Text("·")
                        Text(sourceLabel(image.source))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let relation = relationBadge(image) {
                    Text(relation.text)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(relation.color.opacity(0.16), in: .capsule)
                        .foregroundStyle(relation.color)
                }
                selectionMark(for: image)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if image.source == .imported {
                Button(role: .destructive) {
                    if selectedID == image.id { selectedID = nil }
                    importedStore.delete(image)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("Import firmware file…", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var beginBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showConfirmation = true
            } label: {
                Text(selectedImage.map { "Begin update to \($0.versionDisplay)" } ?? "Select firmware to update")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedImage == nil)
            .padding()
        }
        .background(.bar)
    }

    // MARK: - Helpers

    @ViewBuilder private func selectionMark(for image: FirmwareImage) -> some View {
        Image(systemName: selectedID == image.id ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selectedID == image.id ? Color.accentColor : .secondary)
            .imageScale(.large)
    }

    private func relationBadge(_ image: FirmwareImage) -> (text: String, color: Color)? {
        guard let installedVersion else { return nil }
        if image.version > installedVersion { return ("Newer", .green) }
        if image.version < installedVersion { return ("Older", .orange) }
        return ("Installed", .secondary)
    }

    private func sourceLabel(_ source: FirmwareImage.Source) -> String {
        switch source {
        case .bundled: "Bundled"
        case .imported: "Imported"
        }
    }

    private func sourceIcon(_ source: FirmwareImage.Source) -> String {
        switch source {
        case .bundled: "shippingbox.fill"
        case .imported: "folder.fill"
        }
    }

    private var confirmationTitle: String {
        selectedImage.map { "Update to \($0.versionDisplay)?" } ?? "Update firmware?"
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let image = try importedStore.importFirmware(from: url)
            selectedID = image.id
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
    private func previewSelection(installed: FirmwareVersion?) -> some View {
        NavigationStack {
            FirmwareSelectionView(peer: ConnectedPeer(name: "Sentinel-A1B2"), installedVersion: installed)
        }
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ImportedFirmwareStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-fw-\(UUID().uuidString)")
        ))
    }

    #Preview("Update available (on 1.0.0)") {
        previewSelection(installed: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 0))
    }

    #Preview("Up to date (on 9.9.9)") {
        previewSelection(installed: FirmwareVersion(major: 9, minor: 9, patch: 9, build: 0))
    }

    #Preview("Unknown installed") { previewSelection(installed: nil) }
#endif
