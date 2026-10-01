import BlithCore
import SwiftUI

// The cards Today is built from. Each is one VoiceOver element with a spoken summary.

/// Readiness on the horizon: the band as a glyph and a word, a calm numeral, the 0–100 line with the
/// person's usual drawn on it, BlithCore's sentence, and the way into what's behind the score.
struct ReadinessHorizonCard: View {
    let score: Int
    let band: ScoreBand
    /// The middle half of the person's recent readiness scores (0 … 100), once there are enough.
    let usual: ClosedRange<Double>?
    let summary: String
    let onWhy: () -> Void

    var body: some View {
        Button(action: onWhy) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow(text: "Readiness")
                    Spacer(minLength: Space.s)
                    StatusLabel(symbol: Palette.bandSymbol(band), text: band.label, color: statusColor)
                }
                HStack(alignment: .center, spacing: Space.l) {
                    Text("\(score)")
                        .font(Typo.score(64))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                        .fixedSize()
                    VStack(spacing: Space.s + 2) {
                        HorizonBar(fraction: Double(score) / 100,
                                   usual: usual.map { ($0.lowerBound / 100)...($0.upperBound / 100) },
                                   color: Palette.band(band))
                        HStack {
                            Text("0")
                            Spacer(minLength: Space.xs)
                            if let usual {
                                Text("usual \(Fmt.int(usual.lowerBound))–\(Fmt.int(usual.upperBound))")
                            }
                            Spacer(minLength: Space.xs)
                            Text("100")
                        }
                        .font(Typo.eyebrow)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
                Text(summary)
                    .font(Typo.geist(17, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Palette.separator).frame(height: 1)
                HStack {
                    Text("What's behind this score")
                        .font(Typo.geist(15, .medium, relativeTo: .subheadline))
                    Spacer(minLength: Space.s)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.signal)
            }
            .card(padding: Space.l)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint("Shows what's behind this score")
    }

    /// High reads in its band colour. Moderate and Low sit low on the luminance ramp and would fail
    /// contrast as words, so they use secondary ink; the horizon still carries the band colour.
    var statusColor: Color { band == .high ? Palette.band(band) : Palette.secondaryInk }

    var spoken: String {
        var parts = ["Readiness \(score), \(band.label.lowercased())"]
        if let usual {
            parts.append("Your usual is \(Fmt.int(usual.lowerBound)) to \(Fmt.int(usual.upperBound))")
        }
        parts.append(summary)
        return parts.joined(separator: ". ")
    }
}

/// Readiness while Blith learns the person's usual: the nights it has, out of the 14 it needs.
struct CalibrationCard: View {
    let nights: Int

    var body: some View {
        let total = ScoreEngine.calibrationDays
        let n = min(max(nights, 0), total)
        let title = n == 0 ? "0 of \(total) nights" : "Night \(n) of \(total)"
        let copy = "Readiness starts once Blith knows your usual. Keep wearing your Watch to bed."
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Eyebrow(text: "Readiness")
                Spacer(minLength: Space.s)
                StatusLabel(symbol: Palette.bandSymbol(nil), text: "Learning your usual", color: Palette.secondaryInk)
            }
            Text(title)
                .font(Typo.title)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            SegmentedProgress(total: total, done: n, color: Palette.signal)
            Text(copy)
                .font(Typo.geist(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness, learning your usual. \(title). \(copy)")
    }
}

/// Without overnight heart data, movement leads Today: steps so far against the usual by this time,
/// with the person's usual day drawn behind today's line.
struct MovementHeroCard: View {
    /// Steps so far today; nil when nothing has been recorded yet.
    let steps: Double?
    let pace: TodayPace?
    /// The time of day the comparison is made at, e.g. "15:30".
    let time: String
    /// "Tuesday", or "typical day" when the usual comes from recent days rather than the same weekday.
    let dayName: String
    let onOpen: () -> Void

    var body: some View {
        let status = PaceStatus(pace)
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow(text: "Movement by \(time)")
                    Spacer(minLength: Space.s)
                    if let status {
                        StatusLabel(symbol: status.symbol, text: status.text, color: status.color)
                    }
                }
                if let steps {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(Fmt.int(steps))
                            .font(Typo.score(64))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("steps")
                            .font(Typo.geist(17, .medium, relativeTo: .headline))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("No steps yet today")
                        .font(Typo.title)
                        .foregroundStyle(Palette.ink)
                }
                if let pace, !pace.usualCurve.isEmpty {
                    AccumulationChart(pace: pace, compact: true).frame(height: 128)
                }
                if let usual = pace?.usualByNow {
                    Text("Usually \(Fmt.int(usual)) by \(time) on a \(dayName).")
                        .font(Typo.geist(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: Space.l)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken(status))
        .accessibilityHint("Opens today's activity")
    }

    func spoken(_ status: PaceStatus?) -> String {
        var parts = ["Movement by \(time)"]
        parts.append(steps.map { "\(Fmt.int($0)) steps" } ?? "No steps yet today")
        if let usual = pace?.usualByNow { parts.append("Usually \(Fmt.int(usual)) by now") }
        if let status { parts.append(status.text) }
        return parts.joined(separator: ". ")
    }
}

/// A supporting score beside another: a mono label, a calm numeral, a thin horizon with the usual and
/// one line of context. The whole tile opens the score's tab.
struct ScoreTile: View {
    let title: String
    let value: String
    /// 0 … 1 along the horizon.
    let fraction: Double?
    /// The usual as fractions 0 … 1.
    let usual: ClosedRange<Double>?
    let caption: String
    let summary: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s + 2) {
                Eyebrow(text: title)
                Text(value)
                    .font(Typo.score(34))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HorizonBar(fraction: fraction, usual: usual, color: Palette.signal, style: .thin)
                Text(caption)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .card(padding: Space.l)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary)
        .accessibilityHint(hint)
    }
}

/// A row in a Today list: an optional ring, a title with a detail line or a status, an optional
/// value and a chevron. The whole row is one button and one VoiceOver element.
struct TodayRow: View {
    let title: String
    var detail: String?
    var status: StatusLabel?
    var value: String?
    /// Rust (`Palette.note`) for a reading outside the usual; neutral for anything else worth a look.
    var ring: Color?
    /// What VoiceOver says; built from the visible parts when nil.
    var summary: String?
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.m) {
                if let ring { RingGlyph(color: ring) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typo.geist(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let status { status }
                    if let detail {
                        Text(detail)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.s)
                if let value {
                    Text(value)
                        .font(Typo.number(15))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.vertical, Space.m - 2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint(hint)
    }

    var spoken: String {
        if let summary { return summary }
        let parts: [String?] = [title, value, status?.text, detail]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }
}
