import BlithCore
import SwiftUI

// The horizon (Redesign 2): every score is a line from zero to its maximum with the person's usual
// drawn on it as a band. One shape replaces dials, rings and gauges.

extension Stats {
    /// The person's usual for a run of daily scores: the middle half (25th to 75th percentile).
    /// Nil until there are seven values with some spread.
    static func usualRange(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 7, let lo = percentile(values, 0.25), let hi = percentile(values, 0.75), hi > lo else { return nil }
        return lo...hi
    }
}

/// A 0 … 1 track with the person's usual as a translucent band, the value as a fill and, in the
/// regular style, an ink marker where the value lands. Without a value it shows the track and band only.
struct HorizonBar: View {
    enum Style { case regular, thin }

    /// 0 … 1, or nil while there is no value.
    let fraction: Double?
    /// The person's usual as fractions 0 … 1, when there is one.
    var usual: ClosedRange<Double>?
    var color: Color
    var style: Style = .regular
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var track: CGFloat { style == .regular ? 14 : 8 }
    var height: CGFloat { style == .regular ? 26 : 16 }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken).frame(height: track)
                if let usual {
                    let lo = Self.clamp(usual.lowerBound)
                    let hi = max(lo, Self.clamp(usual.upperBound))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.usualBand)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.signal.opacity(0.45), lineWidth: 1))
                        .frame(width: max(4, w * (hi - lo)), height: track + 8)
                        .offset(x: min(w * lo, max(0, w - 4)))
                }
                if fraction != nil {
                    Capsule().fill(color).frame(width: w * shown, height: track)
                    if style == .regular {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Palette.ink)
                            .frame(width: 4, height: height)
                            .offset(x: min(max(0, w * shown - 2), max(0, w - 4)))
                    }
                }
            }
            .frame(width: w, height: g.size.height)
        }
        .frame(height: height)
        .onAppear { withAnimation(Motion.respecting(reduceMotion, Motion.reveal)) { shown = Self.clamp(fraction ?? 0) } }
        .onChange(of: fraction) { _, f in withAnimation(Motion.respecting(reduceMotion)) { shown = Self.clamp(f ?? 0) } }
        .accessibilityHidden(true)
    }

    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// A status said twice, as a glyph and in words, in one colour. Never colour alone.
struct StatusLabel: View {
    let symbol: String
    let text: String
    var color: Color = Palette.secondaryInk

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .imageScale(.small)
            Text(text)
                .font(Typo.geist(13, .semibold, relativeTo: .footnote))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The mark for a reading outside the person's usual: a ring in rust (`Palette.note`). A neutral ring
/// marks anything else worth a look.
struct RingGlyph: View {
    var color: Color = Palette.note

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2.5)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}
