import BlithCore
import SwiftUI

// Instrument components: dials, meters, range bars, strips and heatmaps.

/// A 300° gauge with tick marks, a glowing gradient arc and a condensed numeral.
struct ScoreDial: View {
    /// 0 … 1, or nil while there is no value.
    let fraction: Double?
    let valueText: String
    var unit: String?
    let label: String
    var color: Color
    var size: CGFloat = 108
    /// Optional "usual" band drawn under the arc (fractions 0 … 1).
    var usual: ClosedRange<Double>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    static let sweep = 300.0
    var lineWidth: CGFloat { max(5, size * 0.075) }

    var body: some View {
        ZStack {
            ticks
            arc(0, 1).stroke(Palette.raised, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let usual {
                arc(usual.lowerBound, usual.upperBound)
                    .stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            if fraction != nil {
                arc(0, max(0.001, shown))
                    .stroke(AngularGradient(colors: [color.opacity(0.45), color], center: .center,
                                            startAngle: .degrees(90 + (360 - Self.sweep) / 2),
                                            endAngle: .degrees(90 + (360 - Self.sweep) / 2 + Self.sweep)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: color.opacity(0.55), radius: size * 0.06)
                knob
            }
            VStack(spacing: -2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(valueText).font(Typo.score(size * 0.34)).foregroundStyle(fraction == nil ? Palette.secondaryInk : Palette.ink)
                        .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    if let unit { Text(unit).font(Typo.number(size * 0.13, weight: .medium)).foregroundStyle(Palette.secondaryInk) }
                }
                Text(label.uppercased()).font(.system(size: max(8, size * 0.085), weight: .medium, design: .monospaced))
                    .tracking(1).foregroundStyle(color.opacity(fraction == nil ? 0.6 : 1))
            }
            .padding(.horizontal, size * 0.16)
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(Motion.respecting(reduceMotion, Motion.reveal)) { shown = fraction ?? 0 } }
        .onChange(of: fraction) { _, f in withAnimation(Motion.respecting(reduceMotion)) { shown = f ?? 0 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(valueText)\(unit ?? "")")
    }

    func angle(_ f: Double) -> Angle { .degrees(90 + (360 - Self.sweep) / 2 + Self.sweep * f) }

    func arc(_ a: Double, _ b: Double) -> Path {
        Path { p in
            let r = size / 2 - lineWidth / 2 - size * 0.07
            p.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: r, startAngle: angle(a), endAngle: angle(b), clockwise: false)
        }
    }

    var ticks: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let outer = sz.width / 2
            for i in 0...30 {
                let f = Double(i) / 30
                let a = angle(f).radians
                let long = i % 5 == 0
                let inner = outer - (long ? size * 0.05 : size * 0.028)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                ctx.stroke(p, with: .color(f <= shown && fraction != nil ? color.opacity(0.7) : Palette.hairline.opacity(long ? 2.2 : 1.4)), lineWidth: 1)
            }
        }
    }

    var knob: some View {
        let r = size / 2 - lineWidth / 2 - size * 0.07
        let a = angle(shown).radians
        return Circle().fill(Palette.ink)
            .frame(width: lineWidth * 0.8, height: lineWidth * 0.8)
            .shadow(color: color, radius: 4)
            .offset(x: cos(a) * r, y: sin(a) * r)
    }
}

/// Mono capsule label.
struct MonoPill: View {
    let text: String
    var color: Color = Palette.secondaryInk
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(Typo.eyebrow).tracking(1.1)
            .foregroundStyle(filled ? Palette.canvas : color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(filled ? color : color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.3), lineWidth: 1))
    }
}

/// A factor behind a score: value, the person's usual, and a centred meter showing which way it pulled.
struct FactorRow: View {
    let factor: ScoreFactor
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(factor.value).font(Typo.number(17)).foregroundStyle(Palette.ink).monospacedDigit()
            }
            DivergingMeter(value: factor.effect, color: factor.effect >= 0 ? color : Palette.coral)
            HStack {
                Text(factor.baseline).font(.caption).foregroundStyle(Palette.secondaryInk)
                Spacer()
                Text("\(Int((factor.weight * 100).rounded()))% OF SCORE").font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// −1 … 1 meter growing from the centre.
struct DivergingMeter: View {
    let value: Double
    var color: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let v = max(-1, min(1, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.raised)
                Rectangle().fill(Palette.secondaryInk.opacity(0.5)).frame(width: 1, height: 10).offset(x: w / 2 - 0.5)
                Capsule().fill(color.gradient)
                    .frame(width: max(3, abs(v) * w / 2), height: 4)
                    .offset(x: v >= 0 ? w / 2 : w / 2 - abs(v) * w / 2)
            }
        }
        .frame(height: 10)
    }
}

