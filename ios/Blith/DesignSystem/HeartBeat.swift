import BlithCore
import Foundation
import SwiftUI

// MARK: - Beat timing
//
// One rule holds this file together: the animation period *is* the heart period. At 48 bpm the
// heart pounds 48 times a minute; at 150 bpm it pounds 150 times. Nothing is eyeballed, so the
// motion is a reading of the data rather than decoration on top of it.

enum Beat {
    /// Phase 0 … 1 through the current cardiac cycle for a given rate.
    /// Driven off absolute time so every heart on screen stays in step.
    static func phase(_ date: Date, interval: TimeInterval) -> Double {
        guard interval > 0 else { return 0 }
        let beats = date.timeIntervalSinceReferenceDate / interval
        return beats - beats.rounded(.down)
    }

    /// A gaussian bump — the building block of both the thump and the ECG trace.
    private static func bump(_ phase: Double, _ center: Double, _ width: Double, _ amplitude: Double = 1) -> Double {
        let d = (phase - center) / width
        return amplitude * exp(-d * d)
    }

    /// The lub-dub envelope, 0 … ~1: a strong first thump (ventricles contracting) and a softer
    /// second one a third of a cycle later. A single sine would read as a throb, not a heartbeat.
    static func thump(_ phase: Double) -> Double {
        bump(phase, 0.08, 0.075) + 0.5 * bump(phase, 0.30, 0.070)
    }

    /// A classic PQRST complex over one cycle, −0.35 … 1.
    static func ecg(_ phase: Double) -> Double {
        bump(phase, 0.16, 0.030, 0.13)      // P — atria
            + bump(phase, 0.300, 0.008, -0.22) // Q
            + bump(phase, 0.335, 0.010, 1.00)  // R — the spike
            + bump(phase, 0.375, 0.012, -0.34) // S
            + bump(phase, 0.560, 0.055, 0.26)  // T — recovery
    }

    /// Calm breathing for when there is no pulse to show: ~10 breaths a minute.
    static func idle(_ date: Date) -> Double {
        (sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 6) + 1) / 2
    }
}

/// A heart that pounds at the person's real pulse, with a shockwave ring on each beat.
/// With Reduce Motion on it holds still and the number carries the rate instead.
struct PoundingHeart: View {
    var bpm: Double?
    var tint: Color = Palette.heart
    var size: CGFloat = 56
    /// Rings that expand outward on every beat. Off for small, inline hearts.
    var shockwave = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interval: TimeInterval { 60 / min(max(bpm ?? 60, 30), 220) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let live = bpm != nil
            let phase = Beat.phase(timeline.date, interval: interval)
            let t = reduceMotion ? 0.35 : (live ? Beat.thump(phase) : Beat.idle(timeline.date) * 0.6)
            ZStack {
                if shockwave && !reduceMotion && live {
                    // Two rings, half a cycle apart, fading as they travel.
                    ring(phase)
                    ring(phase < 0.5 ? phase + 0.5 : phase - 0.5)
                }
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.35 * t + 0.10), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.75))
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.55 * t), radius: size * 0.18 * t)
                    // A heart contracts more than it relaxes: 1.0 → 1.16.
                    .scaleEffect(1 + 0.16 * t)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func ring(_ phase: Double) -> some View {
        // Rings only appear on the beat and vanish before the next one.
        let travel = min(1, phase / 0.62)
        return Circle()
            .strokeBorder(tint.opacity(0.42 * (1 - travel)), lineWidth: max(1, size * 0.03))
            .scaleEffect(0.52 + travel * 0.62)
    }
}

/// A live ECG trace that scrolls at the pulse rate: the spacing between spikes is the real
/// beat-to-beat interval, so a fast pulse visibly crowds the line.
struct ECGTrace: View {
    var bpm: Double?
    var tint: Color = Palette.heart
    /// How many beats fit across the width. Fewer = a wider, calmer trace.
    var beatsAcross: Double = 3.2
    var lineWidth: CGFloat = 2
    /// Fade the left edge so the line appears to come out of nowhere.
    var fadeIn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interval: TimeInterval { 60 / min(max(bpm ?? 60, 30), 220) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                let mid = size.height * 0.62
                let amp = size.height * 0.46
                // Reduce Motion freezes the trace at a phase where a full complex is visible.
                let scroll = reduceMotion ? 0.35 : Beat.phase(timeline.date, interval: interval)
                var path = Path()
                let steps = max(60, Int(size.width))
                for i in 0...steps {
                    let x = size.width * Double(i) / Double(steps)
                    let cycles = (x / size.width) * beatsAcross + scroll
                    let y = mid - Beat.ecg(cycles - cycles.rounded(.down)) * amp
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                var shading = GraphicsContext.Shading.color(tint)
                if fadeIn {
                    shading = .linearGradient(Gradient(colors: [tint.opacity(0), tint.opacity(0.55), tint]),
                                              startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                }
                ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A heart drawn as a real curve rather than a glyph: wide round lobes, a soft cleft and a blunt
/// tip. The right half is defined and the left is mirrored, so it is always perfectly symmetric.
struct HeartShape: Shape {
    /// Height as a fraction of width — the heart is slightly wider than it is tall.
    static let aspect: CGFloat = 0.96
    static let tip = CGPoint(x: 0.5, y: 0.955)
    /// Right half, bottom tip → outer lobe → into the centre cleft. (control1, control2, end)
    ///
    /// The last control point sits well to the right of the cleft on purpose: it makes the tangent
    /// there nearly horizontal, so the two halves meet as a rounded U instead of a sharp notch.
    static let segments: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 0.640, y: 0.915), CGPoint(x: 1.000, y: 0.645), CGPoint(x: 1.000, y: 0.330)),
        (CGPoint(x: 1.000, y: 0.070), CGPoint(x: 0.780, y: -0.035), CGPoint(x: 0.615, y: 0.032)),
        (CGPoint(x: 0.556, y: 0.078), CGPoint(x: 0.560, y: 0.235), CGPoint(x: 0.500, y: 0.285)),
    ]

    func path(in rect: CGRect) -> Path {
        let w = min(rect.width, rect.height / Self.aspect)
        let h = w * Self.aspect
        let x = rect.midX - w / 2
        let y = rect.midY - h / 2
        func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: x + pt.x * w, y: y + pt.y * h) }
        func mirror(_ pt: CGPoint) -> CGPoint { CGPoint(x: x + (1 - pt.x) * w, y: y + pt.y * h) }

