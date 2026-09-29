import BlithCore
import SwiftUI

// MARK: - Region map

/// Region anchors for the current body artwork (`Resources/body-regions.json`, generated with
/// the figure by `design/body/generate_body.py`). Notes store a `BodyRegion`, never a screen
/// point, so markers follow the region through rotation and zoom, and survive a new model as
/// long as the new artwork ships its own anchor map.
struct BodyRegionMap: Decodable {
    struct Anchor: Decodable, Hashable {
        let x: Double
        let y: Double
        let r: Double
    }

    let viewBox: [Double]
    let front: [String: Anchor]
    let back: [String: Anchor]

    var width: Double { viewBox.first ?? 400 }
    var height: Double { viewBox.count > 1 ? viewBox[1] : 1000 }

    static let shared: BodyRegionMap = {
        guard let url = Bundle.main.url(forResource: "body-regions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode(BodyRegionMap.self, from: data) else {
            return BodyRegionMap(viewBox: [400, 1000], front: [:], back: [:])
        }
        return map
    }()

    func anchor(_ region: BodyRegion, back isBack: Bool) -> Anchor? {
        (isBack ? back : front)[region.rawValue]
    }

    /// The side to show a region on: the front when it exists there.
    func preferredSideIsBack(_ region: BodyRegion) -> Bool { front[region.rawValue] == nil && back[region.rawValue] != nil }

    func nearest(to p: CGPoint, back isBack: Bool, scale: CGFloat) -> BodyRegion? {
        let anchors = isBack ? back : front
        var best: (BodyRegion, CGFloat)?
        for (key, a) in anchors {
            guard let region = BodyRegion(rawValue: key) else { continue }
            let d = hypot(CGFloat(a.x) * scale - p.x, CGFloat(a.y) * scale - p.y)
            let limit = CGFloat(a.r) * scale * 1.5
            if d <= limit, d < (best?.1 ?? .infinity) { best = (region, d) }
        }
        return best?.0
    }
}

// MARK: - Body tab

