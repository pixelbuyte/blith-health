import Foundation

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleepUnspecified, core, deep, rem

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }

    public var displayName: String {
        switch self {
        case .inBed: "In bed"
        case .awake: "Awake"
        case .asleepUnspecified: "Asleep"
        case .core: "Core"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }
}

/// One raw sleep-analysis sample.
public struct SleepSegment: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    public var source: SourceRef

    public init(start: Date, end: Date, stage: SleepStage, source: SourceRef) {
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// A night of sleep, attributed to the local day the user woke up on.
public struct SleepNight: Codable, Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var segments: [SleepSegment]
    public var source: SourceRef
    public var id: LocalDate { date }

    public init(date: LocalDate, segments: [SleepSegment], source: SourceRef) {
        self.date = date
        self.segments = segments.sorted { $0.start < $1.start }
        self.source = source
    }

    public var start: Date? { segments.first?.start }
    public var end: Date? { segments.map(\.end).max() }

    /// Time asleep, counting overlapping stage samples once.
    public var asleepDuration: TimeInterval {
        Self.unionDuration(segments.filter { $0.stage.isAsleep })
    }

    public var inBedDuration: TimeInterval {
        guard let start, let end else { return 0 }
        return end.timeIntervalSince(start)
    }

    public var hasStages: Bool { segments.contains { [.core, .deep, .rem].contains($0.stage) } }

    public func duration(of stage: SleepStage) -> TimeInterval {
        Self.unionDuration(segments.filter { $0.stage == stage })
    }

    public static func unionDuration(_ segments: [SleepSegment]) -> TimeInterval {
        let sorted = segments.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?
        for s in sorted {
            if let cs = currentStart, let ce = currentEnd {
                if s.start <= ce {
                    currentEnd = max(ce, s.end)
                } else {
                    total += ce.timeIntervalSince(cs)
                    currentStart = s.start
                    currentEnd = s.end
                }
            } else {
                currentStart = s.start
                currentEnd = s.end
            }
        }
        if let cs = currentStart, let ce = currentEnd { total += ce.timeIntervalSince(cs) }
        return total
    }
}

public struct WorkoutRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var activity: String
    public var start: Date
    public var end: Date
    public var energyKcal: Double?
    public var distanceMeters: Double?
    public var source: SourceRef

    public init(id: String, activity: String, start: Date, end: Date, energyKcal: Double?, distanceMeters: Double?, source: SourceRef) {
        self.id = id
        self.activity = activity
        self.start = start
        self.end = end
        self.energyKcal = energyKcal
        self.distanceMeters = distanceMeters
        self.source = source
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var isWalking: Bool { activity.lowercased().contains("walk") || activity.lowercased().contains("hik") }
}

