import Foundation

// Blith's daily scores. Every score is computed from the person's own history and is shown
// with the factors behind it. They describe signals relative to the person's usual; they are
// not medical assessments.

public enum ScoreBand: String, Sendable, Hashable, Codable {
    case high, moderate, low

    public static func readiness(_ v: Int) -> ScoreBand { v >= 67 ? .high : v >= 34 ? .moderate : .low }

    public var label: String {
        switch self {
        case .high: "High"
        case .moderate: "Moderate"
        case .low: "Low"
        }
    }
}

/// One input to a score, shown in "Why this score".
public struct ScoreFactor: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var value: String
    public var baseline: String
    /// −1 … 1: how this factor pulled the score relative to the person's usual.
    public var effect: Double
    /// Share of the score this factor carries (0 … 1).
    public var weight: Double
}

public struct SleepPerformance: Sendable, Hashable {
    public var date: LocalDate
    public var score: Int
    public var asleep: TimeInterval
    public var inBed: TimeInterval
    public var need: TimeInterval
    public var efficiency: Double
    public var restorativeShare: Double?
    public var stages: [SleepStage: TimeInterval]
    public var disturbances: Int
    public var latencyMinutes: Double?
    public var bedtime: Date?
    public var wake: Date?
    public var consistency: Double?
    /// Shortfall against need over the last 7 nights (never negative).
    public var debt: TimeInterval
    public var respiratoryRate: Double?
    public var factors: [ScoreFactor]
}

public struct LoadResult: Sendable, Hashable {
    public var date: LocalDate
    /// 0 … 10, logarithmic: each step takes more effort than the last.
    public var value: Double
    public var effort: Double
    /// The middle half of the last 28 days' loads.
    public var usualRange: ClosedRange<Double>?
    public var activeEnergy: Double?
    public var exerciseMinutes: Double?
    public var steps: Double?
    public var workouts: [WorkoutRecord]
    public var factors: [ScoreFactor]

    public static let maximum = 10.0
}

public struct ReadinessResult: Sendable, Hashable {
    public var date: LocalDate
    public var score: Int?
    public var band: ScoreBand?
    public var calibrationDays: Int
    public var factors: [ScoreFactor]
    public var summary: String

    public var isCalibrating: Bool { score == nil && calibrationDays < ScoreEngine.calibrationDays }
}

public struct VitalReading: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable { case within, above, below, learning, noData }
    public var metric: HealthMetric
    public var value: Double?
    public var mean: Double?
    public var range: ClosedRange<Double>?
    public var status: Status
    public var recent: [DayValue]
    public var id: HealthMetric { metric }
}

public struct HealthMonitor: Sendable, Hashable {
    public var date: LocalDate
    public var vitals: [VitalReading]
    public var measured: Int { vitals.filter { $0.status != .noData && $0.status != .learning }.count }
    public var within: Int { vitals.filter { $0.status == .within }.count }
}

public struct DayScores: Sendable, Hashable, Identifiable {
    public var date: LocalDate
    public var readiness: Int?
    public var sleep: Int?
    public var load: Double?
    public var id: LocalDate { date }
    public var band: ScoreBand? { readiness.map(ScoreBand.readiness) }
}

public struct ScoreEngine: Sendable {
    public let history: HealthHistory
    public let today: LocalDate
    public let units: UnitSystem

    public static let calibrationDays = 14
    public static let monitored: [HealthMetric] = [.restingHeartRate, .hrv, .respiratoryRate, .oxygenSaturation, .wristTemperature]

    public init(_ ctx: AnalyticsContext) {
        history = ctx.history
        today = ctx.today
        units = ctx.profile.units
    }

    public init(history: HealthHistory, today: LocalDate, units: UnitSystem = .metric) {
        self.history = history
        self.today = today
        self.units = units
    }

    // MARK: Baselines

    struct Baseline { var mean: Double; var sd: Double; var n: Int }

