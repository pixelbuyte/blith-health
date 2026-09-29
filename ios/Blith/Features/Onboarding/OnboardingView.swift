import BlithCore
import SwiftUI

/// Four short steps: value, priorities, connect, optional profile.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var goals: Set<UserGoal> = []
    @State private var categories: Set<HealthCategory> = [.movement, .sleep, .body]
    @State private var connecting = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.heroGradientTop, Palette.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            Group {
                switch step {
                case 0: welcome
                case 1: goalsStep
                case 2: connectStep
                default: ProfileSetupStep(goals: goals) { app.finishOnboarding() }
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .animation(Motion.respecting(reduceMotion), value: step)
    }

    // MARK: Steps

    var welcome: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Spacer()
            BrandMark().frame(width: 84, height: 84)
            Text("Understand your health, not just your numbers.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Blith learns your normal from your own history, notices what changes, and explains why it matters. Ask it anything about your walking, sleep and weight.")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Space.m) {
                bullet("chart.line.uptrend.xyaxis", "Compared with you, not population averages")
                bullet("info.circle", "Every insight shows its evidence")
                bullet("lock.shield", "Your health history is stored on this iPhone")
            }
            .padding(.top, Space.s)
            Spacer()
            primaryButton("Get started") { step = 1 }
        }
        .padding(Space.xxl)
    }

    var goalsStep: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            stepHeader("What matters to you?", "Pick as many as you like. This shapes which patterns we bring up first.")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                    ForEach(UserGoal.allCases) { goal in
                        let selected = goals.contains(goal)
                        Button {
                            if selected { goals.remove(goal) } else { goals.insert(goal) }
                        } label: {
                            VStack(alignment: .leading, spacing: Space.m) {
                                Image(systemName: goal.symbol).font(.title2)
                                    .foregroundStyle(selected ? Color.white : Palette.accent)
                                Text(goal.title).font(.headline).multilineTextAlignment(.leading)
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                            .padding(Space.l)
                            .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.card),
                                        in: RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .sensoryFeedback(.selection, trigger: selected)
                    }
                }
            }
            primaryButton(goals.isEmpty ? "Skip" : "Continue") {
                app.profile.goals = goals
                step = 2
            }
        }
        .padding(Space.xxl)
    }

    var connectStep: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            stepHeader("Connect your health", "Your data lets Blith understand your patterns instead of giving generic advice. Choose what to share; you can change this any time in Settings.")
            ScrollView {
                VStack(spacing: Space.s) {
                    ForEach(HealthCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { categories.contains(category) },
                                             set: { on in if on { categories.insert(category) } else { categories.remove(category) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Space.s) {
                                    Text(category.title).font(.headline)
                                    Text(category.isRecommended ? "Recommended" : "Optional")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(category.isRecommended ? Palette.accent : .secondary)
                                }
                                Text(category.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(Space.l)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous))
                    }
                    Text("Blith only reads data. It never writes to Apple Health and never uses health data for advertising.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, Space.s)
                }
            }
            if let error = app.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if app.healthKitAvailable {
                primaryButton(connecting ? "Connecting…" : "Connect Apple Health") {
                    connecting = true
                    Task {
                        await app.connectAppleHealth(categories: categories)
                        connecting = false
                        if app.errorMessage == nil { step = 3 }
                    }
                }
                .disabled(categories.isEmpty || connecting)
            } else {
                Text("Apple Health isn't available on this device.").font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                Task {
                    step = 3
                    await app.useDemo(.balanced)
                }
            } label: {
                Text("Explore with sample data").frame(maxWidth: .infinity)
            }
            .glassButton()
            .controlSize(.large)
        }
        .padding(Space.xxl)
    }

    // MARK: Pieces

    func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.xl)
    }

    func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(Palette.accent)
        }
    }

    func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 30)
        }
        .glassButton(prominent: true)
        .controlSize(.large)
    }
}

