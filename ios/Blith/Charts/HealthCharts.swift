import BlithCore
import Charts
import SwiftUI

// MARK: - Today accumulation

/// Today's cumulative steps against the user's usual curve for this weekday.
struct AccumulationChart: View {
    let pace: TodayPace
    var compact = false
    /// White-on-cobalt styling for the story card.
    var onHero = false

    var lineColor: Color { Palette.signalBright }
    var usualColor: Color { Palette.tertiaryInk }
    var axisColor: Color { Palette.tertiaryInk }

    struct Point: Identifiable {
        let hour: Double
        let steps: Double
        let series: String
        var id: String { "\(series)-\(hour)" }
    }

    var todayPoints: [Point] {
        var pts = [Point(hour: 0, steps: 0, series: "Today")]
        let current = Int(pace.hourNow)
        for h in 0..<min(current, pace.todayCurve.count) {
            pts.append(Point(hour: Double(h + 1), steps: pace.todayCurve[h], series: "Today"))
        }
        pts.append(Point(hour: pace.hourNow, steps: pace.stepsSoFar, series: "Today"))
        return pts
    }

    var usualPoints: [Point] {
        guard !pace.usualCurve.isEmpty else { return [] }
        return [Point(hour: 0, steps: 0, series: "Usual")] + pace.usualCurve.enumerated().map {
            Point(hour: Double($0.offset + 1), steps: $0.element, series: "Usual")
        }
    }

    var body: some View {
        Chart {
            // Your usual day, as a soft territory: the baseline motif.
            ForEach(usualPoints) { p in
                AreaMark(x: .value("Hour", p.hour), y: .value("Steps", p.steps))
                    .foregroundStyle(Palette.usualBand)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Hour", p.hour), y: .value("Steps", p.steps), series: .value("Series", "Usual"))
                    .foregroundStyle(Palette.quiet)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(todayPoints) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Steps", p.steps), series: .value("Series", "Today"))
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            RuleMark(x: .value("Now", pace.hourNow))
                .foregroundStyle(Palette.hairline)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let usual = pace.usualByNow {
                PointMark(x: .value("Hour", pace.hourNow), y: .value("Usual", usual))
                    .symbol { Circle().strokeBorder(Palette.tertiaryInk, lineWidth: 1.5).frame(width: 9, height: 9) }
            }
            PointMark(x: .value("Hour", pace.hourNow), y: .value("Steps", pace.stepsSoFar))
                .symbol {
                    ZStack {
                        Circle().fill(Palette.signal.opacity(0.25)).frame(width: 20, height: 20)
                        Circle().fill(Palette.ink).frame(width: 8, height: 8)
                    }
                }
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0.0, 6.0, 12.0, 18.0, 24.0]) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(Fmt.hour(Int(h) % 24).replacingOccurrences(of: " ", with: "")).font(Typo.mono(11)).foregroundStyle(axisColor)
                    }
                }
            }
        }
        .chartYAxis(compact ? .hidden : .automatic)
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps through the day")
        .accessibilityValue(accessibilityText)
    }

    var accessibilityText: String {
        var s = "\(Fmt.int(pace.stepsSoFar)) steps so far"
        if let u = pace.usualByNow { s += ", usually \(Fmt.int(u)) by now" }
        return s
    }
}

// MARK: - Step history

/// Interactive bars for any period. Drag across to read each bar.
struct StepHistoryChart: View {
    let buckets: [ChartBucket]
    let unit: BucketUnit
    var average: Double?
    var usualHourly: [Double]?
    var height: CGFloat = 220
    var interactive = true
    /// Daily average of the comparison period, drawn as a dashed reference.
    var previousAverage: Double?
    /// The day/bucket shown in the detail panel below the chart.
    var pinned: LocalDate?
    /// Called with the bucket under the finger (tap or drag).
    var onSelect: ((ChartBucket) -> Void)?

    @State private var selectedDate: Date?

    var body: some View {
        Group {
            if unit == .hour { hourChart } else { dateChart }
        }
        .frame(height: height)
    }

    // Hourly (today). Hours are plotted as dates with an hour unit so bars get proper bands.

