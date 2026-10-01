import BlithCore
import Charts
import SwiftUI

// Instruments: dials, meters, range bars, strips and heatmaps. v4 "Signal": thin precise
// geometry, the person's usual range as a translucent band, one lit tip where the value is.

/// A 300° precision gauge: a fine tick bezel, the usual band as a soft arc segment, the value as a
/// thin bright arc with a lit tip, and calm light numerals in the middle.
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
    var trackWidth: CGFloat { max(2.5, size * 0.03) }
    var valueWidth: CGFloat { max(3.5, size * 0.045) }
    var bandWidth: CGFloat { max(8, size * 0.1) }
    var radius: CGFloat { size / 2 - size * 0.14 }

    var body: some View {
        ZStack {
            ticks
            if let usual {
                arc(usual.lowerBound, usual.upperBound)
                    .stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: bandWidth, lineCap: .butt))
            }
            arc(0, 1).stroke(Palette.sunken, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            if fraction != nil {
                arc(0, max(0.001, shown))
                    .stroke(AngularGradient(colors: [color.opacity(0.3), color], center: .center,
                                            startAngle: angle(0), endAngle: angle(1)),
                            style: StrokeStyle(lineWidth: valueWidth, lineCap: .round))
                tip
            }
            VStack(spacing: size * 0.01) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(valueText).font(Typo.score(size * 0.33)).foregroundStyle(fraction == nil ? Palette.tertiaryInk : Palette.ink)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if let unit { Text(unit).font(Typo.score(size * 0.12, weight: .regular)).foregroundStyle(Palette.secondaryInk) }
                }
                Text(label.uppercased()).font(.custom("GeistMono-Medium", fixedSize: max(8.5, size * 0.075)))
                    .tracking(0.8).foregroundStyle(Palette.secondaryInk).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, size * 0.2)
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
            p.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: radius, startAngle: angle(a), endAngle: angle(b), clockwise: false)
        }
    }

    /// 61 fine ticks; majors every 10. Ticks up to the value are lit faintly in the dial's colour.
    var ticks: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let outer = sz.width / 2 - 1
            for i in 0...60 {
                let f = Double(i) / 60
                let a = angle(f).radians
                let major = i % 10 == 0
                let inner = outer - (major ? size * 0.055 : size * 0.03)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                let lit = fraction != nil && f <= shown
                ctx.stroke(p, with: .color(lit ? color.opacity(major ? 0.9 : 0.55) : Palette.quiet.opacity(major ? 1 : 0.6)),
                           lineWidth: major ? 1.2 : 0.8)
            }
        }
    }

    var tip: some View {
        let a = angle(shown).radians
        return ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: valueWidth * 3.2, height: valueWidth * 3.2)
            Circle().fill(Palette.ink).frame(width: valueWidth * 1.3, height: valueWidth * 1.3)
        }
        .offset(x: cos(a) * radius, y: sin(a) * radius)
    }
}

/// Mono capsule label.
struct MonoPill: View {
    let text: String
    var color: Color = Palette.secondaryInk
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(Typo.eyebrow).tracking(0.9)
            .foregroundStyle(filled ? Palette.canvas : color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(filled ? color : color.opacity(0.10)))
            .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.28), lineWidth: 1))
    }
}