/// Only what the product uses: a name for the greeting, units, optional goals.
struct ProfileSetupStep: View {
    let goals: Set<UserGoal>
    let done: () -> Void
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var hasStepGoal = false
    @State private var stepGoal = 8000
    @State private var goalWeight = ""

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("A few optional details").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("All of this is optional and stays on your iPhone.").foregroundStyle(.secondary)
            }
            .padding(.top, Space.xl)
            Form {
                Section("What should we call you?") {
                    TextField("Name (optional)", text: $name)
                        .textContentType(.givenName)
                }
                Section("Units") {
                    Picker("Units", selection: $app.profile.units) {
                        Text("Metric (kg, km)").tag(UnitSystem.metric)
                        Text("Imperial (lb, mi)").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Daily step goal", isOn: $hasStepGoal)
                    if hasStepGoal {
                        Stepper("\(Fmt.int(Double(stepGoal))) steps", value: $stepGoal, in: 2000...25000, step: 500)
                    }
                } footer: {
                    Text("Without a goal, Blith measures consistency against your own recent normal.")
                }
                if goals.contains(.weightManagement) {
                    Section("Goal weight (optional)") {
                        TextField(app.profile.units == .metric ? "kg" : "lb", text: $goalWeight)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            Button {
                var p = app.profile
                p.name = name.trimmingCharacters(in: .whitespaces)
                p.dailyStepGoal = hasStepGoal ? stepGoal : nil
                if let v = Double(goalWeight.replacingOccurrences(of: ",", with: ".")), v > 20 {
                    p.goalWeightKg = p.units == .metric ? v : v / 2.204_622_6
                }
                app.profile = p
                app.profileChanged()
                done()
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 30)
            }
            .glassButton(prominent: true)
            .controlSize(.large)
        }
        .padding(Space.xxl)
    }
}

/// Honest import progress, driven by the sync engine's real stages.
struct ImportProgressView: View {
    @Environment(AppModel.self) private var app

    var stages: [(SyncProgress.Stage, String)] {
        [(.connecting, "Connecting health data"), (.importingHistory, "Building your history"), (.analyzing, "Understanding your patterns")]
    }

    var body: some View {
        let current = app.importProgress
        VStack(alignment: .leading, spacing: Space.xl) {
            Spacer()
            BrandMark().frame(width: 72, height: 72)
            Text("Building your health history…").font(.system(.title, design: .rounded, weight: .bold))
            VStack(alignment: .leading, spacing: Space.l) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, item in
                    let state = stageState(item.0, current: current?.stage)
                    HStack(spacing: Space.m) {
                        ZStack {
                            Circle().fill(state == 2 ? Palette.accent : Palette.accentSoft).frame(width: 28, height: 28)
                            if state == 2 {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                            } else if state == 1 {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
                            }
                        }
                        Text(item.1).font(.headline).foregroundStyle(state == 0 ? .secondary : .primary)
                    }
                }
            }
            if let current {
                ProgressView(value: current.fraction).tint(Palette.accent)
                Text(current.detail).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = app.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
                Button("Continue anyway") { app.phase = .ready }
            }
            Spacer()
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.ignoresSafeArea())
    }

    /// 0 = pending, 1 = active, 2 = done
    func stageState(_ stage: SyncProgress.Stage, current: SyncProgress.Stage?) -> Int {
        guard let current else { return 0 }
        let order: [SyncProgress.Stage: Int] = [.connecting: 0, .importingRecent: 1, .importingHistory: 1, .analyzing: 2, .done: 3]
        let s = order[stage] ?? 0, c = order[current] ?? 0
        return c > s ? 2 : (c == s ? 1 : 0)
    }
}

/// The app mark drawn natively (matches the app icon).
struct BrandMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.5, green: 0.7, blue: 1), Color(red: 0.25, green: 0.42, blue: 1), Color(red: 0.13, green: 0.2, blue: 0.79)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.19, y: w * 0.69))
                    p.addCurve(to: CGPoint(x: w * 0.48, y: w * 0.575), control1: CGPoint(x: w * 0.32, y: w * 0.70), control2: CGPoint(x: w * 0.38, y: w * 0.585))
                    p.addCurve(to: CGPoint(x: w * 0.69, y: w * 0.5), control1: CGPoint(x: w * 0.6, y: w * 0.63), control2: CGPoint(x: w * 0.63, y: w * 0.56))
                    p.addCurve(to: CGPoint(x: w * 0.8, y: w * 0.33), control1: CGPoint(x: w * 0.74, y: w * 0.42), control2: CGPoint(x: w * 0.76, y: w * 0.34))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: w * 0.057, lineCap: .round, lineJoin: .round))
                Circle().fill(.white).frame(width: w * 0.105).position(x: w * 0.8, y: w * 0.33)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
