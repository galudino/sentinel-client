//
//  LoggingExportFormat.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - LoggingExportFormat

/// The formats a completed session can be exported to. Exports are always
/// **full resolution** — chart decimation never touches exported data.
enum LoggingExportFormat: String, CaseIterable, Identifiable {
    /// Structured JSON: session metadata + field schema + every entry.
    case json
    /// Comma-separated values, one row per entry.
    case csv
    /// The raw `.sentinelsession` binary file (smallest; loss-free).
    case binary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        case .binary: "Binary"
        }
    }

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        case .binary: SessionBinaryFormat.fileExtension
        }
    }

    var utType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        case .binary: .data
        }
    }

    var systemImageName: String {
        switch self {
        case .json: "curlybraces"
        case .csv: "tablecells"
        case .binary: "doc.badge.gearshape"
        }
    }
}
