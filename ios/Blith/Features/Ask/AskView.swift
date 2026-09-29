import BlithCore
import SwiftUI

struct AskView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @FocusState private var focused: Bool

    static let suggestions = ["How have I been walking?", "Show my week.", "How is my weight trending?",
                              "What changed recently?", "Show my sleep last night.", "What was my best week?"]

    var body: some View {
        let ask = app.ask
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xl) {
                        if app.isDemo { SampleDataBanner() }
                        if ask.messages.isEmpty {
                            emptyState
                        }
                        ForEach(ask.messages) { message in
                            MessageView(message: message) { link in router.open(link, snapshot: app.snapshot) }
                                .id(message.id)
                        }
                        if ask.isResponding {
                            HStack(spacing: Space.s) {
                                ProgressView().controlSize(.small)
                                Text(ask.progress ?? "Thinking").font(.subheadline).foregroundStyle(.secondary)
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
            .background(Palette.background)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Ask")
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

    var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Your health, explained.").font(.system(.title, design: .rounded, weight: .bold))
                Text("Ask about your walking, weight, sleep or anything that changed. Answers use your own history and show the data behind them.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Space.xl)
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Self.suggestions, id: \.self) { s in
                    Button {
                        Task { await app.ask.send(s, app: app) }
                    } label: {
                        Text(s).font(.subheadline.weight(.medium)).padding(.horizontal, Space.xs)
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
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .accessibilityLabel("You: \(message.text)")
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(attributed(message.text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                ForEach(message.blocks) { block in
                    ChatBlockView(block: block, open: open)
                }
                if !message.evidence.isEmpty {
                    DisclosureGroup(isExpanded: $showEvidence) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(message.evidence) { e in
                                Text("\(e.label): \(e.detail)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Space.xs)
                    } label: {
                        Label(message.isLocal ? "Based on (answered on this iPhone)" : "Based on", systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                }
            }
        }
    }

    func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
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
