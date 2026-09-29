import Foundation

/// What the user did in the app (not health data). Kept on device.
public struct Engagement: Codable, Hashable, Sendable {
    public var checkIns: Set<LocalDate>
    public var questionsAsked: Int

    public init(checkIns: Set<LocalDate> = [], questionsAsked: Int = 0) {
        self.checkIns = checkIns
        self.questionsAsked = questionsAsked
    }

    enum CodingKeys: String, CodingKey { case checkIns, questionsAsked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkIns = (try? c.decode(Set<LocalDate>.self, forKey: .checkIns)) ?? []
        questionsAsked = (try? c.decode(Int.self, forKey: .questionsAsked)) ?? 0
    }
}

/// A gentle daily check-in streak. Missing a day ends the current run but never touches the
/// total or the best run.
public struct CheckInStreak: Sendable, Hashable {
    public var current: Int
    public var best: Int
    public var total: Int
    public var checkedInToday: Bool

    public static func compute(_ days: Set<LocalDate>, today: LocalDate) -> CheckInStreak {
        let sorted = days.sorted()
        var best = 0, run = 0
        var previous: LocalDate?
        for d in sorted {
            run = (previous.map { $0.adding(days: 1) == d } ?? false) ? run + 1 : 1
            best = max(best, run)
            previous = d
        }
        // Current run ends today, or yesterday if today isn't checked in yet.
        var cursor = days.contains(today) ? today : today.adding(days: -1)
        var current = 0
        while days.contains(cursor) {
            current += 1
            cursor = cursor.adding(days: -1)
        }
        return CheckInStreak(current: current, best: best, total: days.count, checkedInToday: days.contains(today))
    }
}

public struct Achievement: Identifiable, Hashable, Sendable {
    public enum Family: String, Sendable { case walking, consistency, history, sleep, body, ask, checkIn }

    public var id: String
    public var title: String
    public var detail: String
    public var family: Family
    /// Date it was earned, from real data.
    public var unlockedOn: LocalDate?
    /// 0…1 toward unlocking.
    public var progress: Double
    public var progressText: String

    public var isUnlocked: Bool { unlockedOn != nil }
}

