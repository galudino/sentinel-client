//
//  CharacteristicDetailView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import CoreBluetooth
import Foundation
import SwiftUI

/// How the raw bytes (and, for scalar types, the combined integer) are rendered.
enum GATTByteFormat: String, CaseIterable, Identifiable {
    case hex = "Hex"
    case dec = "Dec"
    case oct = "Oct"
    case utf8 = "UTF-8"
    case raw = "Raw"

    var id: Self { self }

    /// Render a byte sequence in this format.
    func renderBytes(_ data: Data) -> String {
        guard !data.isEmpty else { return "(empty)" }
        switch self {
        case .hex: return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .dec: return data.map { String($0) }.joined(separator: " ")
        case .oct: return data.map { String(format: "%03o", $0) }.joined(separator: " ")
        case .utf8: return String(bytes: data, encoding: .utf8) ?? "(non-UTF-8)"
        case .raw: return data.map { String(format: "%02X", $0) }.joined()
        }
    }

    /// Render a combined little-endian integer in this format (falls back to hex
    /// for the non-numeric formats).
    func renderInteger(_ value: UInt64) -> String {
        switch self {
        case .dec: String(value)
        case .oct: "0o" + String(value, radix: 8)
        case .hex, .utf8, .raw: "0x" + String(value, radix: 16, uppercase: true)
        }
    }
}

/// **Characteristic detail** (#18) — read / write / notify one characteristic
/// through the raw ``BluetoothPeripheralTransport``. The single place a new
/// characteristic is exercised before it gets a polished view.
struct CharacteristicDetailView: View {
    let descriptor: CharacteristicDescriptor
    let transport: any BluetoothPeripheralTransport

    @State private var lastData: Data?
    @State private var lastUpdated: Date?
    @State private var format: GATTByteFormat = .hex
    @State private var isReading = false
    @State private var errorMessage: String?

    // Notify
    @State private var isNotifying = false
    @State private var notifyCount = 0
    @State private var notifyTask: Task<Void, Never>?

    // Write
    @State private var writeText = ""
    @State private var isWriting = false

    private var service: CBUUID { descriptor.service.cbuuid }
    private var canRead: Bool { descriptor.properties.contains(.read) }
    private var canWrite: Bool {
        descriptor.properties.contains(.write) || descriptor.properties.contains(.writeWithoutResponse)
    }

    private var canNotify: Bool {
        descriptor.properties.contains(.notify) || descriptor.properties.contains(.indicate)
    }