/// A factor behind a score: value, the person's usual, and a centred meter showing which way it
/// pulled. A factor that pulled down is shown neutral, never red.
struct FactorRow: View {
    let factor: ScoreFactor
    var color: Color
    var negative: Color = Palette.tertiaryInk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.title).font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                Spacer()
                Text(factor.value).font(Typo.number(17)).foregroundStyle(Palette.ink)
            }
            DivergingMeter(value: factor.effect, color: factor.effect >= 0 ? color : negative)
            HStack {
                Text(factor.baseline).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                Spacer()
                Text("\(Int((factor.weight * 100).rounded()))% of score".uppercased()).font(Typo.eyebrow).tracking(0.8).foregroundStyle(Palette.tertiaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// −1 … 1 meter growing from a centre mark.
struct DivergingMeter: View {
    let value: Double
    var color: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let v = max(-1, min(1, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken).frame(height: 4)
                Capsule().fill(color)
                    .frame(width: max(3, abs(v) * w / 2), height: 4)
                    .offset(x: v >= 0 ? w / 2 : w / 2 - abs(v) * w / 2)
                Rectangle().fill(Palette.secondaryInk).frame(width: 1.5, height: 12).offset(x: w / 2 - 0.75)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }
}

/// A personal range as a band with the latest reading placed on it (Health Monitor).
/// Outside the range the marker becomes an amber ring: shape and colour both change.
struct RangeBar: View {
    let value: Double?
    let range: ClosedRange<Double>?
    var color: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken).frame(height: 4)
                if let range {
                    let span = max(range.upperBound - range.lowerBound, 0.0001)
                    let lo = range.lowerBound - span * 0.5
                    let hi = range.upperBound + span * 0.5
                    let x0 = w * (range.lowerBound - lo) / (hi - lo)
                    let x1 = w * (range.upperBound - lo) / (hi - lo)
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.22)).frame(width: x1 - x0, height: 10).offset(x: x0)
                    if let value {
                        let x = max(0, min(w, w * (value - lo) / (hi - lo)))
                        let inside = range.contains(value)
                        Group {
                            if inside {
                                Circle().fill(Palette.ink).frame(width: 10, height: 10)
                            } else {
                                Circle().strokeBorder(Palette.note, lineWidth: 2.5).frame(width: 12, height: 12)
                                    .background(Circle().fill(Palette.surface))
                            }
                        }
                        .offset(x: x - 5.5)
                    }
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }
}

/// Seven days of readiness on the blue luminance ramp; the selected day is outlined.
struct WeekStrip: View {
    let days: [DayScores]
    var selected: LocalDate?
    var onSelect: ((LocalDate) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { d in
                let isSelected = d.date == selected
                Button { onSelect?(d.date) } label: {
                    VStack(spacing: 7) {
                        Text(d.readiness.map(String.init) ?? "–").font(Typo.mono(11, isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(d.readiness == nil ? Palette.hairline : .clear, lineWidth: 1)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(d.readiness == nil ? .clear : Palette.sunken))
                                .frame(height: 58)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.band(d.band), Palette.band(d.band).opacity(0.55)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(4, 58 * Double(d.readiness ?? 0) / 100))
                                .opacity(d.readiness == nil ? 0 : (isSelected || selected == nil ? 1 : 0.7))
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(isSelected ? Palette.ink : .clear, lineWidth: 1.5))
                        Text(String(Fmt.weekdayShort[d.date.weekday - 1].prefix(1))).font(Typo.eyebrow)
                            .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(Fmt.dayLabel(d.date)): readiness \(d.readiness.map(String.init) ?? "not available")")
            }
        }
    }
}

/// 13 weeks of one score as thin daily bars against the person's usual range (the middle half of
/// the period, drawn as a soft band). Days above the band are bright, days inside it calm, days
/// below it quiet — never red. Days without a score draw nothing. Tap or drag to pick a day.
/// (Kept under its old name so every screen that showed the heatmap now gets this.)
struct ScoreHeatmap: View {
    enum Mode { case readiness, sleep, load }
    let days: [DayScores]
    var mode: Mode = .readiness
    var selected: LocalDate?
    var onSelect: ((LocalDate) -> Void)?
    @State private var dragDate: Date?

    func value(_ d: DayScores) -> Double? {
        switch mode {
        case .readiness: d.readiness.map(Double.init)
        case .sleep: d.sleep.map(Double.init)
        case .load: d.load
        }
    }

    var tint: Color {
        switch mode {
        case .readiness: Palette.signal
        case .sleep: Palette.sleep
        case .load: Palette.cyan
        }
    }

    var usual: ClosedRange<Double>? { Stats.usualRange(days.compactMap(value)) }

    var yMax: Double {
        switch mode {
        case .readiness, .sleep: 100
        case .load: max(LoadResult.maximum * 0.6, (days.compactMap(\.load).max() ?? 1) * 1.1)
        }
    }

    func style(_ d: DayScores, _ v: Double) -> Color {
        if let selected { return d.date == selected ? Palette.ink : tint.opacity(0.35) }
        guard let usual else { return tint.opacity(0.7) }
        if v > usual.upperBound { return tint }
        if v < usual.lowerBound { return Palette.quiet }
        return tint.opacity(0.55)
    }

