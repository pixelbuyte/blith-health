import Foundation

/// A raw measurement, deliberately separate from daily resting/walking averages.
public struct HeartRateReading: Sendable, Equatable {
    public let bpm: Double
    public let measuredAt: Date
    public let source: SourceRef

    public init?(bpm: Double, measuredAt: Date, source: SourceRef) {
        guard bpm.isFinite, (1...400).contains(bpm) else { return nil }
        self.bpm = bpm
        self.measuredAt = measuredAt
        self.source = source
    }

    public var beatInterval: TimeInterval { 60 / bpm }

    /// A UI freshness window, not a statement of clinical validity or a live sensor feed.
    public func isRecent(at now: Date) -> Bool {
        let age = now.timeIntervalSince(measuredAt)
        return age >= 0 && age < 60
    }
}