/// A personal range with today's value placed on it (Health Monitor).
struct RangeBar: View {
    let value: Double?
    let range: ClosedRange<Double>?
    var color: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.raised).frame(height: 6)
                if let range {
                    let span = range.upperBound - range.lowerBound
                    let lo = range.lowerBound - span * 0.5
                    let hi = range.upperBound + span * 0.5
                    let x0 = w * (range.lowerBound - lo) / (hi - lo)
                    let x1 = w * (range.upperBound - lo) / (hi - lo)
                    Capsule().fill(color.opacity(0.25)).frame(width: x1 - x0, height: 6).offset(x: x0)
                    if let value {
                        let x = max(0, min(w, w * (value - lo) / (hi - lo)))
                        Circle().fill(range.contains(value) ? color : Palette.amber)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 2))
                            .offset(x: x - 5.5)
                    }
                }
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }
}

/// Seven days of readiness as bars (Skintel's 7-day strip, in the instrument palette).
struct WeekStrip: View {
    let days: [DayScores]
    var selected: LocalDate?
    var onSelect: ((LocalDate) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { d in
                let isSelected = d.date == selected
                Button { onSelect?(d.date) } label: {
                    VStack(spacing: 6) {
                        Text(d.readiness.map(String.init) ?? "–").font(Typo.number(12)).foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5).fill(Palette.raised).frame(height: 54)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Palette.band(d.band).gradient)
                                .frame(height: max(4, 54 * Double(d.readiness ?? 0) / 100))
                                .opacity(d.readiness == nil ? 0 : 1)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected ? Palette.ink : .clear, lineWidth: 1.5))
                        Text(String(Fmt.weekdayShort[d.date.weekday - 1].prefix(1))).font(Typo.eyebrow)
                            .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(Fmt.dayLabel(d.date)): readiness \(d.readiness.map(String.init) ?? "not available")")
            }
        }
    }
}

/// A month-style heatmap (Skintel's journal grid): one cell per day, coloured by band or intensity.
struct ScoreHeatmap: View {
    enum Mode { case readiness, sleep, load }
    let days: [DayScores]
    var mode: Mode = .readiness
    var selected: LocalDate?
    var onSelect: ((LocalDate) -> Void)?

    var body: some View {
        let first = days.first?.date ?? LocalDate(Date(), calendar: .current)
        let lead = (first.weekday + 5) % 7 // Monday-first columns
        let cells: [DayScores?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        Button { onSelect?(cell.date) } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color(cell))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(cell.date == selected ? Palette.ink : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Fmt.dayLabel(cell.date)): \(text(cell))")
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    func color(_ d: DayScores) -> Color {
        switch mode {
        case .readiness: return d.readiness == nil ? Palette.raised : Palette.band(d.band).opacity(0.25 + 0.75 * Double(d.readiness ?? 0) / 100)
        case .sleep: return d.sleep.map { Palette.sleep.opacity(0.15 + 0.85 * pow(Double($0) / 100, 2)) } ?? Palette.raised
        case .load: return d.load.map { Palette.cobalt.opacity(0.12 + 0.88 * $0 / LoadResult.maximum) } ?? Palette.raised
        }
    }

    func text(_ d: DayScores) -> String {
        switch mode {
        case .readiness: d.readiness.map { "readiness \($0)" } ?? "no score"
        case .sleep: d.sleep.map { "sleep \($0)%" } ?? "no sleep"
        case .load: d.load.map { "load \(Fmt.decimal($0))" } ?? "no load"
        }
    }
}

/// Bento tile: mono label, big condensed value, an optional sparkline and caption.
struct MetricTile: View {
    let title: String
    var icon: String?
    let value: String
    var unit: String?
    var caption: String?
    var color: Color = Palette.cobalt
    var spark: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 6) {
                if let icon { BLIcon(name: icon, size: 13).foregroundStyle(color) }
                Text(title.uppercased()).font(Typo.eyebrow).tracking(1.1).foregroundStyle(Palette.secondaryInk).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Typo.score(34)).foregroundStyle(Palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(Typo.number(14, weight: .medium)).foregroundStyle(Palette.secondaryInk) }
            }
            if spark.count >= 3 {
                MiniSpark(values: spark, color: color).frame(height: 24)
            }
            if let caption {
                Text(caption).font(.caption).foregroundStyle(Palette.secondaryInk).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Space.m + 2)
        .accessibilityElement(children: .combine)
    }
}

/// Minimal line with a glowing end point.
struct MiniSpark: View {
    let values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { g in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * Double(i) / Double(max(values.count - 1, 1)), y: g.size.height * (1 - (v - lo) / span) * 0.85 + 2)
            }
            ZStack {
                Path { p in p.addLines(pts) }.stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 4).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Segmented progress (Skintel "2 of 5 done").
struct SegmentedProgress: View {
    let total: Int
    let done: Int
    var color: Color = Palette.cobalt

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i < done ? color : Palette.raised).frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total)")
    }
}