    var dayStart: Date { (buckets.first?.start ?? LocalDate(Date(), calendar: .current)).startDate(in: .current) }
    func hourDate(_ h: Int) -> Date { dayStart.addingTimeInterval(Double(h) * 3600) }

    var typicalHourly: [(Int, Double)] {
        guard let cum = usualHourly, cum.count == 24 else { return [] }
        return (0..<24).map { h in (h, h == 0 ? cum[0] : max(0, cum[h] - cum[h - 1])) }
    }

    var selectedHour: Int? {
        guard let selectedDate else { return nil }
        return max(0, min(23, Int(selectedDate.timeIntervalSince(dayStart) / 3600)))
    }

    var hourChart: some View {
        Chart {
            ForEach(buckets) { b in
                if let hour = b.hour {
                    BarMark(x: .value("Hour", hourDate(hour), unit: .hour), y: .value("Steps", b.value ?? 0))
                        .foregroundStyle(selectedHour == nil || selectedHour == hour ? Palette.signal : Palette.signal.opacity(0.3))
                        .cornerRadius(3)
                }
            }
            ForEach(typicalHourly, id: \.0) { item in
                LineMark(x: .value("Hour", hourDate(item.0), unit: .hour), y: .value("Usual", item.1))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [2, 4]))
                    .interpolationMethod(.monotone)
            }
            if let h = selectedHour, let b = buckets.first(where: { $0.hour == h }) {
                RuleMark(x: .value("Hour", hourDate(h), unit: .hour))
                    .foregroundStyle(Palette.separator)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(title: "\(Fmt.hour(h)) – \(Fmt.hour(h + 1))", value: b.value.map { "\(Fmt.int($0)) steps" } ?? "Later today")
                    }
            }
        }
        .chartXScale(domain: dayStart...hourDate(24))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.hour()).font(Typo.mono(10))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(Typo.mono(10))
            }
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps by hour today")
        .accessibilityValue(buckets.compactMap { b in b.value.flatMap { $0 > 0 ? "\(Fmt.hour(b.hour ?? 0)): \(Fmt.int($0))" : nil } }.joined(separator: ", "))
    }

    // Days / weeks / months

    var calendarUnit: Calendar.Component {
        switch unit {
        case .hour, .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    var selectedBucket: ChartBucket? {
        guard unit != .hour, let selectedDate else { return nil }
        return buckets.min { abs($0.start.chartDate.timeIntervalSince(selectedDate)) < abs($1.start.chartDate.timeIntervalSince(selectedDate)) }
    }

    var dateChart: some View {
        Chart {
            ForEach(buckets) { b in
                if let v = b.value, v > 0 {
                    BarMark(x: .value("Date", b.start.chartDate, unit: calendarUnit), y: .value("Steps", v))
                        .foregroundStyle(barStyle(b))
                        .cornerRadius(unit == .day ? 5 : 3)
                } else if b.value == 0 {
                    // A measured zero: a flat cobalt tick on the baseline.
                    PointMark(x: .value("Date", b.start.chartDate, unit: calendarUnit), y: .value("Steps", 0))
                        .symbol { Capsule().fill(Palette.signal).frame(width: 10, height: 3) }
                } else if !b.isPartial {
                    // No record at all: a hollow marker, visibly different from zero.
                    PointMark(x: .value("Date", b.start.chartDate, unit: calendarUnit), y: .value("Steps", 0))
                        .symbol { Circle().strokeBorder(Palette.tertiaryInk, lineWidth: 1.25).frame(width: 7, height: 7) }
                }
            }
            if let previousAverage, selectedBucket == nil {
                RuleMark(y: .value("Previous", previousAverage))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        ruleLabel("BEFORE \(Fmt.int(previousAverage))", Palette.tertiaryInk)
                    }
            }
            if let average, selectedBucket == nil {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        ruleLabel("AVG \(Fmt.int(average))", Palette.ink)
                    }
            }
            if let b = selectedBucket {
                RuleMark(x: .value("Date", b.start.chartDate, unit: calendarUnit))
                    .foregroundStyle(Palette.separator)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(title: label(b), value: b.value.map { "\(Fmt.int($0)) \(unit == .day ? "steps" : "avg / day")" } ?? "No data")
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: unit == .day && buckets.count <= 7 ? 7 : 5)) { value in
                AxisValueLabel(format: axisFormat, centered: true).font(Typo.mono(10))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel { if let v = value.as(Double.self) { Text(v >= 1000 ? "\(Fmt.decimal(v / 1000, digits: v.truncatingRemainder(dividingBy: 1000) == 0 ? 0 : 1))k" : Fmt.int(v)).font(Typo.mono(10)) } }
            }
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .sensoryFeedback(.selection, trigger: selectedBucket?.id)
        .onChange(of: selectedBucket?.id) { _, _ in
            if let b = selectedBucket { onSelect?(b) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step history")
        .accessibilityValue(buckets.suffix(7).compactMap { b in b.value.map { "\(label(b)): \(Fmt.int($0))" } }.joined(separator: ", "))
    }

    func barStyle(_ b: ChartBucket) -> AnyShapeStyle {
        if let sel = selectedBucket { return AnyShapeStyle(sel.id == b.id ? Palette.signalBright : Palette.signal.opacity(0.25)) }
        if let pinned, unit == .day, buckets.contains(where: { $0.start == pinned }) {
            return AnyShapeStyle(pinned == b.start ? Palette.signalBright : Palette.signal.opacity(0.35))
        }
        if b.isPartial { return AnyShapeStyle(Palette.signal.opacity(0.45)) }
        // History is quieter than the most recent week, so the current stretch reads first.
        if unit == .day, buckets.count > 10, let last = buckets.last?.start, last.dayNumber - b.start.dayNumber >= 7 {
            return AnyShapeStyle(Palette.signal.opacity(0.42))
        }
        return AnyShapeStyle(LinearGradient(colors: [Palette.signalBright, Palette.signal], startPoint: .top, endPoint: .bottom))
    }

    var axisFormat: Date.FormatStyle {
        switch unit {
        case .hour, .day: buckets.count <= 7 ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated)
        case .week: .dateTime.month(.abbreviated)
        case .month: buckets.count > 24 ? .dateTime.year() : .dateTime.month(.narrow)
        }
    }

    func label(_ b: ChartBucket) -> String {
        switch unit {
        case .hour, .day: Fmt.dayLabel(b.start).uppercased()
        case .week: "WEEK OF \(Fmt.shortDate(b.start).uppercased())"
        case .month: "\(Fmt.monthNames[b.start.month - 1].uppercased()) \(b.start.year)"
        }
    }
}