    var body: some View {
        let usual = self.usual
        let first = days.first?.date.chartDate ?? Date()
        let last = days.last?.date.chartDate ?? Date()
        VStack(alignment: .leading, spacing: Space.s) {
            Chart {
                if let usual {
                    RectangleMark(xStart: .value("From", first.addingTimeInterval(-43_200)), xEnd: .value("To", last.addingTimeInterval(43_200)),
                                  yStart: .value("Usual low", usual.lowerBound), yEnd: .value("Usual high", usual.upperBound))
                        .foregroundStyle(Palette.usualBand)
                }
                ForEach(days) { d in
                    if let v = value(d) {
                        BarMark(x: .value("Day", d.date.chartDate, unit: .day), y: .value("Score", max(v, yMax * 0.02)), width: .ratio(0.62))
                            .foregroundStyle(style(d, v))
                            .cornerRadius(1.5)
                    }
                }
                if let selected, let d = days.first(where: { $0.date == selected }), let v = value(d) {
                    RuleMark(x: .value("Selected", selected.chartDate))
                        .foregroundStyle(Palette.hairline)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(title: Fmt.dayLabel(selected).uppercased(), value: text(d, v))
                        }
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk)
                }
            }
            .chartXSelection(value: $dragDate)
            .onChange(of: dragDate) { _, date in
                guard let date, let nearest = days.min(by: { abs($0.date.chartDate.timeIntervalSince(date)) < abs($1.date.chartDate.timeIntervalSince(date)) }) else { return }
                onSelect?(nearest.date)
            }
            .sensoryFeedback(.selection, trigger: selected)
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last 13 weeks")
            .accessibilityValue(summary)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.usualBand).frame(width: 14, height: 8)
                Text(usual.map { "YOUR USUAL \(label($0.lowerBound))–\(label($0.upperBound)) · MIDDLE HALF OF THESE 13 WEEKS" } ?? "LEARNING YOUR USUAL")
                    .font(Typo.eyebrow).tracking(0.6).foregroundStyle(Palette.tertiaryInk).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    func label(_ v: Double) -> String { mode == .load ? Fmt.decimal(v) : Fmt.int(v) }

    func text(_ d: DayScores, _ v: Double) -> String {
        switch mode {
        case .readiness: "Readiness \(Fmt.int(v))"
        case .sleep: "Sleep \(Fmt.int(v))%"
        case .load: "Load \(Fmt.decimal(v))"
        }
    }

    var summary: String {
        let vs = days.compactMap(value)
        guard let avg = Stats.mean(vs) else { return "No scores yet" }
        return "\(vs.count) days with a score, average \(label(avg))"
    }
}

/// A compact tile: mono label, a calm numeral, an optional sparkline and caption.
struct MetricTile: View {
    let title: String
    var icon: String?
    let value: String
    var unit: String?
    var caption: String?
    var color: Color = Palette.signal
    var spark: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 6) {
                if let icon { BLIcon(name: icon, size: 14).foregroundStyle(color) }
                Text(title.uppercased()).font(Typo.eyebrow).tracking(0.9).foregroundStyle(Palette.secondaryInk).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Typo.score(34)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(Typo.geist(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.secondaryInk) }
            }
            if spark.count >= 3 {
                MiniSpark(values: spark, color: color).frame(height: 26)
            }
            if let caption {
                Text(caption).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Space.m + 2)
        .accessibilityElement(children: .combine)
    }
}

/// A precise line whose last point is marked with a ringed dot.
struct MiniSpark: View {
    let values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { g in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * Double(i) / Double(max(values.count - 1, 1)), y: g.size.height * (1 - (v - lo) / span) * 0.8 + 3)
            }
            ZStack {
                Path { p in p.addLines(pts) }.stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(color.opacity(0.22)).frame(width: 12, height: 12).position(last)
                    Circle().fill(color).frame(width: 5, height: 5).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Segmented progress ("2 of 5 done").
struct SegmentedProgress: View {
    let total: Int
    let done: Int
    var color: Color = Palette.signal

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i < done ? color : Palette.sunken).frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total)")
    }
}
