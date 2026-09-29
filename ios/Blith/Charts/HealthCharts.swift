import BlithCore
import Charts
import SwiftUI

// MARK: - Today accumulation

/// Today's cumulative steps against the user's usual curve for this weekday.
struct AccumulationChart: View {
    let pace: TodayPace
    var compact = false

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
            ForEach(usualPoints) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Steps", p.steps), series: .value("Series", "Usual"))
                    .foregroundStyle(Palette.baseline)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
                    .interpolationMethod(.monotone)
            }
            ForEach(todayPoints) { p in
                AreaMark(x: .value("Hour", p.hour), y: .value("Steps", p.steps))
                    .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.28), Palette.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Hour", p.hour), y: .value("Steps", p.steps), series: .value("Series", "Today"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            PointMark(x: .value("Hour", pace.hourNow), y: .value("Steps", pace.stepsSoFar))
                .foregroundStyle(Palette.accent)
                .symbolSize(90)
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0.0, 6.0, 12.0, 18.0, 24.0]) { value in
                AxisGridLine().foregroundStyle(Palette.separator.opacity(0.4))
                AxisValueLabel {
                    if let h = value.as(Double.self) { Text(Fmt.hour(Int(h) % 24).replacingOccurrences(of: " ", with: "")) }
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

    @State private var selectedDate: Date?
    @State private var selectedHour: Int?

    var body: some View {
        Group {
            if unit == .hour { hourChart } else { dateChart }
        }
        .frame(height: height)
    }

    // Hourly (today)

    var typicalHourly: [(Int, Double)] {
        guard let cum = usualHourly, cum.count == 24 else { return [] }
        return (0..<24).map { h in (h, h == 0 ? cum[0] : max(0, cum[h] - cum[h - 1])) }
    }

    var hourChart: some View {
        Chart {
            ForEach(buckets) { b in
                if let hour = b.hour {
                    BarMark(x: .value("Hour", hour), y: .value("Steps", b.value ?? 0), width: .ratio(0.7))
                        .foregroundStyle(selectedHour == nil || selectedHour == hour ? Palette.accent.gradient : Palette.accent.opacity(0.35).gradient)
                        .cornerRadius(3)
                }
            }
            ForEach(typicalHourly, id: \.0) { item in
                LineMark(x: .value("Hour", item.0), y: .value("Usual", item.1))
                    .foregroundStyle(Palette.baseline)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    .interpolationMethod(.monotone)
            }
            if let h = selectedHour, let b = buckets.first(where: { $0.hour == h }) {
                RuleMark(x: .value("Hour", h))
                    .foregroundStyle(Palette.separator)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(title: "\(Fmt.hour(h)) – \(Fmt.hour(h + 1))", value: b.value.map { "\(Fmt.int($0)) steps" } ?? "Later today")
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel { if let h = value.as(Int.self) { Text(Fmt.hour(h).replacingOccurrences(of: " ", with: "")) } }
            }
        }
        .chartXSelection(value: interactive ? $selectedHour : .constant(nil))
        .accessibilityLabel("Steps by hour today")
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
        guard let selectedDate else { return nil }
        return buckets.min { abs($0.start.chartDate.timeIntervalSince(selectedDate)) < abs($1.start.chartDate.timeIntervalSince(selectedDate)) }
    }

    var dateChart: some View {
        Chart {
            ForEach(buckets) { b in
                BarMark(x: .value("Date", b.start.chartDate, unit: calendarUnit), y: .value("Steps", b.value ?? 0))
                    .foregroundStyle(barStyle(b))
                    .cornerRadius(unit == .day ? 5 : 3)
            }
            if let average, selectedBucket == nil {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Palette.baseline)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(Fmt.int(average))").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
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
                AxisValueLabel(format: axisFormat, centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(Palette.separator.opacity(0.4))
                AxisValueLabel { if let v = value.as(Double.self) { Text(v >= 1000 ? "\(Fmt.decimal(v / 1000, digits: v.truncatingRemainder(dividingBy: 1000) == 0 ? 0 : 1))k" : Fmt.int(v)) } }
            }
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .sensoryFeedback(.selection, trigger: selectedBucket?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step history")
        .accessibilityValue(buckets.suffix(7).compactMap { b in b.value.map { "\(label(b)): \(Fmt.int($0))" } }.joined(separator: ", "))
    }

    func barStyle(_ b: ChartBucket) -> AnyShapeStyle {
        if let sel = selectedBucket, sel.id != b.id { return AnyShapeStyle(Palette.accent.opacity(0.3)) }
        if b.isPartial { return AnyShapeStyle(Palette.accent.opacity(0.55)) }
        return AnyShapeStyle(Palette.accent.gradient)
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

func tooltip(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Palette.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
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
                    .foregroundStyle(wd == pattern.busiest ? AnyShapeStyle(Palette.accent.gradient) : AnyShapeStyle(Palette.accent.opacity(0.35)))
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

    var body: some View {
        Chart {
            ForEach(0..<24, id: \.self) { h in
                BarMark(x: .value("Hour", h), y: .value("Share", profile.shares[h]), width: .ratio(0.75))
                    .foregroundStyle(h >= profile.peakWindowStart && h < profile.peakWindowStart + 4
                                     ? AnyShapeStyle(Palette.accent.gradient) : AnyShapeStyle(Palette.accent.opacity(0.3)))
                    .cornerRadius(2)
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel { if let h = value.as(Int.self) { Text(Fmt.hour(h).replacingOccurrences(of: " ", with: "")) } }
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
                        .foregroundStyle(Palette.baseline.opacity(0.6))
                        .symbolSize(18)
                }
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Trend", display(p.trend)))
                    .foregroundStyle(Palette.weight)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let g = goalKg {
                RuleMark(y: .value("Goal", display(g)))
                    .foregroundStyle(Palette.weight.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("Goal").font(.caption2.weight(.semibold)).foregroundStyle(Palette.weight)
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
                AxisGridLine().foregroundStyle(Palette.separator.opacity(0.4))
                AxisValueLabel()
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.lanes, id: \.0) { lane in
                        Text(lane.0).font(.caption2).foregroundStyle(.secondary).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 40)
                GeometryReader { geo in
                    let laneHeight = geo.size.height / 4
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<4, id: \.self) { i in
                            Rectangle().fill(Palette.separator.opacity(0.15)).frame(height: 1)
                                .offset(y: laneHeight * CGFloat(i) + laneHeight / 2)
                        }
                        ForEach(Array(night.segments.enumerated()), id: \.offset) { _, seg in
                            if let l = lane(seg.stage) {
                                let x = CGFloat(seg.start.timeIntervalSince(start) / total) * geo.size.width
                                let w = max(2, CGFloat(seg.duration / total) * geo.size.width)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Palette.sleep(Self.lanes[l].1))
                                    .frame(width: w, height: laneHeight * 0.62)
                                    .offset(x: x, y: laneHeight * CGFloat(l) + laneHeight * 0.19)
                            }
                        }
                    }
                }
            }
            .frame(height: height)
            HStack {
                Text(start.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(end.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 48)
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
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0)...(max((values.max() ?? 1), (values.min() ?? 0) + 0.1)))
        .accessibilityHidden(true)
    }
}