    var body: some View {
        List {
            infoSection
            if canRead || lastData != nil { valueSection }
            if canNotify { notifySection }
            if canWrite { writeSection }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(descriptor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { if canRead { await read() } }
        .onDisappear { notifyTask?.cancel() }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section("Characteristic") {
            LabeledContent("Service", value: descriptor.service.displayName)
            LabeledContent("Type", value: typeText)
            if let unit = descriptor.lsbUnit {
                LabeledContent("Unit", value: unit)
            }
            LabeledContent("Properties", value: descriptor.properties.compactLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text("UUID").font(.caption).foregroundStyle(.secondary)
                Text(descriptor.characteristicCBUUID.uuidString)
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }

    private var typeText: String {
        var text = "\(descriptor.dataType)"
        if let width = descriptor.dataType.byteWidth { text += " (\(width) B)" }
        return text
    }

    // MARK: - Value

    private var valueSection: some View {
        Section {
            LabeledContent("Decoded") {
                Text(lastData.map { descriptor.dataType.interpreted($0, lsbUnit: descriptor.lsbUnit) } ?? "—")
                    .multilineTextAlignment(.trailing)
            }

            Picker("Format", selection: $format) {
                ForEach(GATTByteFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bytes").font(.caption).foregroundStyle(.secondary)
                Text(lastData.map { format.renderBytes($0) } ?? "—")
                    .font(.footnote.monospaced()).textSelection(.enabled)
            }

            if let integer = scalarInteger {
                LabeledContent("Integer", value: format.renderInteger(integer))
                    .font(.footnote.monospaced())
            }

            if let lastData {
                LabeledContent("Length", value: "\(lastData.count) B")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let lastUpdated {
                LabeledContent("Read") { Text(lastUpdated, style: .time) }
                    .font(.caption).foregroundStyle(.secondary)
            }

            if canRead {
                Button { Task { await read() } } label: {
                    Label("Read", systemImage: "arrow.clockwise")
                }
                .disabled(isReading)
            }
        } header: {
            Text("Value")
        }
    }

    /// The combined little-endian scalar value, when the type is a scalar integer.
    private var scalarInteger: UInt64? {
        guard let lastData else { return nil }
        return descriptor.dataType.unsignedScalar(lastData)
    }

    // MARK: - Notify

    private var notifySection: some View {
        Section {
            Toggle("Notifications", isOn: Binding(
                get: { isNotifying },
                set: { enabled in Task { await setNotify(enabled) } }
            ))
            LabeledContent("Received", value: "\(notifyCount)")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Notify")
        } footer: {
            Text("Streams live value updates. The decoded/bytes above refresh as they arrive.")
        }
    }

    // MARK: - Write

    private var writeSection: some View {
        Section {
            TextField(writePlaceholder, text: $writeText)
                .font(.body.monospaced())
                .keyboardType(writeUsesHex ? .asciiCapable : .numbersAndPunctuation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            Button { Task { await write() } } label: {
                Label("Write", systemImage: "square.and.pencil")
            }
            .disabled(encodedWriteData == nil || isWriting)
        } header: {
            Text("Write")
        } footer: {
            Text(writeFooter)
        }
    }

    private var writeUsesHex: Bool {
        switch descriptor.dataType {
        case .bytes, .utf8: true
        default: false
        }
    }

    private var writePlaceholder: String {
        switch descriptor.dataType {
        case .utf8: "Text"
        case .bytes: "Hex bytes (AABBCC)"
        case .unixTimeSeconds: "Epoch seconds"
        default: "Integer"
        }
    }

    private var writeFooter: String {
        switch descriptor.dataType {
        case .utf8: "Written as UTF-8 bytes."
        case .bytes: "Written as raw bytes parsed from hex."
        default: descriptor.dataType.byteWidth.map { "Written as a \($0)-byte little-endian value." }
            ?? "Written as a little-endian value."
        }
    }

    /// Encode the write field to `Data` per the catalogued type, or `nil` if the
    /// input is malformed / out of range.
    private var encodedWriteData: Data? {
        let text = writeText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        switch descriptor.dataType {
        case .utf8:
            return Data(text.utf8)
        case .bytes:
            return Self.hexData(text)
        default:
            guard let width = descriptor.dataType.byteWidth,
                  let value = UInt64(text) else { return nil }
            // Range-check against the field width.
            if width < 8, value >= (UInt64(1) << (width * 8)) { return nil }
            return Data((0 ..< width).map { UInt8((value >> (8 * $0)) & 0xFF) })
        }
    }

    private static func hexData(_ text: String) -> Data? {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    // MARK: - Transport actions

    private func read() async {
        isReading = true
        errorMessage = nil
        defer { isReading = false }
        do {
            let data: Data? = try await transport.read(
                characteristic: descriptor.characteristicCBUUID,
                ofService: service
            )
            lastData = data ?? Data()
            lastUpdated = Date()
        } catch {
            errorMessage = "Read failed: \(error.localizedDescription)"
        }
    }

    private func setNotify(_ enabled: Bool) async {
        errorMessage = nil
        do {
            try await transport.setNotify(
                enabled,
                characteristic: descriptor.characteristicCBUUID,
                ofService: service
            )
            isNotifying = enabled
            if enabled {
                let stream: AsyncStream<Data> = transport.notifications(
                    for: descriptor.characteristicCBUUID,
                    ofService: service
                )
                notifyTask = Task {
                    for await value in stream {
                        lastData = value
                        lastUpdated = Date()
                        notifyCount += 1
                    }
                }
            } else {
                notifyTask?.cancel()
                notifyTask = nil
            }
        } catch {
            errorMessage = "Notify toggle failed: \(error.localizedDescription)"
            isNotifying = false
        }
    }

    private func write() async {
        guard let data = encodedWriteData else { return }
        isWriting = true
        errorMessage = nil
        defer { isWriting = false }
        let type: CBCharacteristicWriteType =
            descriptor.properties.contains(.write) ? .withResponse : .withoutResponse
        do {
            try await transport.write(
                data,
                characteristic: descriptor.characteristicCBUUID,
                ofService: service,
                type: type
            )
            if canRead { await read() }
        } catch {
            errorMessage = "Write failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("RTC temperature (R/N)") {
        let transport = MockBluetoothTransport()
        transport.setReadValue(Int16(2537), for: DS3231CharacteristicUUID.rtcTemperature.cbuuid)
        return NavigationStack {
            CharacteristicDetailView(
                descriptor: CharacteristicCatalog
                    .descriptor(for: DS3231CharacteristicUUID.rtcTemperature.cbuuid)!,
                transport: transport
            )
        }
    }

    #Preview("Serial number (R/W)") {
        let transport = MockBluetoothTransport()
        transport.setReadValue(UInt32(0x0000_ABCD), for: SystemCharacteristicUUID.serialNumber.cbuuid)
        return NavigationStack {
            CharacteristicDetailView(
                descriptor: CharacteristicCatalog
                    .descriptor(for: SystemCharacteristicUUID.serialNumber.cbuuid)!,
                transport: transport
            )
        }
    }
#endif
