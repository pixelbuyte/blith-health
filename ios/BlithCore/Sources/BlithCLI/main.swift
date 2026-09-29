import BlithCore
import Foundation

// Developer tool. Usage:
//   swift run BlithCLI insights [scenario]
//   OPENROUTER_API_KEY=… swift run BlithCLI ask "How have I been walking?" [scenario]
let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "insights"
let calendar = Calendar.current
let now = Date()

func loadHistory(_ scenario: DemoScenario) async throws -> HealthHistory {
    let provider = MockHealthProvider(scenario: scenario, now: { now })
    let engine = SyncEngine(provider: provider, calendar: calendar, now: { now })
    var h = HealthHistory(origin: .demo(scenario))
    h.requestedCategories = Set(HealthCategory.allCases)
    return try await engine.initialImport(into: h)
}

let profile = UserProfile(name: "Zen", goals: [.walkMore, .weightManagement], units: .metric, goalWeightKg: 78)

switch command {
case "ask":
    let question = args.dropFirst().first ?? "How have I been walking?"
    let scenario = args.dropFirst(2).first.flatMap(DemoScenario.init(rawValue:)) ?? .balanced
    let history = try await loadHistory(scenario)
    let snapshot = HealthSnapshot.build(history: history, profile: profile, now: now, calendar: calendar)
    let tools = HealthAssistantTools(snapshot: snapshot)
    let assistant: any AssistantEngine
    if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
        assistant = LLMAssistant(client: OpenRouterClient(apiKey: key, model: OpenRouterClient.defaultModel), tools: tools)
    } else {
        print("(no OPENROUTER_API_KEY — using the on-device assistant)")
        assistant = LocalAssistant(tools: tools)
    }
    let reply = try await assistant.respond(to: question, history: []) { progress in print("… \(progress)") }
    print("\n\(reply.text)\n")
    for block in reply.blocks { print("[widget] \(block.kind) → \(block.link.map { "\($0)" } ?? "-")") }
    for e in reply.evidence { print("[evidence] \(e.label): \(e.detail)") }
default:
    let scenario = args.dropFirst().first.flatMap(DemoScenario.init(rawValue:)) ?? .balanced
    let history = try await loadHistory(scenario)
    let s = HealthSnapshot.build(history: history, profile: profile, now: now, calendar: calendar)
    print("Headline: \(s.headline)")
    print("Today: \(Fmt.int(s.todaySteps ?? 0)) steps · pace change \(s.pace?.change.map(Fmt.signedPercent) ?? "-") (\(s.pace?.basis.rawValue ?? "-"), n=\(s.pace?.observations ?? 0))")
    print("7d \(Fmt.int(s.average7?.value ?? 0)) · 30d \(Fmt.int(s.average30?.value ?? 0)) · 90d \(Fmt.int(s.average90?.value ?? 0))")
    print("Consistency: \(s.consistency?.metCount ?? 0) days ≥ \(Fmt.int(s.consistency?.threshold ?? 0))")
    if let w = s.weight { print("Weight trend \(Fmt.weight(w.trendNow, units: .metric)) change30 \(w.change30Days.map { Fmt.weightChange($0, units: .metric) } ?? "-")") }
    print("Sleep last night: \(s.sleep.lastNightAsleep.map { Fmt.duration($0) } ?? "-")")
    print("\nAll insights (\(s.allInsights.count)):")
    for i in s.allInsights { print(String(format: "  %.2f", i.score) + "  [\(i.kind.rawValue)] \(i.headline)\n        \(i.explanation)") }
    print("\nFeed: \(s.feed.map(\.kind.rawValue))")
    print("\nPatterns:")
    for p in s.patterns { print("  • \(p.text) — \(p.detail)") }
}