struct BodyView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var angle: Double = 0
    @State private var dragStart: Double?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat?
    @State private var selectedRegion: BodyRegion?
    @State private var focusedNoteID: String?
    @State private var scrubDay: Double?
    @State private var editing: HealthEvent?
    @State private var showRegions = false
    @State private var revealed = false

    let map = BodyRegionMap.shared

    var history: HealthHistory? { app.history }
    var notes: [HealthEvent] { history?.bodyNotes ?? [] }
    var today: LocalDate { LocalDate(AppClock.now(), calendar: .current) }
    var isBack: Bool { abs(normalized(angle)) > 90 }

    func normalized(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x <= -180 { x += 360 }
        return x
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    stage
                    regionPanel
                    timeline
                    historyList
                    Text("Interim viewer: a front and back figure with region anchors. A licensed, rigged 3D model is needed for free rotation; the anchor map lets notes move to it unchanged.")
                        .font(.caption).foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
            }
            .blithBackground(wash: Palette.note.opacity(0.10))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { note in
                BodyNoteEditor(note: note, isNew: !notes.contains { $0.id == note.id }) { saved in
                    Task { await app.saveNote(saved) }
                } onDelete: { id in
                    Task { await app.deleteNote(id: id) }
                }
            }
            .sheet(isPresented: $showRegions) { regionList }
            .onAppear {
                withAnimation(Motion.respecting(reduceMotion, Motion.reveal)) { revealed = true }
                focusFromRouter()
            }
            .onChange(of: router.bodyFocusNoteID) { _, _ in focusFromRouter() }
        }
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: "Body history", icon: "bl.body", color: Palette.note)
                    if app.isDemo { SampleDataBanner() }
                }
                Text("Your body").font(Typo.display).foregroundStyle(Palette.ink)
                Text("Tap a region to add a note or see its history.").font(.subheadline).foregroundStyle(Palette.secondaryInk)
            }
            Spacer()
            AvatarButton(name: app.profile.name) { router.sheet = .profile }
        }
        .padding(.top, Space.l)
    }

    // MARK: Stage

    /// Notes whose markers show at the scrubbed date (active then), plus the focused note.
    var visibleNotes: [HealthEvent] {
        let day = scrubDay.map { LocalDate(dayNumber: Int($0.rounded())) } ?? today
        return notes.filter { $0.bodyRegion != nil && ($0.isActive(on: day) || $0.id == focusedNoteID || ($0.date == day)) }
    }

    var stage: some View {
        GeometryReader { geo in
            let figureHeight = geo.size.height - 24
            let scale = figureHeight / CGFloat(map.height)
            let figureWidth = CGFloat(map.width) * scale
            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0x16307F), Color(hex: 0x070D2B)], center: .center, startRadius: 10, endRadius: 360))
                figure(width: figureWidth, height: figureHeight, scale: scale)
                    .scaleEffect(zoom, anchor: zoomAnchor)
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed ? 1 : 0.94)
                    .offset(y: revealed ? 0 : 18)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                controls
            }
            .gesture(rotateGesture)
            .simultaneousGesture(zoomGesture)
        }
        .frame(height: 540)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Body map, \(isBack ? "back" : "front") view")
    }

    var zoomAnchor: UnitPoint {
        guard let region = selectedRegion, let a = map.anchor(region, back: isBack) else { return .center }
        return UnitPoint(x: a.x / map.width, y: a.y / map.height)
    }

    func figure(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let shown = normalized(angle)
        let tilt = isBack ? (shown > 0 ? shown - 180 : shown + 180) : shown
        return LivingFigure(back: isBack, width: width, height: height) {
            ZStack(alignment: .topLeading) {
                if let region = selectedRegion, let a = map.anchor(region, back: isBack) {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.cyan.opacity(0.75), Palette.cyan.opacity(0)], center: .center, startRadius: 0, endRadius: CGFloat(a.r) * scale * 1.6))
                        .frame(width: CGFloat(a.r) * scale * 3.2, height: CGFloat(a.r) * scale * 3.2)
                        .position(x: CGFloat(a.x) * scale, y: CGFloat(a.y) * scale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ForEach(visibleNotes) { note in
                    if let region = note.bodyRegion, let a = map.anchor(region, back: isBack) {
                        NoteMarker(note: note, focused: note.id == focusedNoteID, today: today)
                            .position(x: CGFloat(a.x) * scale, y: CGFloat(a.y) * scale)
                            .onTapGesture { focus(note) }
                    }
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                if let region = map.nearest(to: p, back: isBack, scale: scale) {
                    withAnimation(Motion.respecting(reduceMotion, Motion.snappy)) {
                        selectedRegion = region
                        focusedNoteID = nil
                    }
                }
            }
        }
        .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }

    var controls: some View {
        VStack {
            HStack {
                GlassEffectGroup {
                    sideButton("Front", back: false)
                    sideButton("Back", back: true)
                }
                Spacer()
                Button { showRegions = true } label: {
                    Label("Regions", systemImage: "list.bullet").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                }
                .foregroundStyle(.white)
                .glassSurface(Capsule(), interactive: true)
                .accessibilityHint("Choose a body region from a list")
            }
            Spacer()
            HStack {
                Text(isBack ? "BACK" : "FRONT").font(Typo.eyebrow).tracking(1.4).foregroundStyle(.white.opacity(0.6))
                Spacer()
                HStack(spacing: 0) {
                    Button { setZoom(zoom - 0.5) } label: { Image(systemName: "minus").frame(width: 40, height: 36) }
                        .accessibilityLabel("Zoom out")
                    Button { setZoom(1); selectedRegion = nil } label: { Image(systemName: "arrow.counterclockwise").frame(width: 40, height: 36) }
                        .accessibilityLabel("Reset view")
                    Button { setZoom(zoom + 0.5) } label: { Image(systemName: "plus").frame(width: 40, height: 36) }
                        .accessibilityLabel("Zoom in")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .glassSurface(Capsule(), interactive: true)
            }
        }
        .padding(Space.m)
    }

    func sideButton(_ title: String, back: Bool) -> some View {
        Button { rotate(toBack: back) } label: {
            Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(isBack == back ? Palette.navy : .white)
                .background(isBack == back ? Color.white : Color.clear, in: Capsule())
        }
        .accessibilityAddTraits(isBack == back ? .isSelected : [])
    }

    var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                if dragStart == nil { dragStart = angle }
                angle = (dragStart ?? 0) + Double(v.translation.width) * 0.6
            }
            .onEnded { _ in
                dragStart = nil
                rotate(toBack: isBack)
            }
    }

    var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = zoom }
                zoom = min(3, max(1, (zoomStart ?? 1) * v.magnification))
            }
            .onEnded { _ in zoomStart = nil }
    }

    func setZoom(_ z: CGFloat) {
        withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { zoom = min(3, max(1, z)) }
    }

    func rotate(toBack: Bool) {
        let target: Double = toBack ? (normalized(angle) >= 0 ? 180 : -180) : 0
        withAnimation(Motion.respecting(reduceMotion, .spring(response: 0.6, dampingFraction: 0.85))) { angle = target }
    }

    // MARK: Focus

    func focusFromRouter() {
        guard let id = router.bodyFocusNoteID, let note = notes.first(where: { $0.id == id }) else { return }
        focus(note)
        router.bodyFocusNoteID = nil
    }

    /// Rotate gently toward the note's region, zoom to a useful framing, reveal marker and date.
    func focus(_ note: HealthEvent) {
        focusedNoteID = note.id
        scrubDay = Double(note.date.dayNumber)
        guard let region = note.bodyRegion else { return }
        let back = map.preferredSideIsBack(region)
        withAnimation(Motion.respecting(reduceMotion, .spring(response: 0.8, dampingFraction: 0.88))) {
            angle = back ? 180 : 0
            selectedRegion = region
            zoom = 2.1
        }
    }

    // MARK: Region panel

    @ViewBuilder
    var regionPanel: some View {
        if let region = selectedRegion {
            let regionNotes = notes.filter { $0.bodyRegion == region }
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow(text: region.displayName, icon: "bl.bodynote", color: Palette.note)
                    Spacer()
                    Button { selectedRegion = nil; focusedNoteID = nil; setZoom(1) } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.baseline)
                    }
                    .accessibilityLabel("Close region")
                }
                if regionNotes.isEmpty {
                    Text("No notes here yet.").font(Typo.storySmall).foregroundStyle(Palette.ink)
                } else {
                    ForEach(regionNotes) { note in
                        NoteRow(note: note, today: today, focused: note.id == focusedNoteID) { focus(note) } onEdit: { editing = note }
                    }
                }
                HStack {
                    Button {
                        editing = HealthEvent(date: today, kind: .note, title: "", bodyRegion: region, createdAt: AppClock.now())
                    } label: {
                        Label("Add a note here", systemImage: "plus").font(.subheadline.weight(.semibold))
                    }
                    .glassButton(prominent: true)
                    if let focused = regionNotes.first(where: { $0.id == focusedNoteID }) {
                        Button { router.open(.walkDay(focused.date), snapshot: app.snapshot) } label: {
                            Label("Walking that day", systemImage: "figure.walk").font(.subheadline.weight(.semibold))
                        }
                        .glassButton()
                    }
                }
            }
            .card(tone: .tinted(Palette.note))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Timeline

    @ViewBuilder
    var timeline: some View {
        if let first = notes.map(\.date).min() {
            let lower = Double(first.adding(days: -14).dayNumber)
            let upper = Double(today.dayNumber)
            let value = Binding(get: { scrubDay ?? upper }, set: { scrubDay = $0; focusedNoteID = nil })
            let day = LocalDate(dayNumber: Int((scrubDay ?? upper).rounded()))
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Eyebrow(text: "Body history timeline", icon: "bl.calendar", color: Palette.note)
                    Spacer()
                    Text(day == today ? "Today" : Fmt.dayLabel(day) + ", \(day.year)").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                }
                ZStack(alignment: .leading) {
                    GeometryReader { geo in
                        ForEach(notes) { n in
                            let x = (Double(n.date.dayNumber) - lower) / max(1, upper - lower)
                            Circle().fill(Palette.note).frame(width: 8, height: 8)
                                .position(x: geo.size.width * CGFloat(x), y: geo.size.height / 2)
                        }
                    }
                    .frame(height: 12)
                    .allowsHitTesting(false)
                }
                Slider(value: value, in: lower...upper, step: 1)
                    .tint(Palette.note)
                    .accessibilityValue(Fmt.dayLabel(day))
                Text("Markers show notes that were unresolved on this date. The figure itself doesn't change — Blith doesn't reconstruct your body for past dates.")
                    .font(.caption).foregroundStyle(Palette.secondaryInk)
            }
            .card()
        }
    }

    // MARK: History list

    var historyList: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Notes", subtitle: notes.isEmpty ? "Tap a region above to add your first note" : "Newest first by the date it happened",
                          trailing: "Add") {
                editing = HealthEvent(date: today, kind: .note, title: "", bodyRegion: selectedRegion, createdAt: AppClock.now())
            }
            if notes.isEmpty {
                EmptyStateView(symbol: "bl.bodynote", title: "No body notes yet",
                               message: "Keep a short record of things like a sore knee or a rolled ankle, with the date it happened. Blith shows them beside your walking, never as a diagnosis.",
                               mascot: .pointing)
            } else {
                VStack(spacing: Space.s) {
                    ForEach(notes) { note in
                        NoteRow(note: note, today: today, focused: note.id == focusedNoteID) { focus(note) } onEdit: { editing = note }
                    }
                }
            }
        }
    }

    var regionList: some View {
        NavigationStack {
            List {
                ForEach(BodyRegion.allCases.filter { $0 != .other }) { region in
                    Button {
                        showRegions = false
                        withAnimation(Motion.respecting(reduceMotion, .spring(response: 0.7, dampingFraction: 0.88))) {
                            angle = map.preferredSideIsBack(region) ? 180 : 0
                            selectedRegion = region
                            zoom = 1.8
                        }
                    } label: {
                        HStack {
                            Text(region.displayName)
                            Spacer()
                            let count = notes.filter { $0.bodyRegion == region }.count
                            if count > 0 { Text("\(count) \(count == 1 ? "note" : "notes")").foregroundStyle(Palette.note) }
                        }
                    }
                    .foregroundStyle(Palette.ink)
                }
            }
            .navigationTitle("Body regions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRegions = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Barely perceptible breathing and a slow moving light, paused off screen and with Reduce Motion.
struct LivingFigure<Overlay: View>: View {
    let back: Bool
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var overlay: () -> Overlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        let running = visible && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { tl in
            let t = running ? tl.date.timeIntervalSinceReferenceDate : 0
            let breath = 1 + 0.004 * sin(t * 2 * .pi / 5.2)
            let sweep = CGFloat(sin(t * 2 * .pi / 9)) * width * 0.6
            ZStack {
                Image(back ? "body.back" : "body.front")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .overlay {
                        LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.5)
                            .offset(x: sweep)
                            .blendMode(.plusLighter)
                            .mask(Image(back ? "body.back" : "body.front").resizable().frame(width: width, height: height))
                            .allowsHitTesting(false)
                    }
                    .shadow(color: Palette.cyan.opacity(0.35), radius: 18)
                    .scaleEffect(x: 1, y: breath, anchor: .bottom)
                    .accessibilityHidden(true)
                overlay()
            }
            .frame(width: width, height: height)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

/// Wraps glass buttons so they blend on iOS 26.
struct GlassEffectGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .padding(3)
            .glassSurface(Capsule())
    }
}

struct NoteMarker: View {
    let note: HealthEvent
    let focused: Bool
    let today: LocalDate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Palette.note.opacity(0.35)).frame(width: 30, height: 30)
                .scaleEffect(pulse ? 1.35 : 0.9).opacity(pulse ? 0 : 0.8)
            Circle().fill(Palette.note).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            if focused {
                Text(Fmt.shortDate(note.date))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.note, in: Capsule())
                    .fixedSize()
                    .offset(y: -26)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(note.bodyRegion?.displayName ?? "Body") note: \(note.title), \(Fmt.dayLabel(note.date))")
        .accessibilityAddTraits(.isButton)
    }
}

