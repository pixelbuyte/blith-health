import BlithCore
import Foundation
import HealthKit
import Observation

/// Streams heart rate from Apple Health. New readings appear the moment Health receives them, so
/// the card is as live as the data source: an Apple Watch records every few minutes at rest and
/// every few seconds during a Workout. Demo mode simulates a stream and says so.
@MainActor
@Observable
final class LiveHeartRate {
    enum Status: Equatable {
        case idle
        /// Heart rate hasn't been requested from Health yet.
        case needsAccess
        /// Authorised (or unknowable) but nothing recorded in the last day.
        case noData
        case ready
        case unavailable
    }

    private(set) var status: Status = .idle
    private(set) var samples: [HeartSample] = []
    private(set) var isSimulated = false
    /// The person's resting rate, used to place the current rate in a zone.
    var resting: Double?

    var latest: HeartSample? { samples.last }

    private let store = HKHealthStore()
    private let type = HKQuantityType(.heartRate)
    private let unit = HKUnit.count().unitDivided(by: .minute())
    private var query: HKAnchoredObjectQuery?
    private var simulation: Task<Void, Never>?
    private var generation = 0

    func summary(now: Date = Date()) -> LiveHeartSummary {
        LiveHeartSummary.make(samples: samples, now: now, resting: resting)
    }

    // MARK: Lifecycle

    func start(simulated: Bool) {
        stop()
        generation += 1
        isSimulated = simulated
        if simulated {
            startSimulation()
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        let gen = generation
        Task { [weak self] in
            guard let self else { return }
            let request = try? await store.statusForAuthorizationRequest(toShare: [], read: [type])
            guard gen == generation else { return }
            if request == .shouldRequest {
                status = .needsAccess
            } else {
                startQuery()
            }
        }
    }

    func stop() {
        if let query { store.stop(query) }
        query = nil
        simulation?.cancel()
        simulation = nil
    }

    /// Asks Health for read access to heart rate, then starts streaming.
    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        try? await store.requestAuthorization(toShare: [], read: [type])
        startQuery()
    }

    // MARK: HealthKit

    private func startQuery() {
        let since = Date().addingTimeInterval(-24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        let unit = unit
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, added, _, _, _ in
            let items = (added as? [HKQuantitySample] ?? []).map { HeartSample(date: $0.endDate, bpm: $0.quantity.doubleValue(for: unit)) }
            Task { @MainActor [weak self] in self?.ingest(items) }
        }
        let q = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        q.updateHandler = handler
        query = q
        store.execute(q)
        // The first result set can legitimately be empty; show the empty state instead of a spinner.
        if status != .ready { status = .noData }
    }

    private func ingest(_ items: [HeartSample]) {
        guard !items.isEmpty else { return }
        var merged = samples
        let known = Set(merged.map(\.date))
        merged.append(contentsOf: items.filter { !known.contains($0.date) })
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        samples = merged.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        status = .ready
    }

    // MARK: Simulation (sample data only)

    /// A pinned rate for screenshots and demos: `-BlithLiveBPM 148`.
    static var pinnedBPM: Double? {
        UserDefaults.standard.object(forKey: "BlithLiveBPM") != nil ? UserDefaults.standard.double(forKey: "BlithLiveBPM") : nil
    }

    private func startSimulation() {
        let pinned = Self.pinnedBPM
        let rest = resting ?? 60
        let now = Date()
        // An hour of believable history: a calm baseline with a couple of gentle bumps.
        var history: [HeartSample] = []
        var t = now.addingTimeInterval(-3600)
        while t < now {
            let minutes = now.timeIntervalSince(t) / 60
            let wobble = sin(minutes / 7) * 4 + sin(minutes / 2.3) * 2
            let bump = minutes < 34 && minutes > 22 ? 22 * sin((minutes - 22) / 12 * .pi) : 0
            history.append(HeartSample(date: t, bpm: (rest + 9 + wobble + bump).rounded()))
            t.addTimeInterval(150)
        }
        samples = history
        status = .ready
        let start = pinned ?? (rest + 9)
        simulation = Task { [weak self] in
            var value = start
            var tick = 0
            while !Task.isCancelled {
                let date = Date()
                if let pinned {
                    value = pinned
                } else {
                    // A slow random walk that drifts back toward a calm baseline.
                    value += Double.random(in: -1.6...1.6) + (rest + 10 - value) * 0.06
                    value = min(max(value, rest - 2), rest + 34)
                }
                let sample = HeartSample(date: date, bpm: value.rounded())
                await MainActor.run { self?.ingest([sample]) }
                tick += 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
