import BlithCore
import Observation
import SwiftUI

enum AppTab: Hashable { case today, walk, ask }

/// Navigation state shared by tabs, insight cards and chat widgets, so the assistant can
/// "navigate the app with the user".
@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable {
        case profile
        case sleep(LocalDate?)
        case weight
        case insight(Insight)
        case sources

        var id: String {
            switch self {
            case .profile: "profile"
            case .sleep(let d): "sleep-\(d?.description ?? "last")"
            case .weight: "weight"
            case .insight(let i): "insight-\(i.id)"
            case .sources: "sources"
            }
        }
    }

    var tab: AppTab = .today
    var walkPeriod: WalkPeriod = .week
    var sheet: Sheet?

    func open(_ link: DeepLink, snapshot: HealthSnapshot?) {
        switch link {
        case .today:
            sheet = nil
            tab = .today
        case .walk(let period):
            sheet = nil
            walkPeriod = period
            tab = .walk
        case .sleep(let date):
            sheet = .sleep(date)
        case .weight:
            sheet = .weight
        case .insight(let id):
            if let insight = snapshot?.insight(id: id) { sheet = .insight(insight) }
        case .sources:
            sheet = .sources
        }
    }

    func reset() {
        tab = .today
        walkPeriod = .week
        sheet = nil
    }
}