        var path = Path()
        path.move(to: p(Self.tip))
        for s in Self.segments {
            path.addCurve(to: p(s.2), control1: p(s.0), control2: p(s.1))
        }
        for i in Self.segments.indices.reversed() {
            let s = Self.segments[i]
            let end = i == 0 ? mirror(Self.tip) : mirror(Self.segments[i - 1].2)
            path.addCurve(to: end, control1: mirror(s.1), control2: mirror(s.0))
        }
        path.closeSubpath()
        return path
    }
}

/// The hero heart: a soft, inflated body with a broad gloss over the upper half, a darkened rim
/// that gives it volume, bounce light along the bottom, and the rate read inside it.
///
/// It pounds on the same envelope as `PoundingHeart` — the body swells, the glow flares and the
/// rim light sharpens on each beat, so the whole object breathes rather than just scaling.
struct GlossyHeart: View {
    var bpm: Double?
    /// Shown inside the heart. Usually the rate.
    var value: String?
    var caption: String?
    var size: CGFloat = 220
    /// Base body colour; the gradient is derived from it.
    var body_: Color = Color(hex: 0xF76C76)
    var highlight: Color = Color(hex: 0xFF838A)
    var shade: Color = Color(hex: 0xE24A5C)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interval: TimeInterval { 60 / min(max(bpm ?? 60, 30), 220) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let live = bpm != nil
            let k = reduceMotion ? 0.3 : (live ? Beat.thump(Beat.phase(timeline.date, interval: interval))
                                               : Beat.idle(timeline.date) * 0.5)
            ZStack {
                HeartShape()
                    .fill(LinearGradient(colors: [highlight, body_, shade], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // Rim darkening: transparent through most of the body, deep only at the edge.
                        HeartShape().fill(
                            RadialGradient(gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.80),
                                .init(color: Color(hex: 0x8C142D, opacity: 0.38), location: 1),
                            ]), center: UnitPoint(x: 0.5, y: 0.48), startRadius: size * 0.14, endRadius: size * 0.60))
                    }
                    .overlay {
                        // One broad specular sweep, not a tight dot — this is what reads as "soft".
                        HeartShape().fill(
                            RadialGradient(gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.48), location: 0),
                                .init(color: .white.opacity(0.22 + 0.08 * k), location: 0.35),
                                .init(color: .white.opacity(0.04), location: 0.72),
                                .init(color: .white.opacity(0), location: 1),
                            ]), center: UnitPoint(x: 0.44, y: 0.16), startRadius: 0, endRadius: size * 0.58))
                    }
                    .overlay {
                        // Bounce light off the bottom, so the tip doesn't go flat.
                        HeartShape().fill(
                            RadialGradient(gradient: Gradient(stops: [
                                .init(color: Color(hex: 0xFFBEC8, opacity: 0.20), location: 0),
                                .init(color: Color(hex: 0xFFBEC8, opacity: 0), location: 1),
                            ]), center: UnitPoint(x: 0.5, y: 0.93), startRadius: 0, endRadius: size * 0.32))
                    }
                    .shadow(color: body_.opacity(0.30 + 0.35 * k), radius: size * (0.07 + 0.05 * k))
                    .scaleEffect(1 + 0.055 * k)

                if value != nil || caption != nil {
                    VStack(spacing: 0) {
                        if let value {
                            Text(value)
                                .font(Typo.geist(size * 0.25, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .shadow(color: Color(hex: 0x7A0A1E, opacity: 0.30), radius: size * 0.04)
                                .contentTransition(.numericText())
                        }
                        if let caption {
                            Text(caption.uppercased())
                                .font(Typo.mono(max(9, size * 0.05), .medium))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .offset(y: size * 0.09)
                }
            }
            .frame(width: size, height: size * HeartShape.aspect)
        }
        .accessibilityHidden(true)
    }
}

extension HeartRatePulse {
    var spokenLabel: String {
        "Heart rate \(Int(bpm.rounded())) beats per minute, \(zone.label.lowercased()). \(summary)"
    }
}

// MARK: - Zone colour

extension HeartRateZone {
    /// A warmth ramp that stays inside the Blith palette: calm teal at rest through to coral at
    /// peak. Colour never carries the zone alone — the label and glyph always travel with it.
    var tint: Color {
        switch self {
        case .resting: Palette.recovery
        case .light: Palette.cyan
        case .moderate: Palette.signal
        case .vigorous: Palette.note
        case .peak: Palette.heart
        }
    }
}
