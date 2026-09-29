import BlithCore
import Foundation
import HealthKit
import Observation

extension AppleHealthProvider {
    func latestHeartRate() async throws -> HeartRateReading? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        return HeartRateReading(bpm: sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())),
                                measuredAt: sample.endDate, source: Self.source(of: sample))
    }

    /// Foreground only. Notifications trigger a fresh latest-sample query, including deletions.
    func heartRateChanges() -> (updates: AsyncThrowingStream<Void, Error>, finish: () -> Void) {
        let (updates, continuation) = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let query = HKObserverQuery(sampleType: HKQuantityType(.heartRate), predicate: nil) { _, completion, error in
            defer { completion() }
            if let error { continuation.finish(throwing: error) }
            else { continuation.yield(()) }
        }
        continuation.onTermination = { [store] _ in store.stop(query) }
        store.execute(query)
        continuation.yield(())
        return (updates, { continuation.finish() })
    }

}

@MainActor @Observable
final class HeartRateMonitor {
    private(set) var reading: HeartRateReading?
    private(set) var needsPermission = false
    private(set) var failed = false
    private var generation = UUID()

    func run(provider: AppleHealthProvider, mode: DataMode?, enabled: Bool, connected: Bool) async {
        let token = UUID()
        generation = token
        reading = nil
        failed = false
        needsPermission = false
        guard enabled, let mode else { return }
        if mode.isDemo {
            reading = HeartRateReading(bpm: 72, measuredAt: AppClock.now(),
                                      source: SourceRef(provider: .demo, name: "Sample data", identifier: "demo.heart"))
            return
        }
        guard provider.isAvailable else { return }
        let authorizationNeeded = await provider.needsAuthorizationRequest(for: [.heart])
        guard !Task.isCancelled, token == generation else { return }
        needsPermission = !connected || authorizationNeeded
        guard !needsPermission else { return }
        let observation = provider.heartRateChanges()
        // Also finish on a query error/early return, not only cancellation during next().
        defer { observation.finish() }
        do {
            for try await _ in observation.updates {
                let latest = try await provider.latestHeartRate()
                guard !Task.isCancelled, token == generation else { return }
                reading = latest
            }
        } catch {
            guard !Task.isCancelled, token == generation else { return }
            reading = nil
            failed = true
        }
    }
}
