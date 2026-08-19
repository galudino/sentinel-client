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
/// Expanded past its #7 seed (which held only an id + a display string) to carry
/// what the DFU actually needs: the **signed image bytes** (chunked to the
/// negotiated MTU, CRC32'd for the `Verify` handshake) and the **target
/// ``FirmwareVersion``** (confirmed by reading the System service back after the
/// device reboots). The full selection UI — bundled catalog + Files import +
/// recommended-image logic — remains #20's job; this is the model both #20 and
/// #21/#22 share.
struct FirmwareImage: Equatable, Identifiable {
    /// Where a selectable image came from — surfaced per-row in the #20 picker.
    enum Source: Equatable {
        /// Shipped inside the app bundle (known-good test images).
        case bundled
        /// Imported from Files / iCloud / AirDrop into the app's Documents dir.
        case imported
    }

    let id: UUID
    /// The image's own version — the value the device should report after a
    /// successful flash + reboot.
    let version: FirmwareVersion
    /// The signed MCUBoot image bytes to upload.
    let data: Data
    let source: Source
    /// Original file name, when imported — display only.
    let fileName: String?

    init(
        id: UUID = UUID(),
        version: FirmwareVersion,
        data: Data,
        source: Source = .imported,
        fileName: String? = nil
    ) {
        self.id = id
        self.version = version
        self.data = data
        self.source = source
        self.fileName = fileName
    }

    /// Image size in bytes — drives the `Start Download` command and the upload
    /// chunk count.
    var byteCount: Int { data.count }

    /// Dotted display version without the build number, e.g. `"1.2.3"`.
    var versionDisplay: String { version.shortVersion }
}

extension FirmwareImage {
    /// A stand-in image for the Device tab's "Update Firmware…" seed until the real
    /// selection flow (#20) supplies bundled/imported images. Synthetic bytes — it
    /// exercises the #21 UI + #22 state machine but is not a real signed image, so
    /// a live device will reject it at `Verify` (the intended, safe outcome).
    static func placeholder(
        version: FirmwareVersion = FirmwareVersion(major: 1, minor: 1, patch: 0, build: 0)
    ) -> FirmwareImage {
        FirmwareImage(
            version: version,
            data: Data(repeating: 0xAB, count: 64 * 1024),
            source: .bundled,
            fileName: "placeholder.bin"
        )
    }
}

#if DEBUG
    extension FirmwareImage {
        /// Convenience for tests/previews: build an image from a dotted version
        /// string with synthetic bytes. Keeps the pre-expansion call sites
        /// (`FirmwareImage(version: "1.1.0")`) working unchanged.
        init(version string: String, byteCount: Int = 64 * 1024, source: Source = .bundled) {
            self.init(
                id: UUID(),
                version: FirmwareVersion(parsing: string) ?? FirmwareVersion(major: 0, minor: 0, patch: 0, build: 0),
                data: Data(repeating: 0xAB, count: byteCount),
                source: source,
                fileName: nil
            )
        }
    }
#endif
