import Foundation
import Testing
@testable import BlithCore

struct HeartRateTests {
    static let now = T.now

    // MARK: Beat timing

    @Test func beatIntervalIsTheReciprocalOfRate() {
        #expect(abs(LiveHeartRate(bpm: 60, at: Self.now).beatInterval - 1) < 0.0001)
        #expect(abs(LiveHeartRate(bpm: 120, at: Self.now).beatInterval - 0.5) < 0.0001)
    }

    @Test func beatIntervalClampsImplausibleRates() {
        // A faster pound than 220 bpm would only ever be a bad sample; it must not become a blur.
        #expect(LiveHeartRate(bpm: 900, at: Self.now).beatInterval >= 60 / 220)
        #expect(LiveHeartRate(bpm: 1, at: Self.now).beatInterval <= 60 / 30)
    }

    // MARK: Freshness

    @Test func readingIsFreshOnlyInsideItsWindow() {
        let r = LiveHeartRate(bpm: 72, at: Self.now.addingTimeInterval(-30))
        #expect(r.isFresh(now: Self.now))
        let stale = LiveHeartRate(bpm: 72, at: Self.now.addingTimeInterval(-600))
        #expect(!stale.isFresh(now: Self.now))
        #expect(stale.age(now: Self.now) == 600)
    }

    @Test func ageIsNeverNegative() {
        let ahead = LiveHeartRate(bpm: 72, at: Self.now.addingTimeInterval(3))
        #expect(ahead.age(now: Self.now) == 0)
        #expect(ahead.isFresh(now: Self.now))
    }

    // MARK: Zones against the person's own resting rate

    @Test func zonesAreRelativeToPersonalResting() {
        // The same 95 bpm is light effort for a 50 bpm heart and moderate for a 70 bpm one.
        #expect(HeartRateZone.of(bpm: 95, resting: 50) == .moderate)
        #expect(HeartRateZone.of(bpm: 95, resting: 70) == .light)
        #expect(HeartRateZone.of(bpm: 52, resting: 50) == .resting)
        #expect(HeartRateZone.of(bpm: 140, resting: 55) == .peak)
    }

    @Test func zonesRiseMonotonically() {
        let resting = 60.0
        var last = -1
        for bpm in stride(from: 50.0, through: 200.0, by: 5) {
            let step = HeartRateZone.of(bpm: bpm, resting: resting).step
            #expect(step >= last)
            last = step
        }
    }

    @Test func zoneFallsBackToAnAssumedRestingRate() {
        #expect(HeartRateZone.of(bpm: 62, resting: nil) == .resting)
        #expect(HeartRateZone.of(bpm: 200, resting: nil) == .peak)
        #expect(HeartRateZone.of(bpm: 70, resting: 0) == .resting)
    }

    // MARK: Pulse against the baseline

    @Test func pulseComparesWithTheLearnedRestingRate() {
        let p = HeartRatePulse(reading: LiveHeartRate(bpm: 92, at: Self.now), restingBaseline: 54)
        #expect(p.zone == .moderate)
        #expect(p.aboveResting == 38)
        #expect(!p.isEstimatedBaseline)
        #expect(p.summary == "38 above your resting 54.")
    }

    @Test func pulseSaysWhenItIsAtRest() {
        let p = HeartRatePulse(reading: LiveHeartRate(bpm: 56, at: Self.now), restingBaseline: 54)
        #expect(p.summary == "Right at your resting 54.")
        let below = HeartRatePulse(reading: LiveHeartRate(bpm: 48, at: Self.now), restingBaseline: 54)
        #expect(below.summary == "6 below your resting 54.")
    }

    @Test func pulseWithoutABaselineIsMarkedEstimated() {
        let p = HeartRatePulse(reading: LiveHeartRate(bpm: 70, at: Self.now), restingBaseline: nil)
        #expect(p.isEstimatedBaseline)
        #expect(p.aboveResting == nil)
        #expect(p.summary == "70 bpm right now.")
    }

    // MARK: Trail

    @Test func trailKeepsOnlyItsWindow() {
        var trail = HeartRateTrail(window: 60)
        trail.add(LiveHeartRate(bpm: 60, at: Self.now.addingTimeInterval(-120)))
        trail.add(LiveHeartRate(bpm: 80, at: Self.now))
        #expect(trail.samples.count == 1)
        #expect(trail.latest?.bpm == 80)
    }

    @Test func trailSortsOutOfOrderSamplesAndDeduplicates() {
        var trail = HeartRateTrail(window: 600)
        let t1 = Self.now.addingTimeInterval(-20)
        trail.add(LiveHeartRate(bpm: 70, at: Self.now))
        trail.add(LiveHeartRate(bpm: 65, at: t1))
        #expect(trail.values == [65, 70])
        trail.add(LiveHeartRate(bpm: 66, at: t1))
        #expect(trail.samples.count == 2)
        #expect(trail.values == [66, 70])
    }

    @Test func trailRespectsItsCountLimit() {
        var trail = HeartRateTrail(window: 100_000, limit: 10)
        for i in 0..<50 {
            trail.add(LiveHeartRate(bpm: Double(60 + i), at: Self.now.addingTimeInterval(Double(i))))
        }
        #expect(trail.samples.count == 10)
        #expect(trail.latest?.bpm == 109)
    }

    @Test func trailSummarisesItsRange() {
        var trail = HeartRateTrail(window: 600)
        for (i, bpm) in [72.0, 88, 61, 95].enumerated() {
            trail.add(LiveHeartRate(bpm: bpm, at: Self.now.addingTimeInterval(Double(i))))
        }
        #expect(trail.lowest == 61)
        #expect(trail.highest == 95)
        #expect(abs((trail.mean ?? 0) - 79) < 0.001)
    }

    @Test func trailDriftDetectsAClimbingPulse() {
        var rising = HeartRateTrail(window: 600)
        for (i, bpm) in [60.0, 62, 80, 84].enumerated() {
            rising.add(LiveHeartRate(bpm: bpm, at: Self.now.addingTimeInterval(Double(i))))
        }
        #expect((rising.drift ?? 0) > 0)

        var flat = HeartRateTrail(window: 600)
        for i in 0..<6 { flat.add(LiveHeartRate(bpm: 70, at: Self.now.addingTimeInterval(Double(i)))) }
        #expect(abs(flat.drift ?? 1) < 0.001)
    }

    @Test func emptyTrailHasNoStatistics() {
        let trail = HeartRateTrail()
        #expect(trail.isEmpty)
        #expect(trail.mean == nil)
        #expect(trail.drift == nil)
        #expect(trail.latest == nil)
    }
}
