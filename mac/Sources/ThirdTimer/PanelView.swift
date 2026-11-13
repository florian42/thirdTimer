import AppKit
import SwiftUI
import ThirdTimerCore

/// Spacing comes from one scale, so every gap is a deliberate choice:
/// tight inside a group, wide between groups.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

private let cardRadius: CGFloat = 12

/// How each state looks: one colour and one symbol, used in the panel and
/// the menu bar alike. The symbol and the words carry the state; the colour
/// only supports them.
struct Mood {
    /// The ring, the label and the glow behind the panel.
    var tint: Color
    /// A deeper shade of the tint, dark enough for white text on the main button.
    var ink: Color
    var symbol: String
    var title: String

    private static func shade(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }

    static func of(_ snap: Snapshot) -> Mood {
        switch snap.mode {
        case .idle:
            if snap.pausedByMeeting {
                return Mood(tint: .indigo, ink: shade(0.33, 0.31, 0.78), symbol: "person.2.fill", title: "In a meeting")
            }
            return snap.isPaused
                ? Mood(tint: .indigo, ink: shade(0.33, 0.31, 0.78), symbol: "pause.circle.fill", title: "Paused")
                : Mood(tint: .blue, ink: shade(0.10, 0.42, 0.86), symbol: "pause.circle", title: "Ready when you are")
        case .working:
            switch snap.suggestion {
            case .lunch:
                return Mood(tint: .orange, ink: shade(0.78, 0.40, 0.04), symbol: "fork.knife", title: "Lunchtime")
            case .pause:
                return Mood(tint: .mint, ink: shade(0.04, 0.52, 0.47), symbol: "leaf.fill", title: "A good moment to pause")
            case nil:
                return Mood(tint: .green, ink: shade(0.11, 0.53, 0.30), symbol: "timer", title: "Working")
            }
        case .breaking:
            return snap.isLunchBreak
                ? Mood(tint: .orange, ink: shade(0.78, 0.40, 0.04), symbol: "fork.knife", title: "Lunch")
                : Mood(tint: .teal, ink: shade(0.07, 0.47, 0.58), symbol: "cup.and.saucer.fill", title: "On a break")
        }
    }
}

