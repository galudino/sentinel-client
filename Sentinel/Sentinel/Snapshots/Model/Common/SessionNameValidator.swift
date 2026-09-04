//
//  SessionNameValidator.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SessionNameValidator

/// Validates session and export file names for characters that are problematic
/// across macOS, iOS, Windows, and Linux filesystems.
enum SessionNameValidator {
    static let forbiddenCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
    static let maxNameLength = 128

    // MARK: - ValidationResult

    enum ValidationResult: Equatable {
        case valid
        case empty
        case tooLong
        case containsForbiddenCharacters(String)
        case reservedName

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        var errorMessage: String? {
            switch self {
            case .valid: nil
            case .empty: "Name cannot be empty."
            case .tooLong: "Name must be \(SessionNameValidator.maxNameLength) characters or fewer."
            case let .containsForbiddenCharacters(chars): "Name cannot contain: \(chars)"
            case .reservedName: "This name is reserved and cannot be used."
            }
        }
    }

    // MARK: - Validation

    static func validate(_ name: String) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxNameLength { return .tooLong }

        let foundForbidden = trimmed.unicodeScalars.filter { forbiddenCharacters.contains($0) }
        if !foundForbidden.isEmpty {
            let uniqueChars = Set(foundForbidden.map { String($0) }).sorted().joined(separator: " ")
            return .containsForbiddenCharacters(uniqueChars)
        }

        let reservedNames: Set<String> = [
            ".", "..", "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
        ]
        if reservedNames.contains(trimmed.uppercased()) { return .reservedName }

        return .valid
    }

    /// Replace forbidden characters with underscores for use as a filename.
    static func sanitizeForFilename(_ name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars {
            result.append(forbiddenCharacters.contains(scalar) ? "_" : Character(scalar))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