/// A rule-line label on a solid chip, so it stays legible where it crosses bars.
func ruleLabel(_ text: String, _ color: Color) -> some View {
    Text(text)
        .font(Typo.mono(10, .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Palette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
}

func tooltip(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(Typo.mono(10, .medium)).foregroundStyle(Palette.tertiaryInk)
        Text(value).font(Typo.geist(15, .semibold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Palette.ink)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
}

// MARK: - Patterns

struct WeekdayBars: View {
    let pattern: WeekdayPattern
    let firstWeekday: Int

    var order: [Int] { (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 } }

    var body: some View {
        Chart {
            ForEach(order, id: \.self) { wd in
                BarMark(x: .value("Day", Fmt.weekdayShort[wd - 1]), y: .value("Typical steps", pattern.medians[wd - 1] ?? 0))
                    .foregroundStyle(wd == pattern.busiest ? AnyShapeStyle(Palette.signal) : AnyShapeStyle(Palette.quiet))
                    .cornerRadius(5)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Typical steps by weekday")
        .accessibilityValue(order.compactMap { wd in pattern.medians[wd - 1].map { "\(Fmt.weekdayNames[wd - 1]) \(Fmt.int($0))" } }.joined(separator: ", "))
    }
}

struct TimeOfDayBars: View {
    let profile: TimeOfDayProfile

    /// A reference day so hours can use a date axis with hour bands.
    var dayStart: Date { Calendar.current.startOfDay(for: Date()) }
    func hourDate(_ h: Int) -> Date { dayStart.addingTimeInterval(Double(h) * 3600) }

    var body: some View {
        Chart {
            ForEach(0..<24, id: \.self) { h in
                BarMark(x: .value("Hour", hourDate(h), unit: .hour), y: .value("Share", profile.shares[h]))
                    .foregroundStyle(h >= profile.peakWindowStart && h < profile.peakWindowStart + 4
                                     ? AnyShapeStyle(Palette.signal) : AnyShapeStyle(Palette.quiet))
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: dayStart...hourDate(24))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour()).font(Typo.mono(10))
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("When you move during the day")
        .accessibilityValue("Most movement between \(Fmt.hour(profile.peakWindowStart)) and \(Fmt.hour(profile.peakWindowStart + 4))")
    }
}

// MARK: - Weight

struct WeightTrendChart: View {
    let points: [WeightPoint]
    var goalKg: Double?
    let units: UnitSystem
    var height: CGFloat = 200
    var showReadings = true
    var interactive = true

    @State private var selected: Date?

    func display(_ kg: Double) -> Double { units == .metric ? kg : kg * 2.204_622_6 }

    var yDomain: ClosedRange<Double> {
        var values = points.map { display($0.value) } + points.map { display($0.trend) }
        if let g = goalKg { values.append(display(g)) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max(0.5, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }

    var selectedPoint: WeightPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        Chart {
            if showReadings {
                ForEach(points) { p in
                    PointMark(x: .value("Date", p.date), y: .value("Reading", display(p.value)))
                        .foregroundStyle(Palette.tertiaryInk.opacity(0.7))
                        .symbolSize(16)
                }
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Trend", display(p.trend)))
                    .foregroundStyle(Palette.weight)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let g = goalKg {
                RuleMark(y: .value("Goal", display(g)))
                    .foregroundStyle(Palette.weight.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("GOAL").font(Typo.mono(10, .medium)).foregroundStyle(Palette.weight)
                    }
            }
            if let p = selectedPoint {
                RuleMark(x: .value("Date", p.date))
                    .foregroundStyle(Palette.separator)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(title: p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased(),
                                value: "\(Fmt.weight(p.value, units: units)) · trend \(Fmt.weight(p.trend, units: units))")
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(Typo.mono(10))
            }
        }
        .chartXSelection(value: interactive ? $selected : .constant(nil))
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight trend")
        .accessibilityValue(points.last.map { "Trend \(Fmt.weight($0.trend, units: units))" } ?? "No readings")
    }
}

// MARK: - Sleep

/// Hypnogram: awake / REM / core / deep lanes across the night.
struct SleepTimelineView: View {
    let night: SleepNight
    var height: CGFloat = 132
    /// No lane labels or times, for small tiles.
    var compact = false

    static let lanes: [(String, SleepStageStyle)] = [("Awake", .awake), ("REM", .rem), ("Core", .core), ("Deep", .deep)]

    func lane(_ stage: SleepStage) -> Int? {
        switch stage {
        case .awake: 0
        case .rem: 1
        case .core, .asleepUnspecified: 2
        case .deep: 3
        case .inBed: nil
        }
    }

    var body: some View {
        let start = night.start ?? Date()
        let end = night.end ?? start.addingTimeInterval(1)
        let total = max(1, end.timeIntervalSince(start))
        VStack(spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                if !compact {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.lanes, id: \.0) { lane in
                            Text(lane.0.uppercased()).font(Typo.mono(9.5)).foregroundStyle(Palette.tertiaryInk).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 40)
                }
                GeometryReader { geo in
                    let laneHeight = geo.size.height / 4
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<4, id: \.self) { i in
                            Rectangle().fill(Palette.hairline).frame(height: 1)
                                .offset(y: laneHeight * CGFloat(i) + laneHeight / 2)
                        }
                        ForEach(Array(night.segments.enumerated()), id: \.offset) { _, seg in
                            if let l = lane(seg.stage) {
                                let x = CGFloat(seg.start.timeIntervalSince(start) / total) * geo.size.width
                                let w = max(2, CGFloat(seg.duration / total) * geo.size.width)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Palette.sleep(Self.lanes[l].1))
                                    .frame(width: w, height: laneHeight * 0.66)
                                    .offset(x: x, y: laneHeight * CGFloat(l) + laneHeight * 0.17)
                            }
                        }
                    }
                }
            }
            .frame(height: height)
            if !compact {
                HStack {
                    Text(start.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text(end.formatted(date: .omitted, time: .shortened))
                }
                .font(Typo.mono(10))
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.leading, 48)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
        .accessibilityValue("Asleep \(Fmt.duration(night.asleepDuration)), from \(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))")
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.accent

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0)...(max((values.max() ?? 1), (values.min() ?? 0) + 0.1)))
        .accessibilityHidden(true)
    }
}

// MARK: - Sleep timing

/// One floating bar per night from falling asleep to waking, so shifts in timing are visible.
struct SleepTimingChart: View {
    let points: [SleepTimingPoint]
    var height: CGFloat = 170

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Night", p.date.chartDate, unit: .day),
                    yStart: .value("Asleep", p.bedMinutes / 60), yEnd: .value("Awake", p.wakeMinutes / 60), width: .ratio(0.6))
                .foregroundStyle(LinearGradient(colors: [Palette.sleep, Palette.sleep.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .cornerRadius(4)
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .stride(by: 2)) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let h = value.as(Double.self) { Text(Fmt.hour(Int(h.rounded()))).font(Typo.mono(10)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Typo.mono(10)) }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep timing, last \(points.count) nights")
        .accessibilityValue(points.suffix(7).map { "\(Fmt.dayLabel($0.date)): \(SleepAnalytics.clock($0.bedMinutes)) to \(SleepAnalytics.clock($0.wakeMinutes))" }.joined(separator: ", "))
    }
}

// MARK: - Walking signature

/// A generative portrait of how this person walks: seven rings (weekdays, Monday innermost)
/// by 24 spokes (hours). Each dot's size is the average steps in that hour on that weekday
/// over the last 8 weeks, so no two people's signatures look alike.
struct WalkSignatureView: View {
    let history: HealthHistory
    let today: LocalDate
    var size: CGFloat = 260
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false

    /// [weekdayIndex 0 = Monday][hour] → mean steps.
    var matrix: [[Double]] {
        var sums = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        var counts = Array(repeating: 0, count: 7)
        for d in LocalDate.range(today.adding(days: -56), today.adding(days: -1)) {
            guard let h = history.hourlySteps[d], h.total > 0 else { continue }
            let w = (d.weekday + 5) % 7
            counts[w] += 1
            for i in 0..<24 { sums[w][i] += h.values[i] }
        }
        return (0..<7).map { w in sums[w].map { counts[w] > 0 ? $0 / Double(counts[w]) : 0 } }
    }

    var body: some View {
        let m = matrix
        let peak = max(1, m.flatMap { $0 }.max() ?? 1)
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let maxR = min(sz.width, sz.height) / 2 - 8
            for ring in 0..<7 {
                let r = maxR * (0.3 + 0.7 * CGFloat(ring) / 6)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(Palette.hairline), lineWidth: 0.75)
                for hour in 0..<24 {
                    let v = m[ring][hour] / peak
                    guard v > 0.02 else { continue }
                    let angle = (Double(hour) / 24) * 2 * .pi - .pi / 2
                    let p = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
                    let dot = CGFloat(1.5 + 7.5 * sqrt(v)) * (appear ? 1 : 0.2)
                    let color = v > 0.6 ? Palette.cyan : Palette.signal
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)),
                             with: .color(color.opacity(0.35 + 0.65 * v)))
                }
            }
            for (label, hour) in [("12a", 0), ("6a", 6), ("12p", 12), ("6p", 18)] {
                let angle = (Double(hour) / 24) * 2 * .pi - .pi / 2
                let r = maxR + 2
                ctx.draw(Text(label.uppercased()).font(Typo.mono(9, .medium)).foregroundStyle(Palette.tertiaryInk),
                         at: CGPoint(x: c.x + r * CGFloat(cos(angle)) * 0.86, y: c.y + r * CGFloat(sin(angle)) * 0.86))
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.8)) { appear = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walking signature: when you usually walk, by weekday and hour, over the last 8 weeks")
    }
}
