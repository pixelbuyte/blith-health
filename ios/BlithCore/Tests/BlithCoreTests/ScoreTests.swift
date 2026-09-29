import Foundation
import Testing
@testable import BlithCore

struct ScoreTests {
    static func vitals(days: ClosedRange<Int>, hrv: (Int) -> Double = { _ in 45 }, rhr: (Int) -> Double = { _ in 58 }) -> HealthHistory {
        var h = T.history(steps: T.constant(7_000, days: days))
        var hv: [LocalDate: DailyAggregate] = [:]
        var rv: [LocalDate: DailyAggregate] = [:]
        for ago in days {
            let d = T.today.adding(days: -ago)
            // Small alternating noise so baselines have a spread.
            let wobble = ago % 2 == 0 ? 1.0 : -1.0
            hv[d] = DailyAggregate(date: d, metric: .hrv, value: hrv(ago) + wobble * 3)
            rv[d] = DailyAggregate(date: d, metric: .restingHeartRate, value: rhr(ago) + wobble)
        }
        h.daily[.hrv] = hv
        h.daily[.restingHeartRate] = rv
        return h
    }

    @Test func readinessCalibratesBeforeFourteenNights() {
        let h = Self.vitals(days: 0...9)
        let r = ScoreEngine(history: h, today: T.today).readiness(on: T.today)
        #expect(r.score == nil)
        #expect(r.isCalibrating)
        #expect(r.calibrationDays == 9)
    }

    @Test func readinessFollowsHRVAgainstPersonalBaseline() {
        let high = ScoreEngine(history: Self.vitals(days: 0...40, hrv: { $0 == 0 ? 70 : 45 }, rhr: { $0 == 0 ? 54 : 58 }), today: T.today).readiness(on: T.today)
        let low = ScoreEngine(history: Self.vitals(days: 0...40, hrv: { $0 == 0 ? 28 : 45 }, rhr: { $0 == 0 ? 64 : 58 }), today: T.today).readiness(on: T.today)
        #expect((high.score ?? 0) >= 67)
        #expect((low.score ?? 100) <= 33)
        #expect(high.band == .high)
        #expect(low.band == .low)
        #expect(high.factors.contains { $0.id == "hrv" && $0.effect > 0 })
        #expect(abs(high.factors.reduce(0) { $0 + $1.weight } - 1) < 0.001)
    }

    @Test func loadIsMonotonicAndBounded() {
        let a = ScoreEngine.loadValue(effort: 200)
        let b = ScoreEngine.loadValue(effort: 800)
        let c = ScoreEngine.loadValue(effort: 100_000)
        #expect(a < b)
        #expect(c == LoadResult.maximum)
        #expect(ScoreEngine.loadValue(effort: 0) == 0)
    }

    @Test func sleepScoreRewardsMeetingNeed() {
        var h = HealthHistory(origin: .appleHealth)
        func night(_ ago: Int, hours: Double) -> SleepNight {
            let d = T.today.adding(days: -ago)
            let wake = T.date(d, hour: 7)
            let start = wake.addingTimeInterval(-hours * 3600)
            return SleepNight(date: d, segments: [
                SleepSegment(start: start, end: start.addingTimeInterval(hours * 3600 * 0.6), stage: .core, source: T.source),
                SleepSegment(start: start.addingTimeInterval(hours * 3600 * 0.6), end: start.addingTimeInterval(hours * 3600 * 0.8), stage: .deep, source: T.source),
                SleepSegment(start: start.addingTimeInterval(hours * 3600 * 0.8), end: wake, stage: .rem, source: T.source),
            ], source: T.source)
        }
        for ago in 1...20 { h.sleepNights[T.today.adding(days: -ago)] = night(ago, hours: 7.5) }
        h.sleepNights[T.today] = night(0, hours: 7.5)
        let full = ScoreEngine(history: h, today: T.today).sleep(on: T.today)
        h.sleepNights[T.today] = night(0, hours: 4.5)
        let short = ScoreEngine(history: h, today: T.today).sleep(on: T.today)
        #expect((full?.score ?? 0) >= 90)
        #expect((short?.score ?? 100) < (full?.score ?? 0) - 20)
        #expect(full?.need == 7.5 * 3600)
        #expect((short?.debt ?? 0) >= 3 * 3600 - 1)
    }

    @Test func healthMonitorFlagsValuesOutsidePersonalRange() {
        var h = Self.vitals(days: 0...30)
        h.daily[.restingHeartRate]?[T.today] = DailyAggregate(date: T.today, metric: .restingHeartRate, value: 70)
        let m = ScoreEngine(history: h, today: T.today).monitor(on: T.today)
        #expect(m.vitals.first { $0.metric == .restingHeartRate }?.status == .above)
        #expect(m.vitals.first { $0.metric == .hrv }?.status == .within)
        #expect(m.vitals.first { $0.metric == .oxygenSaturation }?.status == .noData)
    }

    @Test func demoScoresAreComputedForTheBalancedYear() async throws {
        let provider = MockHealthProvider(scenario: .balanced, now: { T.now })
        let engine = SyncEngine(provider: provider, calendar: T.calendar, now: { T.now })
        var h = HealthHistory(origin: .demo(.balanced))
        h.requestedCategories = Set(HealthCategory.allCases)
        h = try await engine.initialImport(into: h)
        let snap = HealthSnapshot.build(history: h, profile: UserProfile(), now: T.now, calendar: T.calendar)
        #expect(snap.readiness.score != nil)
        #expect(snap.sleepScore != nil)
        #expect(snap.load != nil)
        #expect(snap.monitor.measured == 5)
        let bands = Set(snap.scoreHistory.compactMap(\.band))
        #expect(bands.count >= 2)
    }
}
