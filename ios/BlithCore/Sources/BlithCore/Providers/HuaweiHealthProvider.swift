import Foundation

/// Huawei Health adapter.
///
/// Huawei offers no iOS on-device SDK; data is reachable only through the Health Kit cloud
/// REST API after the user signs in with a HUAWEI ID (OAuth 2.0) and the app's Health Kit
/// scopes are approved by Huawei. Until a developer account, client credentials and a token
/// service exist, this provider reports `.notConfigured` and the app runs on HealthKit alone.
///
/// Note: the Huawei Health iOS app can already sync a Huawei watch's steps, sleep and heart
/// rate into Apple Health, so most Huawei users are covered through HealthKit today. When both
/// paths are active, `SourceMerger` prevents double counting.
///
/// Everything provider-specific stays in this file: the rest of the app only sees normalized
/// `ProviderBatch` values with `ProviderKind.huawei` provenance. See docs/HUAWEI.md.
public struct HuaweiHealthProvider: HealthDataProvider {
    public struct Configuration: Sendable {
        public var clientID: String
        public var redirectURI: String
        /// Health Kit REST base URL.
        public var apiBase: URL
        public init(clientID: String, redirectURI: String,
                    apiBase: URL = URL(string: "https://health-api.cloud.huawei.com/healthkit/v2")!) {
            self.clientID = clientID
            self.redirectURI = redirectURI
            self.apiBase = apiBase
        }
    }

    /// Transport for the REST API (implemented once credentials exist; injectable for tests).
    public protocol Transport: Sendable {
        /// Aggregated values per local day for one Huawei data type.
        func dailyTotals(dataType: String, span: DateSpan, calendar: Calendar) async throws -> [(LocalDate, Double)]
        func samples(dataType: String, interval: DateInterval) async throws -> [RawSample]
    }

    public struct RawSample: Sendable, Hashable {
        public var id: String
        public var start: Date
        public var end: Date
        public var value: Double
        public var device: String?
        public init(id: String, start: Date, end: Date, value: Double, device: String?) {
            self.id = id
            self.start = start
            self.end = end
            self.value = value
            self.device = device
        }
    }

    public let configuration: Configuration?
    public let transport: (any Transport)?
    public var kind: ProviderKind { .huawei }
    public var isAvailable: Bool { configuration != nil && transport != nil }

    public init(configuration: Configuration? = nil, transport: (any Transport)? = nil) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Huawei data type names for each normalized metric (Health Kit data model).
    public static let dataTypes: [HealthMetric: String] = [
        .steps: "com.huawei.continuous.steps.delta",
        .distanceWalkingRunning: "com.huawei.continuous.distance.delta",
        .activeEnergy: "com.huawei.continuous.calories.burnt",
        .weight: "com.huawei.instantaneous.body_weight",
        .restingHeartRate: "com.huawei.instantaneous.resting_heart_rate",
    ]
    public static let sleepDataType = "com.huawei.continuous.sleep.fragment"

    /// Huawei sleep fragment states → normalized stages.
    public static func sleepStage(_ state: Int) -> SleepStage? {
        switch state {
        case 1: .core      // light sleep
        case 2: .deep
        case 3: .rem       // "dream"
        case 4: .awake
        case 5: .asleepUnspecified // nap
        default: nil
        }
    }

    public static let source = SourceRef(provider: .huawei, name: "Huawei Health", identifier: "com.huawei.health.cloud", device: "Huawei wearable")

    /// OAuth authorization URL the app would open (ASWebAuthenticationSession). The code must be
    /// exchanged for tokens by a server that holds the client secret — never in the app.
    public func authorizationURL(state: String) -> URL? {
        guard let c = configuration else { return nil }
        var comps = URLComponents(string: "https://oauth-login.cloud.huawei.com/oauth2/v3/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: c.clientID),
            URLQueryItem(name: "redirect_uri", value: c.redirectURI),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: [
                "openid",
                "https://www.huawei.com/healthkit/step.read",
                "https://www.huawei.com/healthkit/distance.read",
                "https://www.huawei.com/healthkit/calories.read",
                "https://www.huawei.com/healthkit/sleep.read",
                "https://www.huawei.com/healthkit/bodyweight.read",
                "https://www.huawei.com/healthkit/heartrate.read",
            ].joined(separator: " ")),
        ]
        return comps.url
    }

    public func requestAuthorization(for categories: Set<HealthCategory>) async throws {
        guard isAvailable else {
            throw HealthProviderError.notConfigured("Huawei Health isn't available yet. It needs a Huawei developer account and approved Health Kit access.")
        }
    }

    public func earliestDataDate() async -> Date? { nil }

    public func fetch(_ request: ProviderFetch, calendar: Calendar) async throws -> ProviderBatch {
        guard let transport else { throw HealthProviderError.notConfigured("Huawei Health isn't configured.") }
        var batch = ProviderBatch()
        for metric in request.metrics {
            guard let type = Self.dataTypes[metric], metric != .weight else {
                if Self.dataTypes[metric] == nil { batch.unsupported.insert(metric) }
                continue
            }
            let totals = try await transport.dailyTotals(dataType: type, span: request.span, calendar: calendar)
            batch.daily[metric] = totals.map { DailyAggregate(date: $0.0, metric: metric, value: $0.1) }
        }
        let interval = request.span.dateInterval(in: calendar)
        if request.includeBody, let type = Self.dataTypes[.weight] {
            batch.weights = try await transport.samples(dataType: type, interval: interval).map {
                HealthSample(id: "huawei-\($0.id)", metric: .weight, value: $0.value, start: $0.start, end: $0.end,
                             source: Self.source, syncedAt: Date())
            }
        }
        if request.includeSleep {
            batch.sleepSegments = try await transport.samples(dataType: Self.sleepDataType, interval: request.sleepInterval(calendar: calendar))
                .compactMap { s in Self.sleepStage(Int(s.value)).map { SleepSegment(start: s.start, end: s.end, stage: $0, source: Self.source) } }
        }
        return batch
    }
}
