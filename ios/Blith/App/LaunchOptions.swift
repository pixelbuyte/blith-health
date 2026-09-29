import BlithCore
import Foundation

/// Launch arguments used by CI to capture screenshots of specific states without touching
/// real data. Example:
///   xcrun simctl launch booted com.blith.health -BlithDemo balanced -BlithTab walk
/// Arguments are read from UserDefaults' argument domain and are ignored when absent.
enum LaunchOptions {
    static var args: UserDefaults { .standard }

    @MainActor
    static func applyIfPresent(to app: AppModel) {
        if args.bool(forKey: "BlithResetOnboarding") {
            Persistence.reset()
            return
        }
        guard let raw = args.string(forKey: "BlithDemo"), let scenario = DemoScenario(rawValue: raw) else { return }
        if args.object(forKey: "BlithClockHour") != nil {
            let hour = args.double(forKey: "BlithClockHour")
            let target = Calendar.current.startOfDay(for: Date()).addingTimeInterval(hour * 3600)
            AppClock.offset = target.timeIntervalSince(Date())
        }
        Persistence.onboardingComplete = true
        Persistence.dataMode = .demo(scenario)
        var p = app.profile
        if p.name.isEmpty { p.name = "Zen" }
        if p.goals.isEmpty { p.goals = [.walkMore, .weightManagement, .consistency] }
        if p.goalWeightKg == nil { p.goalWeightKg = 78 }
        if let units = args.string(forKey: "BlithUnits").flatMap(UnitSystem.init(rawValue:)) { p.units = units }
        app.profile = p
        Persistence.aiConsent = args.object(forKey: "BlithAIConsent").map { _ in args.bool(forKey: "BlithAIConsent") } ?? Persistence.aiConsent
    }

    @MainActor
    static func applyAfterLaunch(to app: AppModel) async {
        switch args.string(forKey: "BlithTab") {
        case "walk": app.router.tab = .walk
        case "ask": app.router.tab = .ask
        default: break
        }
        if let period = args.string(forKey: "BlithPeriod").flatMap(WalkPeriod.init(rawValue:)) { app.router.walkPeriod = period }
        if args.bool(forKey: "BlithAskScript"), let snapshot = app.snapshot {
            await app.ask.runScript(["How have I been walking?", "Show my sleep last night.", "How has my weight changed?"],
                                    snapshot: snapshot)
        }
        switch args.string(forKey: "BlithSheet") {
        case "sleep": app.router.sheet = .sleep(nil)
        case "weight": app.router.sheet = .weight
        case "profile": app.router.sheet = .profile
        case "sources": app.router.sheet = .sources
        case "insight": if let i = app.snapshot?.feed.first { app.router.sheet = .insight(i) }
        default: break
        }
    }
}
