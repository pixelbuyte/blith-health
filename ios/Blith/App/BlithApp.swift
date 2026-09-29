import BlithCore
import SwiftUI

@main
struct BlithApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.router)
                .tint(Palette.accent)
                .task { await app.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, app.phase == .ready { Task { await app.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch app.phase {
            case .launching:
                Palette.background.ignoresSafeArea()
                    .overlay(ProgressView())
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .importing:
                ImportProgressView()
                    .transition(.opacity)
            case .ready:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.respecting(reduceMotion), value: app.phase)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.horizon", value: AppTab.today) {
                TodayView()
            }
            Tab("Walk", systemImage: "figure.walk", value: AppTab.walk) {
                WalkView()
            }
            Tab("Ask", systemImage: "sparkles", value: AppTab.ask) {
                AskView()
            }
        }
        .modifier(LiquidGlassTabBar())
        .sheet(item: $router.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(app)
                .environment(router)
        }
    }
}

/// On iOS 26 the system tab bar is Liquid Glass; let it shrink while scrolling content.
private struct LiquidGlassTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct SheetHost: View {
    let sheet: AppRouter.Sheet
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var body: some View {
        switch sheet {
        case .profile:
            ProfileView()
        case .sleep(let date):
            SleepDetailView(initialDate: date)
        case .weight:
            WeightDetailView()
        case .sources:
            NavigationStack { SourcesView() }
        case .insight(let insight):
            InsightExplanationSheet(
                insight: insight,
                updated: app.history?.sync.lastSync,
                onAsk: { question in
                    router.tab = .ask
                    Task { await app.ask.send(question, app: app) }
                },
                onOpen: { link in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        router.open(link, snapshot: app.snapshot)
                    }
                })
            .presentationDetents([.medium, .large])
        }
    }
}