struct NoteRow: View {
    let note: HealthEvent
    let today: LocalDate
    var focused = false
    let onFocus: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onFocus) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(spacing: 0) {
                    Circle().fill(note.isActive(on: today) ? Palette.note : Palette.baseline).frame(width: 10, height: 10)
                        .padding(.top, 5)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title.isEmpty ? note.kindLabel : note.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("\(note.bodyRegion?.displayName ?? "General") · \(note.kindLabel)\(note.severity.map { " · " + ["mild", "moderate", "strong"][max(0, min(2, $0 - 1))] } ?? "")")
                        .font(.caption).foregroundStyle(Palette.secondaryInk)
                    Text("Happened \(Fmt.dayLabel(note.date)), \(note.date.year) · written \(note.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(Palette.secondaryInk)
                    if let r = note.resolvedDate {
                        Text("Resolved \(Fmt.shortDate(r))").font(.caption2.weight(.semibold)).foregroundStyle(Palette.sleep)
                    }
                    if note.isSample {
                        Text("Sample note").font(.caption2.weight(.semibold)).foregroundStyle(Palette.review)
                    }
                }
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil.circle").font(.title3).foregroundStyle(Palette.secondaryInk) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit note")
            }
            .padding(Space.m)
            .background(focused ? Palette.noteSoft : Palette.card, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(focused ? Palette.note.opacity(0.4) : Palette.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this note on the body")
    }
}

