//
//  AnalogClockView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/20/26.
//

import SwiftUI

/// A self-contained analog clock face drawn for a given `date`. It renders a
/// single instant — to make it **tick**, drive it from a `TimelineView` and feed
/// the timeline's date (optionally offset onto the device clock). Home does this,
/// with one timeline feeding both the face and the date/time text.
///
/// Pure drawing (SwiftUI `Canvas`), no state, so it previews and composes freely.
struct AnalogClockView: View {
    let date: Date
    var handColor: Color = .primary
    var secondHandColor: Color = .orange

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            drawFace(context, center: center, radius: radius)
            drawTicks(context, center: center, radius: radius)
            drawHands(context, center: center, radius: radius)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Analog clock")
        .accessibilityValue(date.formatted(date: .omitted, time: .shortened))
    }

    // MARK: - Drawing

    private func drawFace(_ context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let inset = radius - 1
        let faceRect = CGRect(x: center.x - inset, y: center.y - inset, width: inset * 2, height: inset * 2)
        context.stroke(Circle().path(in: faceRect), with: .color(.secondary.opacity(0.4)), lineWidth: 2)
    }

    private func drawTicks(_ context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for tick in 0 ..< 12 {
            let angle = Double(tick) / 12 * 2 * .pi
            let outer = point(from: center, radius: radius * 0.92, angle: angle)
            let inner = point(from: center, radius: radius * 0.80, angle: angle)
            var tickPath = Path()
            tickPath.move(to: inner)
            tickPath.addLine(to: outer)
            context.stroke(tickPath, with: .color(.secondary.opacity(0.6)), lineWidth: tick % 3 == 0 ? 2 : 1)
        }
    }

    private func drawHands(_ context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: date).quotientAndRemainder(dividingBy: 12).remainder)
        let minute = Double(calendar.component(.minute, from: date))
        let second = Double(calendar.component(.second, from: date))

        let hourAngle = (hour + minute / 60) / 12 * 2 * .pi
        let minuteAngle = (minute + second / 60) / 60 * 2 * .pi
        let secondAngle = second / 60 * 2 * .pi

        let hourHand = Hand(
            tip: point(from: center, radius: radius * 0.50, angle: hourAngle),
            width: 3,
            color: handColor
        )
        let minuteHand = Hand(
            tip: point(from: center, radius: radius * 0.72, angle: minuteAngle),
            width: 2,
            color: handColor
        )
        let secondHand = Hand(
            tip: point(from: center, radius: radius * 0.84, angle: secondAngle),
            width: 1,
            color: secondHandColor
        )
        for hand in [hourHand, minuteHand, secondHand] {
            drawHand(context, from: center, hand: hand)
        }

        let hubRect = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
        context.fill(Circle().path(in: hubRect), with: .color(handColor))
    }

    /// A single clock hand: its tip point + stroke chrome.
    private struct Hand {
        let tip: CGPoint
        let width: CGFloat
        let color: Color
    }

    private func drawHand(_ context: GraphicsContext, from center: CGPoint, hand: Hand) {
        var handPath = Path()
        handPath.move(to: center)
        handPath.addLine(to: hand.tip)
        context.stroke(handPath, with: .color(hand.color), style: StrokeStyle(lineWidth: hand.width, lineCap: .round))
    }

    /// A point on a circle, `angle` measured **clockwise from 12 o'clock**.
    private func point(from center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Ticking clock") {
        // Drive it from a TimelineView to make the hands tick — the same pattern
        // Home uses (one timeline feeds both the face and the date/time text).
        TimelineView(.periodic(from: .now, by: 1)) { context in
            AnalogClockView(date: context.date)
        }
        .frame(width: 120, height: 120)
        .padding()
    }
#endif
