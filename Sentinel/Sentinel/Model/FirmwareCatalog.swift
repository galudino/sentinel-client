//
//  FirmwareCatalog.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation

/// Sources the firmware images `FirmwareSelectionView` (#20) offers, and the
/// recommend/ordering logic over them.
///
/// **Phase I: bundled images only.** Known-good signed `.bin`s ship in the app
/// bundle under `Resources/Firmware/`, named `sentinel-firmware_<version>[-<label>].bin`
/// — currently the stable **`1.0.1`** (the recommended baseline / "factory reset"
/// image) and a deliberately-absurd **`255.255.255-test`** standout test build. The
/// newest *stable* image is the "recommended" default; pre-release/test builds
/// (a `-<label>` suffix) are selectable but never recommended. Bundling stock
/// firmware lets the app reflash a device to known-good firmware offline.
///
/// **Later (Phase IV, issue #32):** cloud retrieval from S3 becomes another source
/// and the true "latest" — the recommend logic below is source-agnostic, so it
/// slots in without change. Files imported from the Files app are the other source
/// today, via ``ImportedFirmwareStore``.
enum FirmwareCatalog {
    /// Bundle subdirectory the signed images ship in.
    static let bundleSubdirectory = "Firmware"
    /// Convention prefix on bundled image file names.
    static let fileNamePrefix = "sentinel-firmware_"

    /// All signed images shipped in `bundle`, newest version first. Looks in the
    /// `Firmware/` subdirectory first, then falls back to a bundle-wide search
    /// (synchronized groups may copy resources flat), filtering to the naming
    /// convention either way.
    static func bundledImages(in bundle: Bundle = .main) -> [FirmwareImage] {
        var urls = bundle.urls(forResourcesWithExtension: "bin", subdirectory: bundleSubdirectory) ?? []
        if urls.isEmpty {
            urls = bundle.urls(forResourcesWithExtension: "bin", subdirectory: nil) ?? []
        }
        return urls
            .filter { $0.lastPathComponent.hasPrefix(fileNamePrefix) }
            .compactMap { image(contentsOf: $0, source: .bundled) }
            .sorted { $0.version > $1.version }
    }

    /// Build a ``FirmwareImage`` by reading `url` and parsing its file name for a
    /// version + display label. Returns `nil` only if the bytes can't be read; an
    /// unparseable name still yields an image (version `0.0.0`, the file name as
    /// its label) so an arbitrarily-named import is still selectable.
    static func image(contentsOf url: URL, source: FirmwareImage.Source) -> FirmwareImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let fileName = url.lastPathComponent
        let parsed = parse(fileName: fileName)
        return FirmwareImage(
            version: parsed?.version ?? FirmwareVersion(major: 0, minor: 0, patch: 0, build: 0),
            displayName: parsed?.displayName ?? fileName,
            isPrerelease: parsed?.isPrerelease ?? false,
            data: data,
            source: source,
            fileName: fileName
        )
    }

    /// A firmware file name parsed into its numeric version + display label.
    struct ParsedName: Equatable {
        let version: FirmwareVersion
        /// The version token verbatim, keeping any pre-release suffix (`"255.255.255-test"`).
        let displayName: String
        /// A pre-release/test build — the token carries a `-<label>` suffix.
        var isPrerelease: Bool { displayName.contains("-") }
    }

    /// Parse a firmware file name into its version + display label.
    /// `"sentinel-firmware_255.255.255-test.bin"` → version `255.255.255`, label
    /// `"255.255.255-test"`, `isPrerelease == true`. The label keeps the suffix the
    /// numeric version drops.
    static func parse(fileName: String) -> ParsedName? {
        var name = fileName
        if name.lowercased().hasSuffix(".bin") { name = String(name.dropLast(4)) }

        let token: String = if name.hasPrefix(fileNamePrefix) {
            String(name.dropFirst(fileNamePrefix.count))
        } else if let underscore = name.lastIndex(of: "_") {
            String(name[name.index(after: underscore)...])
        } else {
            name
        }

        // The numeric version is the token up to the first "-" (pre-release sep).
        let numeric = token.split(separator: "-", maxSplits: 1).first.map(String.init) ?? token
        guard let version = FirmwareVersion(parsing: numeric) else { return nil }
        return ParsedName(version: version, displayName: token)
    }

    /// The newest **stable** image strictly newer than `installed`, or `nil` when
    /// the device is already up to date. Pre-release/test builds (e.g.
    /// `255.255.255-test`) are excluded — they remain selectable in the picker but
    /// are never offered as the recommended update or the badge/banner signal (#14).
    static func recommended(installed: FirmwareVersion, among images: [FirmwareImage]) -> FirmwareImage? {
        images
            .filter { $0.version > installed && !$0.isPrerelease }
            .max { $0.version < $1.version }
    }
}
