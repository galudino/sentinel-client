//
//  SplashView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/13/26.
//

import SwiftUI

/// The first view shown on app launch. A brief brand moment that also covers
/// cold-start initialization before the app transitions into its main flow.
///
/// The mark is `sensor.fill` — the same glyph as the app icon — animated with a
/// variable-color "ping" pulse so the symbol's concentric signal arcs light up
/// outward like a live sensor broadcast. See issue #26 for the full spec.
///
/// `onComplete` fires once, after the fade-out finishes. The parent scene swaps
/// this view out for the app's root once it fires (see `SentinelApp`). The
/// duration is fixed and does not gate on real readiness checks — those complete
/// well before the splash finishes.
struct SplashView: View {
    let onComplete: () -> Void

    @State private var symbolScale: CGFloat = 0.8
    @State private var symbolOpacity: Double = 0.0
    @State private var isPulsing = false
    @State private var rootOpacity: Double = 1.0

    private let easeInDuration: Double = 0.6 // scale + opacity
    private let pulseDuration: Double = 1.6 // variable-color pulse visible window
    private let fadeOutDuration: Double = 0.4

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            Image(systemName: "sensor.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers.nonReversing,
                    options: .repeating,
                    isActive: isPulsing
                )
                .frame(width: 120, height: 120)
                .scaleEffect(symbolScale)
                .opacity(symbolOpacity)
        }
        .opacity(rootOpacity)
        .task { await runSequence() }
    }

    private func runSequence() async {
        // 1. Ease in (scale + opacity), then start the pulse.
        withAnimation(.easeOut(duration: easeInDuration)) {
            symbolScale = 1.0
            symbolOpacity = 1.0
        }
        isPulsing = true

        // 2. Let the variable-color pulse play for the splash's visible window.
        try? await Task.sleep(for: .seconds(pulseDuration))

        // 3. Cross-fade out.
        withAnimation(.easeIn(duration: fadeOutDuration)) {
            rootOpacity = 0.0
        }
        try? await Task.sleep(for: .seconds(fadeOutDuration))

        isPulsing = false // stop the effect — no retained animation after completion
        onComplete()
    }
}

#Preview {
    SplashView(onComplete: {})
}
