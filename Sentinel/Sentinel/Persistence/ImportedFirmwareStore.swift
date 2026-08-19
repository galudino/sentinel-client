//
//  ImportedFirmwareStore.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation
import Observation

/// The persistent set of firmware `.bin`s the user imported from Files (#20).
/// Picked files are **copied** into the app's Documents dir so they survive
/// relaunches without holding a security-scoped bookmark. `@Observable`, **no
/// singleton** — created once in `SentinelApp.init()` and injected with
/// `.environment(...)`, alongside the bundled images from ``FirmwareCatalog``.
@Observable
final class ImportedFirmwareStore {
    /// Imported images, newest version first. Refreshed on import / delete.
    private(set) var images: [FirmwareImage] = []

    private let directory: URL

    /// - Parameter directory: injectable for tests (pass a temp dir).
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        refresh()
    }

    private static func defaultDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ImportedFirmware", isDirectory: true)
    }

    /// Re-read the imported directory into ``images``.
    func refresh() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        images = contents
            .filter { $0.pathExtension.lowercased() == "bin" }
            .compactMap { FirmwareCatalog.image(contentsOf: $0, source: .imported) }
            .sorted { $0.version > $1.version }
    }

    /// Copy a user-picked `.bin` into the store and return the resulting image.
    /// Re-importing the same file name overwrites the prior copy.
    @discardableResult
    func importFirmware(from pickedURL: URL) throws -> FirmwareImage {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }

        let destination = directory.appendingPathComponent(pickedURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: pickedURL, to: destination)
        refresh()

        guard let image = images.first(where: { $0.fileName == destination.lastPathComponent }) else {
            throw ImportedFirmwareError.copyFailed
        }
        return image
    }

    /// Delete an imported image's backing file.
    func delete(_ image: FirmwareImage) {
        guard image.source == .imported, let fileName = image.fileName else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        refresh()
    }
}

enum ImportedFirmwareError: LocalizedError {
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .copyFailed: "Couldn't import that firmware file."
        }
    }
}
