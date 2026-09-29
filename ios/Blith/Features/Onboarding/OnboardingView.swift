import BlithCore
import SwiftUI

/// Four short steps: value, priorities, connect, optional profile.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var goals: Set<UserGoal> = []
    @State private var categories: Set<HealthCategory> = [.movement, .sleep, .body, .heart]
    @State private var connecting = false

    var body: some View {
        ZStack {
            Color.clear.blithBackground(wash: Palette.signal.opacity(0.2))
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
            BrandMark().frame(width: 56, height: 56)
            HStack(spacing: -6) {
                ScoreDial(fraction: 0.86, valueText: "86", unit: "%", label: "Sleep", color: Palette.sleep, size: 96)
                ScoreDial(fraction: 0.74, valueText: "74", unit: "%", label: "Readiness", color: Palette.band(.high), size: 140, usual: 0.58...0.8)
                ScoreDial(fraction: 0.54, valueText: "5.4", label: "Load", color: Palette.cyan, size: 96)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            Text("Your body, measured against you.")
                .font(Typo.display)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Blith turns your Apple Health history into daily readiness, sleep and load scores, a personal health monitor and a 3D body map — every number explained with the evidence behind it.")
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryInk)
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
                                HStack {
                                    SignalGlyph(symbol: goal.symbol, tint: selected ? Palette.signal : Palette.secondaryInk, size: 36)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selected ? Palette.signal : Palette.quiet)
                                }
                                Text(goal.title).font(Typo.geist(16, .semibold, relativeTo: .headline)).multilineTextAlignment(.leading)
                                    .foregroundStyle(Palette.ink)
                            }
                            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                            .padding(Space.l)
                            .background(selected ? Palette.raised : Palette.surface,
                                        in: RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous)
                                .strokeBorder(selected ? Palette.signal : Palette.hairline, lineWidth: selected ? 1.5 : 1))
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
                                    Text(category.title).font(Typo.geist(17, .semibold, relativeTo: .headline))
                                    Text(category.isRecommended ? "Recommended" : "Optional")
                                        .font(Typo.geist(12, .semibold, relativeTo: .caption))
                                        .foregroundStyle(category.isRecommended ? Palette.signal : Palette.tertiaryInk)
                                }
                                Text(category.detail).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .tint(Palette.signal)
                        .padding(Space.l)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    }
                    Text("Blith only reads data. It never writes to Apple Health and never uses health data for advertising.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.top, Space.s)
                }
            }
            if let error = app.errorMessage {
                Text(error).font(Typo.caption).foregroundStyle(.red)
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
                Text("Apple Health isn't available on this device.").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
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
            Text(title).font(Typo.pageTitle).foregroundStyle(Palette.ink)
            Text(subtitle).font(Typo.body).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.xl)
    }

    func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(Typo.geist(15, .medium, relativeTo: .subheadline))
        } icon: {
            Image(systemName: symbol).foregroundStyle(Palette.signal)
        }
    }

    func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Typo.geist(17, .semibold, relativeTo: .headline)).frame(maxWidth: .infinity, minHeight: 30)
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
                Text("All of this is optional and stays on your iPhone.").foregroundStyle(Palette.secondaryInk)
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
                Text("Continue").font(Typo.geist(17, .semibold, relativeTo: .headline)).frame(maxWidth: .infinity, minHeight: 30)
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
            ZStack {
                SignalPulse(size: 150, tint: Palette.signal)
                ScoreDial(fraction: current?.fraction ?? 0.02, valueText: "\(Int(((current?.fraction ?? 0) * 100).rounded()))", unit: "%",
                          label: "Importing", color: Palette.signal, size: 120)
            }
            Text("Building your health history…").font(Typo.display).foregroundStyle(Palette.ink)
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
                        Text(item.1).font(Typo.geist(17, .semibold, relativeTo: .headline)).foregroundStyle(state == 0 ? .secondary : .primary)
                    }
                }
            }
            if let current {
                ProgressView(value: current.fraction).tint(Palette.accent)
                Text(current.detail).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
            }
            if let error = app.errorMessage {
                Text(error).font(Typo.caption).foregroundStyle(.red)
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
            let r = w * 0.2
            let c = CGPoint(x: w * 0.55, y: w * 0.58)
            let end = Angle.degrees(195 + 0.87 * 360)
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0x12245A), Color(hex: 0x05070D)], center: .center, startRadius: 0, endRadius: w * 0.7))
                RoundedRectangle(cornerRadius: w * 0.26, style: .continuous).strokeBorder(Palette.cobalt.opacity(0.35), lineWidth: 1)
                Capsule().fill(Palette.cobalt).frame(width: w * 0.1, height: w * 0.4).position(x: c.x - r, y: w * 0.36)
                Circle().trim(from: 0, to: 0.87)
                    .stroke(AngularGradient(colors: [Palette.cobalt, Palette.cyan], center: .center),
                            style: StrokeStyle(lineWidth: w * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(195))
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                    .shadow(color: Palette.cyan.opacity(0.6), radius: w * 0.05)
                Circle().fill(.white).frame(width: w * 0.05)
                    .position(x: c.x + r * cos(end.radians), y: c.y + r * sin(end.radians))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