    /// Mean and SD over the 30 days before `date` (the day itself is excluded).
    func baseline(_ metric: HealthMetric, before date: LocalDate, days: Int = 30, log: Bool = false) -> Baseline? {
        let vals = history.values(metric, in: DateSpan(date.adding(days: -days), date.adding(days: -1))).values
            .map { log ? Foundation.log(max($0, 1)) : $0 }
        guard vals.count >= 3, let m = Stats.mean(vals) else { return nil }
        return Baseline(mean: m, sd: Stats.standardDeviation(vals) ?? 0, n: vals.count)
    }

    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-1.3 * z)) }

    // MARK: Sleep

    /// Personal sleep need: the length of the person's well-rested nights (75th percentile of
    /// the last 28), kept within 7–9 hours. Falls back to 8 hours.
    public func sleepNeed(before date: LocalDate) -> TimeInterval {
        let vals = history.sleepNights.filter { $0.key < date && $0.key >= date.adding(days: -28) }.map(\.value.asleepDuration)
        guard vals.count >= 7, let p = Stats.percentile(vals, 0.75) else { return 8 * 3600 }
        return min(9 * 3600, max(7 * 3600, p))
    }

    static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if m < 12 * 60 { m += 24 * 60 } // after midnight counts as late evening
        return m
    }

    public func sleep(on date: LocalDate) -> SleepPerformance? {
        guard let night = history.sleepNights[date], night.asleepDuration > 1800 else { return nil }
        let asleep = night.asleepDuration
        let inBed = max(asleep, night.inBedDuration)
        let need = sleepNeed(before: date)
        let sufficiency = min(1, asleep / need)
        let efficiency = inBed > 0 ? asleep / inBed : 1
        var stages: [SleepStage: TimeInterval] = [:]
        for s in SleepStage.allCases { stages[s] = night.duration(of: s) }
        let restorative: Double? = night.hasStages && asleep > 0 ? ((stages[.deep] ?? 0) + (stages[.rem] ?? 0)) / asleep : nil
        let sorted = night.segments.sorted { $0.start < $1.start }
        let firstAsleep = sorted.first { $0.stage.isAsleep }
        let latency = firstAsleep.flatMap { fa in night.start.map { fa.start.timeIntervalSince($0) / 60 } }
        let disturbances = max(0, sorted.enumerated().filter { i, s in s.stage == .awake && i > 0 && i < sorted.count - 1 }.count)
        let bedtime = firstAsleep?.start
        var consistency: Double?
        if let bedtime {
            let prior = (1...7).compactMap { history.sleepNights[date.adding(days: -$0)]?.segments.first(where: { $0.stage.isAsleep })?.start }
                .map { Self.minutesOfDay($0) }
            if prior.count >= 3, let med = Stats.median(prior) {
                consistency = max(0, 1 - abs(Self.minutesOfDay(bedtime) - med) / 240)
            }
        }
        var parts: [(Double, Double)] = [(sufficiency, 0.55), (efficiency, 0.15)]
        if let restorative { parts.append((min(1, restorative / 0.40), 0.15)) }
        if let consistency { parts.append((consistency, 0.15)) }
        let wsum = parts.reduce(0) { $0 + $1.1 }
        let score = Int((100 * parts.reduce(0) { $0 + $1.0 * $1.1 } / wsum).rounded())

        var debt: TimeInterval = 0
        for i in 0..<7 { if let n = history.sleepNights[date.adding(days: -i)] { debt += max(0, need - n.asleepDuration) } }

        var factors = [
            ScoreFactor(id: "hours", title: "Hours vs need", value: Fmt.duration(asleep), baseline: "need \(Fmt.duration(need))",
                        effect: sufficiency * 2 - 1, weight: 0.55 / wsum),
            ScoreFactor(id: "efficiency", title: "Efficiency", value: "\(Int((efficiency * 100).rounded()))%", baseline: "time asleep in bed",
                        effect: (efficiency - 0.85) / 0.15, weight: 0.15 / wsum),
        ]
        if let restorative {
            factors.append(ScoreFactor(id: "restorative", title: "Deep + REM", value: "\(Int((restorative * 100).rounded()))%",
                                       baseline: "about 40% is typical", effect: min(1, restorative / 0.40) * 2 - 1, weight: 0.15 / wsum))
        }
        if let consistency {
            factors.append(ScoreFactor(id: "consistency", title: "Bedtime consistency", value: "\(Int((consistency * 100).rounded()))%",
                                       baseline: "vs your last 7 nights", effect: consistency * 2 - 1, weight: 0.15 / wsum))
        }
        return SleepPerformance(date: date, score: score, asleep: asleep, inBed: inBed, need: need, efficiency: efficiency,
                                restorativeShare: restorative, stages: stages, disturbances: disturbances, latencyMinutes: latency,
                                bedtime: bedtime, wake: night.end, consistency: consistency, debt: debt,
                                respiratoryRate: history.value(.respiratoryRate, on: date), factors: factors)
    }

    // MARK: Load

    static func loadValue(effort: Double) -> Double {
        let v = LoadResult.maximum * log1p(max(0, effort) / 250) / log1p(2_400 / 250)
        return (min(LoadResult.maximum, v) * 10).rounded() / 10
    }

    func effort(on date: LocalDate) -> Double? {
        let energy = history.value(.activeEnergy, on: date) ?? history.value(.steps, on: date).map { $0 * 0.042 }
        guard let energy else { return nil }
        return energy + 4 * (history.value(.exerciseMinutes, on: date) ?? 0)
    }

    public func load(on date: LocalDate) -> LoadResult? {
        guard let effort = effort(on: date) else { return nil }
        let recent = (1...28).compactMap { self.effort(on: date.adding(days: -$0)) }.map(Self.loadValue)
        var usual: ClosedRange<Double>?
        if recent.count >= 7, let lo = Stats.percentile(recent, 0.25), let hi = Stats.percentile(recent, 0.75) { usual = lo...hi }
        let energy = history.value(.activeEnergy, on: date)
        let exercise = history.value(.exerciseMinutes, on: date)
        let workouts = history.workouts.filter { LocalDate($0.start, calendar: .current) == date }.sorted { $0.start < $1.start }
        let value = Self.loadValue(effort: effort)
        var factors: [ScoreFactor] = []
        if let energy {
            let base = Stats.median((1...28).compactMap { history.value(.activeEnergy, on: date.adding(days: -$0)) })
            factors.append(ScoreFactor(id: "energy", title: "Active energy", value: "\(Fmt.int(energy)) kcal",
                                       baseline: base.map { "\(date == today ? "usual full day" : "usual") \(Fmt.int($0)) kcal" } ?? "building your usual",
                                       effect: base.map { max(-1, min(1, (energy - $0) / max($0, 1))) } ?? 0, weight: 0.7))
        }
        if let exercise {
            let base = Stats.median((1...28).compactMap { history.value(.exerciseMinutes, on: date.adding(days: -$0)) })
            factors.append(ScoreFactor(id: "exercise", title: "Exercise minutes", value: "\(Fmt.int(exercise)) min",
                                       baseline: base.map { "\(date == today ? "usual full day" : "usual") \(Fmt.int($0)) min" } ?? "building your usual",
                                       effect: base.map { max(-1, min(1, (exercise - $0) / max($0, 1))) } ?? 0, weight: 0.3))
        }
        return LoadResult(date: date, value: value, effort: effort, usualRange: usual, activeEnergy: energy, exerciseMinutes: exercise,
                          steps: history.value(.steps, on: date), workouts: workouts, factors: factors)
    }

    // MARK: Readiness

    public func readiness(on date: LocalDate) -> ReadinessResult {
        let hrvBase = baseline(.hrv, before: date, log: true)
        let rhrBase = baseline(.restingHeartRate, before: date)
        let window = DateSpan(date.adding(days: -30), date.adding(days: -1))
        let calibration = min(history.values(.hrv, in: window).count, history.values(.restingHeartRate, in: window).count, Self.calibrationDays)
        guard calibration >= Self.calibrationDays else {
            return ReadinessResult(date: date, score: nil, band: nil, calibrationDays: calibration, factors: [],
                                   summary: "Learning your usual heart signals: \(calibration) of \(Self.calibrationDays) nights so far.")
        }
        var parts: [(Double, Double)] = []
        var factors: [ScoreFactor] = []
        if let hrv = history.value(.hrv, on: date), let b = hrvBase {
            let z = (log(max(hrv, 1)) - b.mean) / max(b.sd, 0.05)
            let c = Self.sigmoid(z)
            parts.append((c, 0.5))
            factors.append(ScoreFactor(id: "hrv", title: "Heart rate variability", value: "\(Fmt.int(hrv)) ms",
                                       baseline: "usual \(Fmt.int(exp(b.mean))) ms", effect: c * 2 - 1, weight: 0.5))
        }
        if let rhr = history.value(.restingHeartRate, on: date), let b = rhrBase {
            let z = (rhr - b.mean) / max(b.sd, 1)
            let c = Self.sigmoid(-z)
            parts.append((c, 0.2))
            factors.append(ScoreFactor(id: "rhr", title: "Resting heart rate", value: "\(Fmt.int(rhr)) bpm",
                                       baseline: "usual \(Fmt.int(b.mean)) bpm", effect: c * 2 - 1, weight: 0.2))
        }
        if let s = sleep(on: date) {
            parts.append((Double(s.score) / 100, 0.3))
            factors.append(ScoreFactor(id: "sleep", title: "Sleep performance", value: "\(s.score)%",
                                       baseline: "\(Fmt.duration(s.asleep)) of \(Fmt.duration(s.need)) need",
                                       effect: Double(s.score) / 50 - 1, weight: 0.3))
        }
        guard parts.contains(where: { $0.1 >= 0.2 }) else {
            return ReadinessResult(date: date, score: nil, band: nil, calibrationDays: calibration, factors: factors,
                                   summary: "No overnight heart data yet for this day.")
        }
        let wsum = parts.reduce(0) { $0 + $1.1 }
        var score = 100 * parts.reduce(0) { $0 + $1.0 * $1.1 } / wsum
        if let resp = history.value(.respiratoryRate, on: date), let b = baseline(.respiratoryRate, before: date),
           (resp - b.mean) / max(b.sd, 0.3) > 2 {
            score -= 5
            factors.append(ScoreFactor(id: "resp", title: "Respiratory rate", value: "\(Fmt.decimal(resp)) /min",
                                       baseline: "usual \(Fmt.decimal(b.mean)) /min", effect: -0.6, weight: 0.05))
        }
        factors = factors.map { var f = $0; f.weight = f.weight / wsum; return f }
        let value = max(1, min(99, Int(score.rounded())))
        let band = ScoreBand.readiness(value)
        let summary = switch band {
        case .high: "Your overnight signals are stronger than your usual."
        case .moderate: "Your overnight signals are close to your usual."
        case .low: "Your overnight signals are lower than your usual. A lighter day may feel better."
        }
        return ReadinessResult(date: date, score: value, band: band, calibrationDays: calibration, factors: factors, summary: summary)
    }

    // MARK: Health monitor

    static func floorSD(_ m: HealthMetric) -> Double {
        switch m {
        case .restingHeartRate: 1.5
        case .hrv: 4
        case .respiratoryRate: 0.4
        case .oxygenSaturation: 0.008
        case .wristTemperature: 0.15
        default: 0
        }
    }

    public func vital(_ metric: HealthMetric, on date: LocalDate) -> VitalReading {
        let recent = history.values(metric, in: DateSpan(date.adding(days: -29), date))
            .map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        let value = history.value(metric, on: date)
        guard let b = baseline(metric, before: date), b.n >= 7 else {
            return VitalReading(metric: metric, value: value, mean: nil, range: nil, status: value == nil ? .noData : .learning, recent: recent)
        }
        let sd = max(b.sd, Self.floorSD(metric))
        let range = (b.mean - 1.5 * sd)...(b.mean + 1.5 * sd)
        let status: VitalReading.Status = value.map { range.contains($0) ? .within : ($0 > range.upperBound ? .above : .below) } ?? .noData
        return VitalReading(metric: metric, value: value, mean: b.mean, range: range, status: status, recent: recent)
    }

    public func monitor(on date: LocalDate) -> HealthMonitor {
        HealthMonitor(date: date, vitals: Self.monitored.map { vital($0, on: date) })
    }

    // MARK: History

    public func history(days: Int, endingOn end: LocalDate? = nil) -> [DayScores] {
        let last = end ?? today
        return (0..<days).reversed().map { i in
            let d = last.adding(days: -i)
            return DayScores(date: d, readiness: readiness(on: d).score, sleep: sleep(on: d)?.score, load: load(on: d)?.value)
        }
    }
}
