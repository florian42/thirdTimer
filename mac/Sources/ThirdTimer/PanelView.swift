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

/// How each state looks: one system colour and one symbol, used in the
/// panel and the menu bar alike. The symbol and the words carry the state;
/// the colour only supports them.
struct Mood {
    var tint: Color
    var symbol: String
    var title: String

    static func of(_ snap: Snapshot) -> Mood {
        switch snap.mode {
        case .idle:
            return Mood(tint: .secondary, symbol: "pause.circle", title: "Ready when you are")
        case .working:
            switch snap.suggestion {
            case .lunch: return Mood(tint: .orange, symbol: "fork.knife", title: "Lunchtime")
            case .pause: return Mood(tint: .mint, symbol: "leaf.fill", title: "A good moment to pause")
            case nil: return Mood(tint: .green, symbol: "timer", title: "Working")
            }
        case .breaking:
            return snap.isLunchBreak
                ? Mood(tint: .orange, symbol: "fork.knife", title: "Lunch")
                : Mood(tint: .teal, symbol: "cup.and.saucer.fill", title: "On a break")
        }
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

    var body: some View {
        let snap = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let problem = model.loadProblem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                hero(snap)
                deliverablesSection(snap)
                todaySection(snap)
                SettingsSection()
                footer(snap)
            }
            .padding(Space.l)
        }
        // A fixed size: a scroll view has no height of its own, so without
        // one the panel collapses to nothing.
        .frame(width: 360, height: 560)
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

    // MARK: Hero