/// Add or edit a body note. The event date is when it happened; the entry date is kept separately.
struct BodyNoteEditor: View {
    @State var note: HealthEvent
    let isNew: Bool
    let onSave: (HealthEvent) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var resolved = false
    @State private var resolvedOn = Date()
    @State private var confirmDelete = false

    init(note: HealthEvent, isNew: Bool, onSave: @escaping (HealthEvent) -> Void, onDelete: @escaping (String) -> Void) {
        _note = State(initialValue: note)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened? (e.g. rolled my right ankle)", text: $note.title, axis: .vertical)
                    TextField("Details (optional)", text: Binding(get: { note.note ?? "" }, set: { note.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Your words stay as you wrote them. Blith won't turn a note into a diagnosis.")
                }
                Section("Where and what") {
                    Picker("Region", selection: Binding(get: { note.bodyRegion ?? .other }, set: { note.bodyRegion = $0 })) {
                        ForEach(BodyRegion.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Kind", selection: $note.kind) {
                        ForEach(HealthEvent.Kind.allCases, id: \.self) { k in
                            Text(HealthEvent(date: note.date, kind: k, title: "").kindLabel).tag(k)
                        }
                    }
                    Picker("How it felt", selection: Binding(get: { note.severity ?? 0 }, set: { note.severity = $0 == 0 ? nil : $0 })) {
                        Text("Not set").tag(0)
                        Text("Mild").tag(1)
                        Text("Moderate").tag(2)
                        Text("Strong").tag(3)
                    }
                }
                Section {
                    DatePicker("Happened on", selection: $date, in: ...AppClock.now(), displayedComponents: .date)
                    Toggle("Resolved", isOn: $resolved)
                    if resolved {
                        DatePicker("Resolved on", selection: $resolvedOn, in: date...AppClock.now().addingTimeInterval(1), displayedComponents: .date)
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text(isNew ? "Written today. The date it happened can be earlier." :
                            "Written \(note.createdAt.formatted(date: .abbreviated, time: .omitted)).")
                }
                if !isNew {
                    Section {
                        Button("Delete note", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New body note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var n = note
                        n.date = LocalDate(date, calendar: .current)
                        n.resolvedDate = resolved ? LocalDate(resolvedOn, calendar: .current) : nil
                        n.title = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        n.isSample = n.isSample && !isNew
                        onSave(n)
                        dismiss()
                    }
                    .disabled(note.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(note.id)
                    dismiss()
                }
            }
            .onAppear {
                date = note.date.startDate(in: .current)
                resolved = note.resolvedDate != nil
                resolvedOn = note.resolvedDate?.startDate(in: .current) ?? AppClock.now()
            }
        }
    }
}
