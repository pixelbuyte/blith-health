import BlithCore
import Foundation
import HealthKit
import Observation

/// Streams the most recent heart rate samples so the home screen can show a pulse that is actually
/// beating now, rather than last night's resting average.
///
/// HealthKit has no "current" heart rate: a watch writes samples every few seconds during a
/// workout and every few minutes at rest, and they arrive in batches after the fact. An anchored
/// query with a long-running result sequence is the closest honest thing — it delivers each new
/// sample as it lands, and the anchor means a sample is never counted twice.
///
/// Nothing here computes a score. The pulse is displayed, not interpreted.
@MainActor
@Observable
final class HeartRateMonitor {
    /// The freshest reading, whether or not it is still fresh — the view decides how to present age.
    private(set) var latest: LiveHeartRate?
    /// A rolling three-minute window, for the live trace and the low/high chips.
    private(set) var trail = HeartRateTrail(window: 180)
    private(set) var isStreaming = false
    /// Set when HealthKit refused or is unavailable, so the UI can stay quiet instead of spinning.
    private(set) var unavailableReason: String?

    private let store = HKHealthStore()
    private var task: Task<Void, Never>?
    /// Demo mode drives a synthetic pulse; real HealthKit is never mixed with it.
    private var simulator: Task<Void, Never>?

    static let type = HKQuantityType(.heartRate)
    static let unit = HKUnit.count().unitDivided(by: .minute())

    var pulse: HeartRatePulse? {
        latest.map { HeartRatePulse(reading: $0, restingBaseline: restingBaseline) }
    }

    /// Resting heart rate learned from recent nights, supplied by the app model.
    var restingBaseline: Double?

    // MARK: Lifecycle

    /// Starts (or restarts) streaming. Safe to call whenever the Today screen appears.
    func start(demo: Bool, restingBaseline: Double?) {
        self.restingBaseline = restingBaseline
        guard !isStreaming else { return }
        stop()
        isStreaming = true
        if demo {
            startSimulator()
        } else {
            startHealthKit()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        simulator?.cancel()
        simulator = nil
        isStreaming = false
    }

    private func record(_ readings: [LiveHeartRate]) {
        guard !readings.isEmpty else { return }
        trail.add(contentsOf: readings)
        if let newest = readings.max(by: { $0.at < $1.at }),
           latest.map({ newest.at >= $0.at }) ?? true {
            latest = newest
        }
    }

    // MARK: Apple Health

    private func startHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            unavailableReason = "Health data isn't available on this device."
            isStreaming = false
            return
        }
        task = Task { [weak self] in
            await self?.readMostRecent()
            await self?.stream()
        }
    }

    /// One reading straight away, so the widget isn't empty while waiting for the next sample.
    private func readMostRecent() async {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return }
        record([Self.reading(from: sample)])
    }

    /// Long-running anchored query: each element of the sequence is a batch of new samples.
    private func stream() async {
        // Only samples from the last few minutes matter for a live pulse.
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-600), end: nil, options: [])
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: Self.type, predicate: predicate)],
            anchor: nil)
        do {
            for try await result in descriptor.results(for: store) {
                if Task.isCancelled { return }
                record(result.addedSamples.map(Self.reading(from:)))
                trail.trim(now: Date())
            }
        } catch {
            unavailableReason = "Heart rate isn't shared with Blith."
            isStreaming = false
        }
    }

    static func reading(from sample: HKQuantitySample) -> LiveHeartRate {
        let name = sample.sourceRevision.source.name
        let product = sample.device?.model ?? sample.sourceRevision.productType ?? ""
        let isWatch = product.lowercased().contains("watch")
            || sample.sourceRevision.source.bundleIdentifier.lowercased().contains("watch")
        return LiveHeartRate(bpm: sample.quantity.doubleValue(for: unit),
                             at: sample.endDate,
                             sourceName: isWatch ? "Apple Watch" : name,
                             isWatch: isWatch)
    }

    // MARK: Demo

    /// A plausible resting pulse that wanders and carries a breathing rhythm, so the sample-data
    /// experience shows the same widget behaviour. Always labelled as sample data by the UI.
    private func startSimulator() {
        let base = restingBaseline ?? 64
        simulator = Task { [weak self] in
            var t = 0.0
            while !Task.isCancelled {
                let breathing = sin(t / 4.2) * 2.4
                let drift = sin(t / 37) * 5.5
                let jitter = Double.random(in: -1.2...1.2)
                let bpm = max(42, base + 4 + breathing + drift + jitter)
                self?.record([LiveHeartRate(bpm: bpm, at: Date(), sourceName: "Sample data", isWatch: false)])
                t += 2
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
