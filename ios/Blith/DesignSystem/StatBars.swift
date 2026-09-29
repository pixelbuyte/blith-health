import BlithCore
import SwiftUI

// MARK: - Stat bars
//
// A row of short, self-contained cards instead of one tall stacked block. Each bar is one signal
// read at a glance: a small piece of live evidence on the left, then what it is and what it says.
//
// Why a row and not a column: the top of the home screen has one hero (the pulse). Everything else
// is context, and context should cost one line of height, not five. A bar is also honest about not
// knowing — `.waiting` keeps the card at full size and says what unlocks it, so the screen never
// shows an empty instrument.

/// The evidence on the left of a bar. Each case is a different *kind* of measurement, never just a
/// different colour — the shape itself says whether this is a trend, a score, a count or a pulse.
enum BarEvidence {
    /// A short history: the last few days, latest on the right.
    case bars([Double], Color)
    /// A 0…1 score, drawn as a ring with the value inside it.
    case ring(Double, String, Color)
    /// A plain count or reading.
    case glyph(String, Color)
    /// The live pulse, beating at `bpm`.
    case pulse(Double?, Color)
    /// Nothing measured yet.
    case waiting(String)
}

/// A few days of a signal as tiny bars, latest at the right and brightest — so the eye lands on
/// today and reads backwards for the trend.
struct MiniBars: View {
    var values: [Double]
    var tint: Color
    var height: CGFloat = 26

    var body: some View {
        let peak = max(values.max() ?? 1, 0.0001)
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let isLatest = i == values.count - 1
                Capsule()
                    // A floor of 0.18 keeps a near-zero day visible as a mark rather than a gap.
                    .fill(tint.opacity(isLatest ? 1 : 0.34))
                    .frame(width: 3.5, height: max(3, height * (0.18 + 0.82 * v / peak)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// A score as a ring. The gap in the ring is the part not earned, which reads faster than a number
/// alone and does not depend on colour.
struct MiniRing: View {
    var fraction: Double
    var label: String
    var tint: Color
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().stroke(Palette.sunken, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(Typo.number(size * 0.35, weight: .medium))
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One bar: evidence, then the name of the signal, then what it currently says.
struct StatBar: View {
    var evidence: BarEvidence
    var title: String
    var value: String
    /// The one-line reading under the value. Kept to a few words so the bar stays one line tall.
    var caption: String?
    var tint: Color = Palette.signal
    /// Match the surrounding design rather than the default card.
    var surface: AnyShapeStyle = AnyShapeStyle(Palette.surface)
    var border: Color = Palette.hairline
    var width: CGFloat = 132

    private var isWaiting: Bool { if case .waiting = evidence { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 0)
            }
            .frame(height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(Typo.mono(9.5, .medium))
                    .tracking(0.9)
                    .foregroundStyle(isWaiting ? Palette.tertiaryInk : tint)
                Text(value)
                    .font(Typo.number(17, weight: .medium))
                    .foregroundStyle(isWaiting ? Palette.tertiaryInk : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(Typo.geist(10.5, relativeTo: .caption2))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(caption.map { ". \($0)" } ?? "")")
    }

    @ViewBuilder private var leading: some View {
        switch evidence {
        case .bars(let values, let color):
            MiniBars(values: values, tint: color)
        case .ring(let fraction, let label, let color):
            MiniRing(fraction: fraction, label: label, tint: color)
        case .glyph(let name, let color):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(0.14)))
        case .pulse(let bpm, let color):
            PoundingHeart(bpm: bpm, tint: color, size: 34, shockwave: false)
        case .waiting(let name):
            // Waiting has a shape of its own — a dashed ring — so it never looks like a zero.
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 32, height: 32)
                .background(Circle().strokeBorder(Palette.quiet,
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
    }
}

/// The bars as a row. It scrolls rather than squeezing: four narrow cards beat three cramped ones,
/// and the cut-off fourth is what tells you to swipe.
struct SummaryBars<Content: View>: View {
    var inset: CGFloat = Space.page
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) { content }
                .padding(.horizontal, inset)
        }
        .scrollIndicators(.hidden)
        // The row is the full bleed of the screen, so cards can run off the edge.
        .padding(.horizontal, -inset)
    }
}

#Preview("Stat bars") {
    VStack(alignment: .leading, spacing: Space.l) {
        SummaryBars {
            StatBar(evidence: .pulse(78, Palette.heart), title: "Pulse", value: "78 bpm",
                    caption: "24 over resting", tint: Palette.heart)
            StatBar(evidence: .ring(0.69, "69", Palette.signal), title: "Sleep", value: "6h 52m",
                    caption: "usual 7h 10m", tint: Palette.signal)
            StatBar(evidence: .bars([0.4, 0.8, 0.5, 0.9, 0.3, 0.7, 1.0], Palette.cyan), title: "Load",
                    value: "1.2", caption: "usual 1.9–3.7", tint: Palette.cyan)
            StatBar(evidence: .glyph("figure.walk", Palette.recovery), title: "Steps", value: "2,657",
                    caption: "so far today", tint: Palette.recovery)
            StatBar(evidence: .waiting("moon.zzz"), title: "HRV", value: "–", caption: "after 1st night")
        }
    }
    .padding(.vertical, Space.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .blithBackground()
}
