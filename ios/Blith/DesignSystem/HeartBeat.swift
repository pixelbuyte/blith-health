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

/// The beat-to-beat reading as words, for VoiceOver and for the "what am I looking at" line.
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
