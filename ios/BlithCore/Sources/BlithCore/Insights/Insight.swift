import Foundation

/// A place in the app a card, insight or chat widget can open.
public enum DeepLink: Codable, Hashable, Sendable {
    case today
    case walk(WalkPeriod)
    case sleep(LocalDate?)
    case weight
    case insight(String)
    case sources
    /// Walk tab, month range, with this day selected.
    case walkDay(LocalDate)
    /// Body tab, optionally focused on a note.
    case body(String?)
    /// Readiness detail for a day (nil = today).
    case readiness(LocalDate?)
}

public enum InsightKind: String, Codable, Sendable, CaseIterable {
    case baselineChange, consistency, momentum, dayOfWeek, weekdayDecline, timing, personalBest
    case longTermChange, pace, weightTrend, weightActivity, rebound, sleepMovement, sleepTiming, noteContext

    /// Insights in the same family never appear together on Today.
    public var family: String {
        switch self {
        case .baselineChange, .momentum, .longTermChange: "volume"
        case .weightTrend, .weightActivity: "weight"
        default: rawValue
        }
    }
}

public enum InsightConfidence: String, Codable, Sendable {
    case low, moderate, high

    public var label: String {
        switch self {
        case .low: "Early signal"
        case .moderate: "Moderate"
        case .high: "Consistent data"
        }
    }
}

/// A labelled value for the small evidence chart on an insight card.
public struct EvidencePoint: Codable, Hashable, Sendable, Identifiable {
    public var label: String
    public var value: Double
    /// Marks the value the insight is about (drawn in the accent color).
    public var highlighted: Bool
    public var id: String { label }

    public init(_ label: String, _ value: Double, highlighted: Bool = false) {
        self.label = label
        self.value = value
        self.highlighted = highlighted
    }
}

public struct EvidenceRow: Codable, Hashable, Sendable, Identifiable {
    public var label: String
    public var value: String
    public var id: String { label }

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// A deterministic, explainable observation about the user. Headline and explanation are
/// written from calculated values; `evidence` is what the "Why am I seeing this?" sheet shows.
public struct Insight: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: InsightKind
    public var headline: String
    public var explanation: String
    public var metric: HealthMetric
    public var secondaryMetric: HealthMetric?
    public var currentValue: Double?
    public var comparisonValue: Double?
    /// Fractional change (0.11 = +11%) where meaningful.
    public var change: Double?
    public var currentRange: DateSpan
    public var comparisonRange: DateSpan?
    public var confidence: InsightConfidence
    public var sampleCount: Int
    public var source: String
    /// Always present for relationships between metrics: correlation is not causation.
    public var caveat: String?
    public var evidence: [EvidenceRow]
    /// Big figure shown on the card ("+11%"), with its caption.
    public var emphasis: String?
    public var emphasisCaption: String?
    public var score: Double
    public var createdAt: Date
    public var link: DeepLink
    /// Numbers behind the insight, for its evidence chart.
    public var points: [EvidencePoint] = []

    public init(id: String, kind: InsightKind, headline: String, explanation: String, metric: HealthMetric,
                secondaryMetric: HealthMetric? = nil, currentValue: Double? = nil, comparisonValue: Double? = nil,
                change: Double? = nil, currentRange: DateSpan, comparisonRange: DateSpan? = nil,
                confidence: InsightConfidence, sampleCount: Int, source: String, caveat: String? = nil,
                evidence: [EvidenceRow], emphasis: String? = nil, emphasisCaption: String? = nil,
                score: Double, createdAt: Date, link: DeepLink) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.explanation = explanation
        self.metric = metric
        self.secondaryMetric = secondaryMetric
        self.currentValue = currentValue
        self.comparisonValue = comparisonValue
        self.change = change
        self.currentRange = currentRange
        self.comparisonRange = comparisonRange
        self.confidence = confidence
        self.sampleCount = sampleCount
        self.source = source
        self.caveat = caveat
        self.evidence = evidence
        self.emphasis = emphasis
        self.emphasisCaption = emphasisCaption
        self.score = score
        self.createdAt = createdAt
        self.link = link
    }
}

/// A plain-language observation about how this person walks (Walk DNA).
public struct PatternObservation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var symbol: String
    public var text: String
    public var detail: String

    public init(id: String, symbol: String, text: String, detail: String) {
        self.id = id
        self.symbol = symbol
        self.text = text
        self.detail = detail
    }
}

extension Insight {
    func with(points: [EvidencePoint]) -> Insight {
        var copy = self
        copy.points = points
        return copy
    }
}
