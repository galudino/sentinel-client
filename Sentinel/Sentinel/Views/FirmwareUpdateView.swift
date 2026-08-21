//
//  FirmwareUpdateView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// The OTA DFU escape hatch (#21) — one full-screen view that deliberately leaves
/// `MainTabView` (no tab bar, no back) while firmware uploads. Austere on purpose,
/// like the iOS Settings app mid-software-update: the device is updating and
/// everything else is paused.
///
/// It is pure presentation over the ``OTAUploader`` state machine (#22): the
/// progress ring and phase text render `uploader.state` / `uploader.progressFraction`
/// directly, and the Cancel button follows the same point-of-no-return rule the
/// engine enforces — cancellable through `.uploading`, disabled from `.validating`
/// on. On success the uploader has already reconnected to the rebooted device and
/// read its new version back; "Done" swaps the router onto that fresh connection.
struct FirmwareUpdateView: View {
    let peer: ConnectedPeer
    let image: FirmwareImage

    @Environment(AppRouter.self) private var router

    @State private var uploader: OTAUploader?
    @State private var reconnector: CentralFirmwareReconnector?
    @State private var showCancelConfirmation = false

    /// Previews inject a frozen uploader and set this so the `.task` skips the real
    /// `start(image:)` (the simulator has no BLE).
    private let isPreview: Bool

    init(peer: ConnectedPeer, image: FirmwareImage) {
        self.peer = peer
        self.image = image
        isPreview = false
    }

    private var state: OTAUploader.State { uploader?.state ?? .idle }
    private var progress: Double { uploader?.progressFraction ?? 0 }

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            progressRing
            Text(state.userFacingMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
            statusFootnote
            Spacer()
            actionButtons
        }
        .padding()
        .animation(.smooth, value: state)
        .task {
            guard !isPreview, uploader == nil else { return }
            let reconnector = CentralFirmwareReconnector(
                central: router.bluetoothManager,
                peripheralID: peer.id,
                name: peer.name
            )
            let uploader = OTAUploader(
                ota: peer.ota,
                system: peer.system,
                mtu: peer.negotiatedMTU,
                reconnector: reconnector
            )
            self.reconnector = reconnector
            self.uploader = uploader
            uploader.start(image: image)
        }
        .confirmationDialog(
            "Cancel firmware update?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel update", role: .destructive) {
                Task {
                    await uploader?.cancel()
                    router.cancelFirmwareUpdate()
                }
            }
            Button("Keep updating", role: .cancel) {}
        } message: {
            Text("Cancelling will leave the device on its current firmware. The partial upload will be discarded.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text(peer.name ?? "Sentinel device")
                .font(.headline)
            Text("Updating to v\(image.versionDisplay)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            ringLabel
        }
        .frame(width: 200, height: 200)
    }

    @ViewBuilder private var ringLabel: some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.red)
        case .uploading:
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        default:
            ProgressView()
                .controlSize(.large)
        }
    }

    private var ringColor: Color {
        switch state {
        case .complete: .green
        case .failed: .red
        default: .accentColor
        }
    }

    @ViewBuilder private var statusFootnote: some View {
        switch state {
        case let .failed(reason):
            Text(reason)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        case .validating, .restarting, .reconnecting, .verifying:
            Text("Please wait — do not disconnect the device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var actionButtons: some View {
        switch state {
        case .complete:
            Button("Done") {
                if let reconnectedPeer = reconnector?.reconnectedPeer {
                    router.firmwareUpdateReconnected(peer: reconnectedPeer)
                } else {
                    router.firmwareUpdateCompleted()
                }
            }
            .buttonStyle(.borderedProminent)

        case .failed:
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) {
                    router.cancelFirmwareUpdate()
                }
                Button("Try again") {
                    uploader?.start(image: image)
                }
                .buttonStyle(.borderedProminent)
            }

        default:
            // Cancellable through `.uploading`; from `.validating` on the button
            // is disabled — the device is committing and rebooting.
            Button("Cancel", role: .destructive) {
                showCancelConfirmation = true
            }
            .disabled(!state.isCancellable)
        }
    }
}

// MARK: - Previews

#if DEBUG
    extension FirmwareUpdateView {
        /// Preview initializer — injects a frozen ``OTAUploader`` phase and skips the
        /// live `start(image:)`.
        init(peer: ConnectedPeer, image: FirmwareImage, previewUploader: OTAUploader) {
            self.peer = peer
            self.image = image
            _uploader = State(initialValue: previewUploader)
            isPreview = true
        }
    }

    private func previewView(_ state: OTAUploader.State, progress: Double = 0) -> some View {
        FirmwareUpdateView(
            peer: ConnectedPeer(name: "Sentinel"),
            image: FirmwareImage(version: "1.1.0"),
            previewUploader: .preview(state, progress: progress)
        )
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
    }

    #Preview("Uploading") { previewView(.uploading(chunkIndex: 112, totalChunks: 256), progress: 0.44) }
    #Preview("Validating") { previewView(.validating, progress: 1) }
    #Preview("Reconnecting") { previewView(.reconnecting, progress: 1) }
    #Preview("Complete") { previewView(.complete, progress: 1) }
    #Preview("Failed") { previewView(.failed("The device rejected the update: Image verification failed.")) }
#endif
