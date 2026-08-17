//
//  FirmwareImage.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation

/// A firmware payload selected for OTA DFU — the thing the router carries into
/// the `.updatingFirmware` state and hands to `FirmwareUpdateView` (#21).
///
/// **Seed for #7 (navigation state machine).** Just enough to identify a payload
/// and make `AppState` `Equatable`. The firmware-selection flow (#20) and the DFU
/// uploader (#22) own the real model — image bytes / file URL, MCUBoot header,
/// CRC32, negotiated chunking. See `docs/architecture/architecture.md` (OTA DFU
/// wire protocol).
struct FirmwareImage: Equatable, Identifiable {
    let id: UUID
    /// Human-readable version, e.g. `"1.1.0"`. Display + confirm-after-reconnect.
    let version: String

    init(id: UUID = UUID(), version: String) {
        self.id = id
        self.version = version
    }
}
