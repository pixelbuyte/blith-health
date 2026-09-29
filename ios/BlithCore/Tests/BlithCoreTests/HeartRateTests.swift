import Foundation
import Testing
@testable import BlithCore

struct HeartRateTests {
    private let source = SourceRef(provider: .appleHealth, name: "Watch", identifier: "watch")
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func paceMatchesMeasuredBPM() {
        for (bpm, seconds) in [(60.0, 1.0), (120, 0.5), (180, 1.0 / 3.0)] {
            let reading = HeartRateReading(bpm: bpm, measuredAt: now, source: source)
            #expect(reading?.beatInterval == seconds)
        }
    }

    @Test func invalidValuesCannotDriveAnimation() {
        for bpm in [0, -1, Double.nan, Double.infinity, 401] {
            #expect(HeartRateReading(bpm: bpm, measuredAt: now, source: source) == nil)
        }
    }

    @Test func freshnessUsesMeasurementTimeAndRejectsFutureSamples() {
        let reading = HeartRateReading(bpm: 72, measuredAt: now, source: source)!
        #expect(reading.isRecent(at: now))
        #expect(reading.isRecent(at: now.addingTimeInterval(59)))
        #expect(!reading.isRecent(at: now.addingTimeInterval(60)))
        #expect(!reading.isRecent(at: now.addingTimeInterval(-1)))
    }
}
