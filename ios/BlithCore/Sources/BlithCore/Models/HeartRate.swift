import Foundation

// MARK: - Live heart rate
//
// The rest of BlithCore deals in daily aggregates: one resting heart rate per night, one HRV per
// night. A live pulse is a different kind of signal — it is a single instant, it is only worth
// showing while it is fresh, and it is the one number a person can feel. It therefore gets its own
// small model instead of a `HealthMetric` case, so nothing in the daily pipeline has to change.

/// One heart rate reading at one instant.
public struct LiveHeartRate: Sendable, Hashable, Identifiable {
    /// Beats per minute as recorded. Never rounded here; formatting is the UI's job.
    public var bpm: Double
    public var at: Date
    /// Where it came from ("Apple Watch"), shown so a reading is never anonymous.
    public var sourceName: String?
    /// True when the sample came from a watch actively on the wrist rather than a backfill.
    public var isWatch: Bool

    public var id: Date { at }

    public init(bpm: Double, at: Date, sourceName: String? = nil, isWatch: Bool = false) {
        self.bpm = bpm
        self.at = at
        self.sourceName = sourceName
        self.isWatch = isWatch
    }

    /// Seconds between beats at this rate — the period the pounding animation runs at, so the
    /// animation rate *is* the pulse. Clamped to a plausible human range (30–220 bpm).
    public var beatInterval: TimeInterval { 60 / Swift.min(Swift.max(bpm, 30), 220) }

    /// A reading older than this is history, not a pulse. Watches sample every few seconds while
    /// you move and every few minutes at rest, so two minutes is the honest limit for "now".
    public static let freshWindow: TimeInterval = 120

    public func isFresh(now: Date, within: TimeInterval = LiveHeartRate.freshWindow) -> Bool {
        let age = now.timeIntervalSince(at)
        return age >= -5 && age <= within
    }

    public func age(now: Date) -> TimeInterval { Swift.max(0, now.timeIntervalSince(at)) }
}

/// Effort bands measured against *the person's own* resting heart rate rather than a population
/// max-HR formula, which needs an age Blith never asks for.
public enum HeartRateZone: String, Sendable, CaseIterable, Identifiable {
    case resting, light, moderate, vigorous, peak

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .resting: "Resting"
        case .light: "Light"
        case .moderate: "Moderate"
        case .vigorous: "Vigorous"
        case .peak: "Peak"
        }
    }

    /// Said in shape as well as colour, so a zone never depends on hue alone.
    public var glyph: String {
        switch self {
        case .resting: "moon.zzz"
        case .light: "figure.walk"
        case .moderate: "figure.walk.motion"
        case .vigorous: "figure.run"
        case .peak: "flame"
        }
    }

    /// 0 … 4, for ramps and meters.
    public var step: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Multiples of the person's resting heart rate at which each band starts.
    static let thresholds: [(zone: HeartRateZone, multiple: Double)] = [
        (.light, 1.18), (.moderate, 1.55), (.vigorous, 1.95), (.peak, 2.35),
    ]

    /// When no resting baseline has been learned yet, a neutral adult resting rate is assumed so
    /// the widget still says something sensible. The UI must label this as an estimate.
    public static let assumedResting: Double = 62

    public static func of(bpm: Double, resting: Double?) -> HeartRateZone {
        let base = resting ?? assumedResting
        guard base > 0 else { return .resting }
        let ratio = bpm / base
        var zone = HeartRateZone.resting
        for t in thresholds where ratio >= t.multiple { zone = t.zone }
        return zone
    }
}

/// A live pulse placed against the person's own history: the zone it falls in, and how it compares
/// with the resting rate Blith has learned from their nights.
public struct HeartRatePulse: Sendable, Hashable {
    public var reading: LiveHeartRate
    /// Resting heart rate learned from recent nights, if there is one.
    public var restingBaseline: Double?
    public var zone: HeartRateZone
    /// Difference from the resting baseline in bpm, positive when above it.
    public var aboveResting: Double?
    /// True when the baseline is assumed rather than learned.
    public var isEstimatedBaseline: Bool

    public init(reading: LiveHeartRate, restingBaseline: Double?) {
        self.reading = reading
        self.restingBaseline = restingBaseline
        zone = HeartRateZone.of(bpm: reading.bpm, resting: restingBaseline)
        aboveResting = restingBaseline.map { reading.bpm - $0 }
        isEstimatedBaseline = restingBaseline == nil
    }

    public var bpm: Double { reading.bpm }
    public var beatInterval: TimeInterval { reading.beatInterval }

    /// One plain sentence, never a verdict. "38 above your resting 54" beats "elevated".
    public var summary: String {
        guard let base = restingBaseline, let delta = aboveResting else {
            return "\(Int(bpm.rounded())) bpm right now."
        }
        let b = Int(base.rounded())
        if delta >= 4 { return "\(Int(delta.rounded())) above your resting \(b)." }
        if delta <= -4 { return "\(Int((-delta).rounded())) below your resting \(b)." }
        return "Right at your resting \(b)."
    }
}

/// A short rolling window of readings — what the live trace and the min/max chips draw from.
/// Capped by age *and* count so it can run for hours without growing.
public struct HeartRateTrail: Sendable {
    public private(set) var samples: [LiveHeartRate] = []
    public var window: TimeInterval
    public var limit: Int

    public init(window: TimeInterval = 180, limit: Int = 240) {
        self.window = window
        self.limit = limit
    }

    public var latest: LiveHeartRate? { samples.last }
    public var isEmpty: Bool { samples.isEmpty }
    public var values: [Double] { samples.map(\.bpm) }
    public var lowest: Double? { values.min() }
    public var highest: Double? { values.max() }

    public var mean: Double? {
        guard !samples.isEmpty else { return nil }
        return values.reduce(0, +) / Double(samples.count)
    }

    /// Adds a reading, keeping the trail sorted, de-duplicated by instant, and trimmed.
    public mutating func add(_ reading: LiveHeartRate, now: Date? = nil) {
        if let i = samples.firstIndex(where: { $0.at == reading.at }) {
            samples[i] = reading
        } else {
            samples.append(reading)
            if samples.count > 1, samples[samples.count - 2].at > reading.at {
                samples.sort { $0.at < $1.at }
            }
        }
        trim(now: now ?? samples.last?.at ?? reading.at)
    }

    public mutating func add(contentsOf readings: [LiveHeartRate], now: Date? = nil) {
        for r in readings { add(r, now: now) }
    }

    public mutating func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        samples.removeAll { $0.at < cutoff }
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }

    /// Direction over the trail: positive when the pulse is climbing.
    public var drift: Double? {
        guard samples.count >= 4 else { return nil }
        let half = samples.count / 2
        let older = samples.prefix(half).map(\.bpm)
        let newer = samples.suffix(samples.count - half).map(\.bpm)
        guard !older.isEmpty, !newer.isEmpty else { return nil }
        return newer.reduce(0, +) / Double(newer.count) - older.reduce(0, +) / Double(older.count)
    }
}
