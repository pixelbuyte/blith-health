import BlithCore
import SwiftUI

struct AskView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @FocusState private var focused: Bool

    static let suggestions: [(String, String)] = [
        ("How have I been walking?", "bl.walk"), ("Why was my walking lower last Tuesday?", "bl.calendar"),
        ("Show my sleep last night.", "bl.sleep"), ("How has my weight changed?", "bl.weight"),
        ("What changed recently?", "bl.sparkle"), ("Show my body notes.", "bl.bodynote"),
    ]

    var body: some View {
        let ask = app.ask
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xl) {
                        askHeader(responding: ask.isResponding)
                        if ask.messages.isEmpty {
                            emptyState
                        }
                        ForEach(ask.messages) { message in
                            MessageView(message: message) { link in router.open(link, snapshot: app.snapshot) }
                                .id(message.id)
                        }
                        if ask.isResponding {
                            HStack(spacing: Space.s) {
                                BlithMascot(pose: .thinking, size: 34)
                                Text(ask.progress ?? "Thinking").font(.subheadline).foregroundStyle(Palette.secondaryInk)
                                    .contentTransition(.opacity)
                            }
                            .id("progress")
                            .accessibilityElement(children: .combine)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.l)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: ask.messages.count) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: ask.isResponding) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .blithBackground(wash: Palette.cyan.opacity(0.14))
            .safeAreaInset(edge: .bottom) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !ask.messages.isEmpty {
                        Button { ask.clear() } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("New conversation")
                    }
                }
            }
            .sheet(isPresented: Binding(get: { ask.pendingQuestion != nil },
                                        set: { if !$0 && ask.pendingQuestion != nil { ask.resolveConsent(false, app: app) } })) {
                AIConsentSheet { allowed in ask.resolveConsent(allowed, app: app) }
            }
        }
    }

    func askHeader(responding: Bool) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: "Your health, explained", icon: "bl.sparkle", color: Palette.cyan)
                    if app.isDemo { SampleDataBanner() }
                }
                Text("Ask Blith").font(Typo.display).foregroundStyle(Palette.ink)
            }
            Spacer()
            BlithMascot(pose: responding ? .thinking : .listening, size: 58)
        }
    }

    var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Ask about your walking, sleep, weight or body notes. Every answer is computed from your records and comes with the evidence behind it.")
                .foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Self.suggestions, id: \.0) { s in
                    Button {
                        Task { await app.ask.send(s.0, app: app) }
                    } label: {
                        HStack(spacing: Space.s) {
                            BLIcon(name: s.1, size: 16).foregroundStyle(Palette.cobalt)
                            Text(s.0).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, Space.xs)
                    }
                    .glassButton()
                }
            }
            if !AppConfig.aiConfigured || Persistence.aiConsent == false {
                Label("Answers are generated on this iPhone.", systemImage: "iphone")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    var composer: some View {
        @Bindable var ask = app.ask
        return HStack(alignment: .bottom, spacing: Space.s) {
            TextField("Ask about your health…", text: $ask.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { submit() }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .glassButton(prominent: true)
            .buttonBorderShape(.circle)
            .disabled(ask.draft.trimmingCharacters(in: .whitespaces).isEmpty || ask.isResponding)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }

    func submit() {
        let text = app.ask.draft
        Task { await app.ask.send(text, app: app) }
    }
}

struct MessageView: View {
    let message: ChatMessage
    let open: (DeepLink) -> Void
    @State private var showEvidence = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                    .foregroundStyle(.white)
                    .background(Palette.askGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .accessibilityLabel("You: \(message.text)")
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.s) {
                    ZStack {
                        Circle().fill(Palette.accentSoft)
                        BLIcon(name: "bl.sparkle", size: 15).foregroundStyle(Palette.cobalt)
                    }
                    .frame(width: 30, height: 30)
                    Text(attributed(message.text))
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                ForEach(message.blocks) { block in
                    ChatBlockView(block: block, open: open)
                }
                if !message.evidence.isEmpty {
                    WhyButton { showEvidence = true }
                }
            }
            .sheet(isPresented: $showEvidence) { AnswerEvidenceSheet(message: message) }
        }
    }

    func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// What an answer was computed from.
struct AnswerEvidenceSheet: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(message.evidence) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.label).font(.subheadline.weight(.semibold))
                            Text(e.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Records used")
                } footer: {
                    Text(message.isLocal
                         ? "Answered on this iPhone from your records. Numbers are computed by Blith, not estimated."
                         : "Numbers were computed on this iPhone and only minimized summaries were sent to the AI model to phrase the answer.")
                }
                if !message.toolsUsed.isEmpty {
                    Section("Calculations run") {
                        ForEach(Array(Set(message.toolsUsed)).sorted(), id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline)
                        }
                    }
                }
                Section {
                    Text("Relationships between records are patterns, not causes. Blith doesn't diagnose.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Why you're seeing this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Shown once before any question leaves the device. Declining keeps Ask fully on-device.
struct AIConsentSheet: View {
    let decide: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Palette.accent)
                    Text("Use AI to answer your questions?").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("To answer in conversation, Blith sends your question and a small summary of the relevant numbers to an AI model (via OpenRouter). You choose; you can change this any time in Settings.")
                    VStack(alignment: .leading, spacing: Space.m) {
                        point("checkmark.circle", "Sent: your question, and aggregates like “7-day average: 7,420 steps” or “weight trend: −1.2 kg in 30 days”.")
                        point("xmark.circle", "Never sent: your name, raw health records, identifiers or location.")
                        point("checkmark.shield", "Used only to answer you. Not used for advertising.")
                        point("iphone", "Prefer not to? Ask still answers common questions on this iPhone.")
                    }
                    .font(.subheadline)
                    Text("Blith is not a medical device and doesn't give diagnoses.").font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: Space.m) {
                        Button {
                            decide(true)
                        } label: { Text("Allow AI answers").font(.headline).frame(maxWidth: .infinity) }
                            .glassButton(prominent: true)
                        Button {
                            decide(false)
                        } label: { Text("Keep answers on this iPhone").frame(maxWidth: .infinity) }
                            .glassButton()
                    }
                    .controlSize(.large)
                }
                .padding(Space.xxl)
            }
            .interactiveDismissDisabled()
        }
    }

    func point(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Palette.accent) }
    }
}
