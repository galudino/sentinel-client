//
//  FirmwareImage.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation

/// A firmware payload selected for OTA DFU — the thing the router carries into
/// the `.updatingFirmware` state and hands to `FirmwareUpdateView` (#21), which
/// streams ``data`` to the device via the OTA uploader (#22).
///
/// Carries what the DFU actually needs: the **signed MCUBoot image bytes** (chunked
/// to the negotiated MTU, CRC32'd for the `Verify` handshake) and the **target
/// ``FirmwareVersion``** (confirmed by reading the System service back after the
/// device reboots), plus a human ``displayName`` (e.g. `"1.0.1-test"`) that may
/// carry a pre-release label the numeric version drops. Produced by
/// ``FirmwareCatalog`` (bundled images) and ``ImportedFirmwareStore`` (Files
/// imports); selected in `FirmwareSelectionView` (#20).
struct FirmwareImage: Equatable, Identifiable {
    /// Where a selectable image came from — surfaced per-row in the #20 picker.
    enum Source: Equatable {
        /// Shipped inside the app bundle (known-good test/rollback images).
        case bundled
        /// Imported from Files / iCloud / AirDrop into the app's Documents dir.
        case imported
    }

    let id: UUID
    /// The image's own version — the release the device should report after a
    /// successful flash + reboot.
    let version: FirmwareVersion
    /// Human display label — `"1.0.0"`, `"1.0.1-test"`, or an imported file's name
    /// when its version can't be parsed. Defaults to the numeric short version.
    let displayName: String
    /// The signed MCUBoot image bytes to upload.
    let data: Data
    let source: Source
    /// Original file name, when known — display + de-dup on import.
    let fileName: String?

    init(
        id: UUID = UUID(),
        version: FirmwareVersion,
        displayName: String? = nil,
        data: Data,
        source: Source = .imported,
        fileName: String? = nil
    ) {
        self.id = id
        self.version = version
        self.displayName = displayName ?? version.shortVersion
        self.data = data
        self.source = source
        self.fileName = fileName
    }

    /// Image size in bytes — drives the `Start Download` command and the upload
    /// chunk count.
    var byteCount: Int { data.count }

    /// The label shown wherever a version is presented (cards, progress view).
    var versionDisplay: String { displayName }
}

#if DEBUG
    extension FirmwareImage {
        /// Convenience for tests/previews: build an image from a dotted version
        /// string with synthetic bytes. The string becomes the display label, so
        /// `FirmwareImage(version: "1.1.0")` shows `1.1.0`.
        init(version string: String, byteCount: Int = 64 * 1024, source: Source = .bundled) {
            // Parse just the numeric part so a pre-release label (e.g. "1.0.1-test")
            // still yields version 1.0.1 while keeping the full string as the label.
            let numeric = string.split(separator: "-", maxSplits: 1).first.map(String.init) ?? string
            self.init(
                version: FirmwareVersion(parsing: numeric) ?? FirmwareVersion(major: 0, minor: 0, patch: 0, build: 0),
                displayName: string,
                data: Data(repeating: 0xAB, count: byteCount),
                source: source,
                fileName: nil
            )
        }
    }
#endif
