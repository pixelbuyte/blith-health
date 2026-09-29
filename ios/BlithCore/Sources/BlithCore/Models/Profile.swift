import Foundation

public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric, imperial
}

public enum UserGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case walkMore
    case understandHealth
    case weightManagement
    case buildStamina
    case recovery
    case consistency

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walkMore: "Walk more"
        case .understandHealth: "Understand my health"
        case .weightManagement: "Weight management"
        case .buildStamina: "Build stamina"
        case .recovery: "Recovery"
        case .consistency: "Stay consistent"
        }
    }

    public var symbol: String {
        switch self {
        case .walkMore: "figure.walk"
        case .understandHealth: "sparkle.magnifyingglass"
        case .weightManagement: "scalemass"
        case .buildStamina: "bolt.heart"
        case .recovery: "bed.double"
        case .consistency: "circle.dotted.circle"
        }
    }
}

/// What the user told us. Only what the product uses is collected.
public struct UserProfile: Codable, Hashable, Sendable {
    public var name: String
    public var goals: Set<UserGoal>
    public var units: UnitSystem
    /// Optional daily step target; when nil, consistency is measured against the personal baseline.
    public var dailyStepGoal: Int?
    /// Goal weight in kilograms, if the user set one.
    public var goalWeightKg: Double?
    public var firstWeekday: Int

    public init(name: String = "", goals: Set<UserGoal> = [], units: UnitSystem = .metric,
                dailyStepGoal: Int? = nil, goalWeightKg: Double? = nil, firstWeekday: Int = 2) {
        self.name = name
        self.goals = goals
        self.units = units
        self.dailyStepGoal = dailyStepGoal
        self.goalWeightKg = goalWeightKg
        self.firstWeekday = firstWeekday
    }

    enum CodingKeys: String, CodingKey { case name, goals, units, dailyStepGoal, goalWeightKg, firstWeekday }

    // Every field is decoded leniently so adding fields never wipes a saved profile.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        goals = (try? c.decode(Set<UserGoal>.self, forKey: .goals)) ?? []
        units = (try? c.decode(UnitSystem.self, forKey: .units)) ?? .metric
        dailyStepGoal = try? c.decodeIfPresent(Int.self, forKey: .dailyStepGoal)
        goalWeightKg = try? c.decodeIfPresent(Double.self, forKey: .goalWeightKg)
        firstWeekday = (try? c.decode(Int.self, forKey: .firstWeekday)) ?? 2
    }
}

/// Per-metric data state. Every screen renders all five.
public enum MetricAvailability: String, Codable, Sendable {
    /// Recent data exists.
    case available
    /// Permission was requested but nothing came back (HealthKit never reveals whether read
    /// access was denied, so "no data" and "not allowed" look identical to the app).
    case noData
    /// The user didn't connect this category.
    case notAuthorized
    /// This device or provider can't record it.
    case unsupported
    /// Data exists but the newest value is older than `metric.staleAfterDays`.
    case stale
}