/// The one main action of each state: a solid pill across the panel.
struct PillButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(fill.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

/// Smaller choices next to the main action.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.08), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Things you may do but rarely need: plain words, no box.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// The panel that opens from the menu bar item.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedDeliverable: UUID?
    @State private var checkpointText = ""
    @State private var handoffText = ""
    @State private var newName = ""
    @State private var editingID: UUID?
    @State private var editName = ""
    @State private var copiedID: UUID?
    @State private var confirmingReset = false
    // `--settings` opens on the settings page, for screenshots.
    @State private var showingSettings = CommandLine.arguments.contains("--settings")

    var body: some View {
        let snap = model.snapshot
        let mood = Mood.of(snap)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header(mood)
                if let problem = model.loadProblem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                if confirmingReset {
                    resetConfirmation(snap)
                }
                if showingSettings {
                    SettingsSection()
                } else {
                    hero(snap, mood)
                    todaySection(snap)
                    deliverablesSection(snap, mood)
                    Text("⌃⌥T starts, breaks and resumes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Space.l)
        }
        // A fixed size: a scroll view has no height of its own, so without
        // one the panel collapses to nothing.
        .frame(width: 360, height: 620)
        // The colour of the state glows softly from the top, behind everything.
        .background(alignment: .top) {
            LinearGradient(
                colors: [mood.tint.opacity(0.30), mood.tint.opacity(0.10), mood.tint.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 400)
        }
        // Keep the picker on the deliverable in use, also when the hotkey changed it.
        .onChange(of: model.state.lastDeliverableID) { newValue in
            selectedDeliverable = newValue
        }
        .onAppear {
            selectedDeliverable = snap.currentDeliverableID ?? snap.preselectedDeliverableID
            // Don't open with the cursor in a text field: Return should trigger the main action.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
    }

    // MARK: Header

    private func header(_ mood: Mood) -> some View {
        HStack(spacing: Space.m) {
            if showingSettings {
                Text("Settings").font(.callout.weight(.semibold))
            } else {
                Label(mood.title, systemImage: mood.symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(mood.tint)
            }
            Spacer()
            if showingSettings {
                Button("Done") { showingSettings = false }
                    .buttonStyle(ChipButtonStyle())
            } else {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Settings")
                Menu {
                    Button("Reset session…") { confirmingReset = true }
                    Divider()
                    Button("Quit Third Timer") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Reset the session, or quit")
            }
        }
    }

    // MARK: Hero

    /// The top of the panel: what is happening now, and the one thing to do next.
    private func hero(_ snap: Snapshot, _ mood: Mood) -> some View {
        VStack(spacing: Space.l) {
            if snap.mode == .working {
                Text(snap.currentDeliverableName ?? "No deliverable")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            ZStack {
                TimeRing(progress: ringProgress(snap), tint: mood.tint)
                ringCenter(snap, mood)
                    .frame(width: 150)
            }
            .frame(width: 196, height: 196)
            if let line = heroLine(snap) {
                secondary(line).multilineTextAlignment(.center)
            }
            heroActions(snap, mood)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func ringCenter(_ snap: Snapshot, _ mood: Mood) -> some View {
        switch snap.mode {
        case .idle:
            if snap.isPaused {
                clockStack(snap.elapsedSeconds, caption: snap.pausedByMeeting ? "in a meeting" : "paused")
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(mood.tint.opacity(0.55))
                    .accessibilityHidden(true)
            }
        case .working:
            clockStack(snap.elapsedSeconds, caption: "\(Format.short(snap.bankSeconds)) break earned")
        case .breaking:
            let remaining = snap.breakRemainingSeconds ?? 0
            clockStack(abs(remaining), caption: remaining >= 0 ? "left" : "past the end")
        }
    }

    private func clockStack(_ seconds: Double, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(Format.clock(seconds))
                .font(.system(size: 42, weight: .medium, design: .rounded))
                .monospacedDigit()
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// One calm sentence under the ring, only when there is something to say.
    private func heroLine(_ snap: Snapshot) -> String? {
        switch snap.mode {
        case .idle:
            let kept = snap.bankSeconds >= 60 ? " \(Format.short(snap.bankSeconds)) of break is kept." : ""
            if snap.pausedByMeeting {
                return "Paused by your calendar. Work starts again when the meeting ends.\(kept)"
            }
            if snap.isPaused {
                return "Nothing is counted and the bell stays quiet.\(kept)"
            }
            return snap.bankSeconds >= 60
                ? "\(Format.short(snap.bankSeconds)) of break banked"
                : "Work as long as you like. Every hour earns \(60 / snap.ratioDenominator) minutes of break."
        case .working:
            switch snap.suggestion {
            case .pause: return "You've been at it for \(Format.short(snap.elapsedSeconds))."
            case .lunch: return "A proper lunch sets up the afternoon."
            case nil: return nil
            }
        case .breaking:
            let remaining = snap.breakRemainingSeconds ?? 0
            if snap.isLunchBreak {
                guard remaining >= 0 else { return nil }
                let end = model.now.addingTimeInterval(remaining)
                return "Enjoy your lunch. The bell rings at \(end.formatted(date: .omitted, time: .shortened))."
            }
            guard remaining >= 0 else {
                return snap.bankSeconds >= 60 ? "\(Format.short(snap.bankSeconds)) still banked" : nil
            }
            let staysBanked = snap.bankSeconds - remaining
            return staysBanked >= 60 ? "\(Format.short(staysBanked)) more stays banked" : nil
        }
    }

    /// While working the ring fills toward the suggested pause; on a break it empties.
    private func ringProgress(_ snap: Snapshot) -> Double {
        switch snap.mode {
        case .idle:
            return 0
        case .working:
            guard let pauseAfter = snap.pauseAfterSeconds, pauseAfter > 0 else { return 0 }
            return min(1, snap.elapsedSeconds / pauseAfter)
        case .breaking:
            let remaining = max(0, snap.breakRemainingSeconds ?? 0)
            let total = remaining + snap.elapsedSeconds
            return total > 0 ? remaining / total : 0
        }
    }

    @ViewBuilder
    private func heroActions(_ snap: Snapshot, _ mood: Mood) -> some View {
        switch snap.mode {
        case .idle:
            deliverablePicker(snap)
            primaryButton(snap.isPaused ? "Back to work" : "Start working", mood) {
                model.send(.startWork(deliverableID: selectedDeliverable))
            }

        case .working:
            if let info = snap.returnInfo {
                returnInfoBox(info)
            }
            if snap.suggestion == .lunch {
                primaryButton("Take lunch · \(model.state.rhythm.lunchLengthMinutes) min", mood) {
                    startBreak { model.send(.startLunch) }
                }
                Button("Short break · \(Format.short(snap.bankSeconds))") {
                    startBreak { model.send(.startBreak(seconds: nil)) }
                }
                .buttonStyle(ChipButtonStyle())
            } else {
                primaryButton("Take a break · \(Format.short(snap.bankSeconds))", mood) {
                    startBreak { model.send(.startBreak(seconds: nil)) }
                }
                if !snap.partialBreakOptions.isEmpty {
                    HStack(spacing: Space.s) {
                        ForEach(snap.partialBreakOptions, id: \.self) { seconds in
                            Button("\(Int(seconds / 60)) min") {
                                startBreak { model.send(.startBreak(seconds: seconds)) }
                            }
                            .buttonStyle(ChipButtonStyle())
                        }
                    }
                }
            }
            HStack(spacing: Space.l) {
                pauseButton
                if snap.suggestion != nil {
                    Button("Not now") { model.send(.dismissSuggestion) }
                        .buttonStyle(QuietButtonStyle())
                }
            }

        case .breaking:
            Label(breakTip(snap), systemImage: snap.movementSuggested ? "figure.walk" : "eye")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            breakNotes(snap)
            deliverablePicker(snap)
            primaryButton("Resume work", mood) {
                model.send(.resumeWork(deliverableID: selectedDeliverable))
            }
            pauseButton
        }
    }

    private func breakTip(_ snap: Snapshot) -> String {
        if snap.isLunchBreak { return "Away from the desk if you can." }
        if snap.movementSuggested {
            return "Energy dips around now. A short walk lifts it more than the screen does."
        }
        return "Step away from the screen. Look out of the window, stretch, get some water."
    }

    /// For a meeting, or anything else that is neither work on a deliverable nor a break.
    private var pauseButton: some View {
        Button {
            model.send(.pause)
        } label: {
            Label("Pause for a meeting", systemImage: "person.2")
        }
        .buttonStyle(QuietButtonStyle())
        .help("Stops the timer. Nothing is earned or spent, and the bell stays quiet.")
    }

    private func startBreak(_ send: () -> Void) {
        checkpointText = ""
        handoffText = ""
        send()
    }

    private func secondary(_ text: String) -> Text {
        Text(text).font(.callout).foregroundColor(.secondary)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func primaryButton(_ title: String, _ mood: Mood, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PillButtonStyle(fill: mood.ink))
            .keyboardShortcut(.defaultAction)
    }

    /// A quiet surface that groups related things without a border.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    // MARK: Notes

    @ViewBuilder
    private func breakNotes(_ snap: Snapshot) -> some View {
        if snap.awaitingCheckpoint {
            noteField(
                label: "Where did you leave off?",
                placeholder: "One line on the state of the work",
                text: $checkpointText
            ) {
                model.send(.recordCheckpoint(checkpointText))
                checkpointText = ""
            }
        } else if let text = model.state.currentBreak?.checkpoint {
            savedNote(label: "Where you left off", text: text)
        }
        if snap.awaitingHandoff {
            noteField(
                label: "Hand off to Claude",
                placeholder: "What can it work on while you're away?",
                text: $handoffText
            ) {
                model.send(.recordHandoff(handoffText))
                handoffText = ""
            }
        } else if let text = model.state.currentBreak?.handoff {
            savedNote(label: "Handed off", text: text)
        }
    }

    private func noteField(
        label: String, placeholder: String, text: Binding<String>, save: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(label).font(.callout)
                Text("Optional").font(.callout).foregroundStyle(.tertiary)
            }
            HStack(spacing: Space.s) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func savedNote(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.callout).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func returnInfoBox(_ info: ReturnInfo) -> some View {
        card {
            VStack(alignment: .leading, spacing: Space.s) {
                if let checkpoint = info.checkpoint {
                    savedNote(label: "Where you left off", text: checkpoint)
                }
                if let handoff = info.handoff {
                    savedNote(label: "Handed off", text: handoff)
                }
            }
            .padding(Space.m)
        }
    }

    private func deliverablePicker(_ snap: Snapshot) -> some View {
        Picker("Working on", selection: $selectedDeliverable) {
            Text("Nothing in particular").tag(UUID?.none)
            ForEach(snap.activeDeliverables) { d in
                Text(d.name).tag(UUID?.some(d.id))
            }
        }
    }

    // MARK: Today

    /// Three numbers for the day. The value leads; the label is small beneath it.
    private func todaySection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Today")
            HStack(spacing: Space.s) {
                stat(Format.short(snap.todayWorkSeconds), "worked")
                stat(Format.short(snap.todayBreakSeconds), "on breaks")
                stat(Format.short(snap.bankSeconds), "banked")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        card {
            VStack(spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.xs)
        }
    }

    // MARK: Deliverables

    private func deliverablesSection(_ snap: Snapshot, _ mood: Mood) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Deliverables")
            card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(snap.activeDeliverables) { d in
                        Group {
                            if editingID == d.id {
                                editRow(d)
                            } else {
                                deliverableRow(d, inUse: snap.mode == .working && snap.currentDeliverableID == d.id, mood)
                            }
                        }
                        .padding(Space.m)
                        Divider().padding(.leading, Space.m)
                    }
                    HStack(spacing: Space.s) {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("New deliverable", text: $newName)
                            .textFieldStyle(.plain)
                            .onSubmit(addDeliverable)
                        if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: addDeliverable)
                        }
                    }
                    .padding(Space.m)
                }
            }
            if snap.activeDeliverables.isEmpty {
                secondary("Add what you're working on, and Third Timer keeps track of the time you put into it.")
            }
            if !snap.doneDeliverables.isEmpty {
                DisclosureGroup("Done (\(snap.doneDeliverables.count))") {
                    ForEach(snap.doneDeliverables) { d in
                        HStack(alignment: .firstTextBaseline) {
                            Text(d.name).lineLimit(2)
                            Spacer()
                            Text(Format.short(d.investedSeconds)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func addDeliverable() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.send(.addDeliverable(id: UUID(), name: newName))
        newName = ""
    }

    private func deliverableRow(_ d: DeliverableView, inUse: Bool, _ mood: Mood) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                // A dot marks the one being worked on right now.
                Circle()
                    .fill(inUse ? mood.tint : Color.primary.opacity(0.15))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(d.name).fontWeight(.medium).lineLimit(2)
                Spacer(minLength: Space.s)
                Text(Format.short(d.investedSeconds))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .help("Time invested")
                // Row actions sit in a quiet menu: none of them is the main action of the panel.
                Menu {
                    Button("Rename") {
                        editingID = d.id
                        editName = d.name
                    }
                    if !d.checkpoints.isEmpty {
                        Button("Copy checkpoint log") { copyLog(d.id) }
                    }
                    Divider()
                    Button("Mark as done") { model.send(.completeDeliverable(id: d.id)) }
                } label: {
                    Image(systemName: copiedID == d.id ? "checkmark.circle" : "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Rename, copy the checkpoint log, or mark as done")
            }
            if !d.checkpoints.isEmpty {
                DisclosureGroup("Checkpoints (\(d.checkpoints.count))") {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(d.checkpoints.enumerated()), id: \.offset) { _, c in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.time.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(c.text).font(.callout)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, Space.xs)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, Space.l)
            }
        }
    }

    private func copyLog(_ id: UUID) {
        model.copyCheckpointLog(for: id)
        copiedID = id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == id { copiedID = nil }
        }
    }

    private func editRow(_ d: DeliverableView) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            TextField("Name", text: $editName).textFieldStyle(.roundedBorder)
            HStack(spacing: Space.s) {
                Button("Save") {
                    model.send(.renameDeliverable(id: d.id, name: editName))
                    editingID = nil
                }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { editingID = nil }
            }
        }
    }

    // MARK: Reset

    /// Reset throws away banked break time, so it asks first.
    private func resetConfirmation(_ snap: Snapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(snap.bankSeconds >= 60
                    ? "Stop the timer and clear \(Format.short(snap.bankSeconds)) of banked break time?"
                    : "Stop the timer and start a fresh session?")
                    .font(.callout)
                secondary("Time invested and checkpoints are kept.")
                HStack(spacing: Space.s) {
                    Button("Reset session", role: .destructive) {
                        model.send(.resetSession)
                        confirmingReset = false
                    }
                    Button("Cancel") { confirmingReset = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Space.m)
        }
    }
}

/// The ring around the time: it fills while you work toward a pause, and
/// empties during a break.
struct TimeRing: View {
    var progress: Double
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 10)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(5)
        .accessibilityHidden(true)
    }
}