/// Milestones earned from the user's own records. No points, no penalties: each one is a fact
/// about their history with the day it became true.
public enum AchievementEngine {
    public static func evaluate(history h: HealthHistory, engagement: Engagement, today: LocalDate,
                                threshold: Double?) -> [Achievement] {
        let steps = (h.daily[.steps] ?? [:]).filter { $0.key < today || $0.key == today }
        let sortedDays = steps.keys.sorted()
        var out: [Achievement] = []

        func nth(_ n: Int, of dates: [LocalDate]) -> LocalDate? { dates.count >= n ? dates[n - 1] : nil }

        out.append(Achievement(id: "baseline", title: "Baseline ready", detail: "7 days of walking history, enough to know your normal.",
                               family: .history, unlockedOn: nth(7, of: sortedDays),
                               progress: min(1, Double(sortedDays.count) / 7), progressText: "\(min(sortedDays.count, 7)) of 7 days"))
        out.append(Achievement(id: "month", title: "A month of you", detail: "30 days of history to compare against.",
                               family: .history, unlockedOn: nth(30, of: sortedDays),
                               progress: min(1, Double(sortedDays.count) / 30), progressText: "\(min(sortedDays.count, 30)) of 30 days"))
        let tenK = sortedDays.filter { (steps[$0]?.value ?? 0) >= 10_000 }
        let best = steps.values.map(\.value).max() ?? 0
        out.append(Achievement(id: "tenk", title: "10K day", detail: "A day with 10,000 steps or more.",
                               family: .walking, unlockedOn: tenK.first,
                               progress: min(1, best / 10_000), progressText: tenK.isEmpty ? "Best so far \(Fmt.int(best))" : "\(tenK.count) so far"))
        // Steady week: 5 of any 7 consecutive days at/above the user's threshold.
        var steady: LocalDate?
        var bestWindow = 0
        if let t = threshold, let first = sortedDays.first {
            for end in LocalDate.range(first.adding(days: 6), today) {
                let hits = LocalDate.range(end.adding(days: -6), end).filter { (steps[$0]?.value ?? 0) >= t }.count
                bestWindow = max(bestWindow, hits)
                if hits >= 5 { steady = end; break }
            }
        }
        out.append(Achievement(id: "steady", title: "Steady week", detail: "5 days in a week at or near your usual walking.",
                               family: .consistency, unlockedOn: steady,
                               progress: min(1, Double(bestWindow) / 5), progressText: steady == nil ? "Best week \(bestWindow) of 5" : "Earned"))
        // Seven nights of sleep recorded in a row.
        let nights = h.sleepNights.keys.sorted()
        var run = 0, bestRun = 0
        var sleepDate: LocalDate?
        var prev: LocalDate?
        for d in nights {
            run = (prev.map { $0.adding(days: 1) == d } ?? false) ? run + 1 : 1
            bestRun = max(bestRun, run)
            if run == 7 && sleepDate == nil { sleepDate = d }
            prev = d
        }
        out.append(Achievement(id: "sleepweek", title: "Seven nights", detail: "Sleep recorded 7 nights in a row.",
                               family: .sleep, unlockedOn: sleepDate,
                               progress: min(1, Double(bestRun) / 7), progressText: "\(min(bestRun, 7)) of 7 nights"))
        let firstNote = h.events.map(\.createdAt).min().map { LocalDate($0, calendar: .current) }
        out.append(Achievement(id: "firstnote", title: "First body note", detail: "Your first note on the body map.",
                               family: .body, unlockedOn: h.events.isEmpty ? nil : (firstNote ?? today),
                               progress: h.events.isEmpty ? 0 : 1, progressText: h.events.isEmpty ? "Add a note in Body" : "Earned"))
        out.append(Achievement(id: "firstask", title: "Curious", detail: "Asked Blith your first question.",
                               family: .ask, unlockedOn: engagement.questionsAsked > 0 ? today : nil,
                               progress: engagement.questionsAsked > 0 ? 1 : 0, progressText: engagement.questionsAsked > 0 ? "Earned" : "Ask anything"))
        let checks = engagement.checkIns.sorted()
        for (n, title) in [(3, "Three check-ins"), (7, "A week of check-ins"), (30, "Thirty check-ins")] {
            out.append(Achievement(id: "checkin\(n)", title: title, detail: "Opened Blith on \(n) different days.",
                                   family: .checkIn, unlockedOn: nth(n, of: checks),
                                   progress: min(1, Double(checks.count) / Double(n)), progressText: "\(min(checks.count, n)) of \(n)"))
        }
        return out
    }
}

/// Bed and wake times per night, in minutes relative to midnight (11 PM = −60, 7 AM = 420).
public struct SleepTimingPoint: Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var bedMinutes: Double
    public var wakeMinutes: Double
    public var asleep: Double
    public var id: LocalDate { date }
}

extension SleepAnalytics {
    public static func timing(_ ctx: AnalyticsContext, nights: Int = 28) -> [SleepTimingPoint] {
        LocalDate.range(ctx.today.adding(days: -(nights - 1)), ctx.today).compactMap { d in
            guard let n = ctx.history.sleepNights[d], let s = n.start, let e = n.end else { return nil }
            let midnight = d.startDate(in: ctx.calendar)
            return SleepTimingPoint(date: d, bedMinutes: s.timeIntervalSince(midnight) / 60,
                                    wakeMinutes: e.timeIntervalSince(midnight) / 60, asleep: n.asleepDuration)
        }
    }

    /// "11:40 PM" from minutes relative to midnight.
    public static func clock(_ minutes: Double) -> String {
        var m = Int(minutes.rounded())
        m = ((m % 1440) + 1440) % 1440
        let h = m / 60, mm = m % 60
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", mm)) \(h < 12 ? "AM" : "PM")"
    }
}