    /// The top card: what is happening now, and the one thing to do next.
    private func hero(_ snap: Snapshot) -> some View {
        let mood = Mood.of(snap)
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Label(mood.title, systemImage: mood.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(mood.tint)
                    heroText(snap)
                }
                Spacer(minLength: 0)
                if let progress = ringProgress(snap) {
                    ProgressRing(progress: progress, tint: mood.tint)
                        .frame(width: 44, height: 44)
                        .padding(.top, Space.xs)
                }
            }
            heroActions(snap)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [mood.tint.opacity(0.18), mood.tint.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom))
        )
    }

    @ViewBuilder
    private func heroText(_ snap: Snapshot) -> some View {
        switch snap.mode {
        case .idle:
            if snap.bankSeconds >= 60 {
                secondary("\(Format.short(snap.bankSeconds)) of break banked")
            } else {
                secondary("Work as long as you like. Every hour earns \(60 / snap.ratioDenominator) minutes of break.")
            }
        case .working:
            Text(snap.currentDeliverableName ?? "No deliverable")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            clock(snap.elapsedSeconds)
            secondary(workingLine(snap))
        case .breaking:
            let remaining = snap.breakRemainingSeconds ?? 0
            clock(abs(remaining))
            secondary(breakLine(snap, remaining: remaining))
        }
    }

    private func workingLine(_ snap: Snapshot) -> String {
        let earned = "\(Format.short(snap.bankSeconds)) of break earned"
        switch snap.suggestion {
        case .pause: return "You've been at it for \(Format.short(snap.elapsedSeconds)). \(earned)."
        case .lunch: return "A proper lunch sets up the afternoon."
        case nil: return earned
        }
    }

    private func breakLine(_ snap: Snapshot, remaining: Double) -> String {
        if snap.isLunchBreak {
            guard remaining >= 0 else { return "past the end of lunch" }
            let end = model.now.addingTimeInterval(remaining)
            return "Enjoy your lunch. The bell rings at \(end.formatted(date: .omitted, time: .shortened))."
        }
        guard remaining >= 0 else {
            return snap.bankSeconds >= 60
                ? "past the end of this break · \(Format.short(snap.bankSeconds)) still banked"
                : "past the end of this break"
        }
        let staysBanked = snap.bankSeconds - remaining
        return staysBanked >= 60
            ? "left of this break · \(Format.short(staysBanked)) more stays banked"
            : "left of this break"
    }

    /// While working the ring fills toward the suggested pause; on a break it empties.
    private func ringProgress(_ snap: Snapshot) -> Double? {
        switch snap.mode {
        case .idle:
            return nil
        case .working:
            guard let pauseAfter = snap.pauseAfterSeconds, pauseAfter > 0 else { return nil }
            return min(1, snap.elapsedSeconds / pauseAfter)
        case .breaking:
            let remaining = max(0, snap.breakRemainingSeconds ?? 0)
            let total = remaining + snap.elapsedSeconds
            return total > 0 ? remaining / total : 0
        }
    }

    @ViewBuilder
    private func heroActions(_ snap: Snapshot) -> some View {
        switch snap.mode {
        case .idle:
            deliverablePicker(snap)
            primaryButton("Start working") {
                model.send(.startWork(deliverableID: selectedDeliverable))
            }

        case .working:
            if let info = snap.returnInfo {
                returnInfoBox(info)
            }
            if snap.suggestion == .lunch {
                primaryButton("Take lunch · \(model.state.rhythm.lunchLengthMinutes) min") {
                    startBreak { model.send(.startLunch) }
                }
                HStack(spacing: Space.s) {
                    Button("Short break · \(Format.short(snap.bankSeconds))") {
                        startBreak { model.send(.startBreak(seconds: nil)) }
                    }
                    Spacer()
                    notNowButton
                }
            } else {
                primaryButton("Take a break · \(Format.short(snap.bankSeconds))") {
                    startBreak { model.send(.startBreak(seconds: nil)) }
                }
                HStack(spacing: Space.s) {
                    if !snap.partialBreakOptions.isEmpty {
                        // "Not now" needs the room when a pause is suggested.
                        if snap.suggestion == nil {
                            secondary("Or just")
                        }
                        ForEach(snap.partialBreakOptions, id: \.self) { seconds in
                            Button("\(Int(seconds / 60)) min") {
                                startBreak { model.send(.startBreak(seconds: seconds)) }
                            }
                            .fixedSize()
                        }
                    }
                    Spacer()
                    if snap.suggestion == .pause {
                        notNowButton
                    }
                }
            }

        case .breaking:
            Label(breakTip(snap), systemImage: snap.movementSuggested ? "figure.walk" : "eye")
            .font(.callout)
            .foregroundStyle(.secondary)
            breakNotes(snap)
            deliverablePicker(snap)
            primaryButton("Resume work") {
                model.send(.resumeWork(deliverableID: selectedDeliverable))
            }
        }
    }

    private func breakTip(_ snap: Snapshot) -> String {
        if snap.isLunchBreak { return "Away from the desk if you can." }
        if snap.movementSuggested {
            return "Energy dips around now. A short walk lifts it more than the screen does."
        }
        return "Step away from the screen. Look out of the window, stretch, get some water."
    }

    private var notNowButton: some View {
        Button("Not now") { model.send(.dismissSuggestion) }
            .buttonStyle(.link)
            .font(.callout)
    }

    private func startBreak(_ send: () -> Void) {
        checkpointText = ""
        handoffText = ""
        send()
    }

    private func clock(_ seconds: Double) -> some View {
        Text(Format.clock(seconds))
            .font(.system(size: 48, weight: .medium, design: .rounded))
            .monospacedDigit()
            .tracking(-1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func secondary(_ text: String) -> Text {
        Text(text).font(.callout).foregroundColor(.secondary)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    /// The one main action of each state: solid, large and full width.
    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
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
    }

    private func returnInfoBox(_ info: ReturnInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let checkpoint = info.checkpoint {
                savedNote(label: "Where you left off", text: checkpoint)
            }
            if let handoff = info.handoff {
                savedNote(label: "Handed off", text: handoff)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func deliverablePicker(_ snap: Snapshot) -> some View {
        Picker("Working on", selection: $selectedDeliverable) {
            Text("Nothing in particular").tag(UUID?.none)
            ForEach(snap.activeDeliverables) { d in
                Text(d.name).tag(UUID?.some(d.id))
            }
        }
    }

    // MARK: Deliverables

    private func deliverablesSection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Deliverables")
            if snap.activeDeliverables.isEmpty {
                secondary("Add what you're working on, and Third Timer keeps track of the time you put into it.")
            }
            ForEach(snap.activeDeliverables) { d in
                if editingID == d.id {
                    editRow(d)
                } else {
                    deliverableRow(d)
                }
            }
            HStack(spacing: Space.s) {
                TextField("New deliverable", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDeliverable)
                Button("Add", action: addDeliverable)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, Space.xs)
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

    private func deliverableRow(_ d: DeliverableView) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(d.name).fontWeight(.medium).lineLimit(2)
                    (Text(Format.short(d.investedSeconds)).fontWeight(.semibold)
                        + Text(" invested").foregroundColor(.secondary))
                        .font(.callout)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
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
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
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
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    // MARK: Today and footer

    private func todaySection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Today")
            Text("\(Format.short(snap.todayWorkSeconds)) worked · \(Format.short(snap.todayBreakSeconds)) on breaks")
                .font(.callout)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func footer(_ snap: Snapshot) -> some View {
        if confirmingReset {
            // Reset throws away banked break time, so it asks first.
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
        } else {
            HStack(spacing: Space.m) {
                Text("⌃⌥T starts, breaks and resumes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset…") { confirmingReset = true }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }
}

/// A thin ring: it fills while you work toward a pause, and empties during a break.
struct ProgressRing: View {
    var progress: Double
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}
