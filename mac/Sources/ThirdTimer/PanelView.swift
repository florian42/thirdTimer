import AppKit
import SwiftUI
import ThirdTimerCore

/// Spacing comes from one scale, so every gap is a deliberate choice:
/// tight inside a group, wide between groups.
private enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

private let cardRadius: CGFloat = 8

/// The panel that opens from the menu bar item.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedDeliverable: UUID?
    @State private var checkpointText = ""
    @State private var handoffText = ""
    @State private var newName = ""
    @State private var newDeadline = PanelView.defaultDeadline()
    @State private var editingID: UUID?
    @State private var editName = ""
    @State private var editDeadline = Date()
    @State private var copiedID: UUID?
    @State private var confirmingReset = false

    var body: some View {
        let snap = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let problem = model.loadProblem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                timerSection(snap)
                ratioSection(snap)
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

    /// Three days ahead at the end of the working day, not at the current minute.
    private static func defaultDeadline() -> Date {
        let day = Date().addingTimeInterval(3 * 86400)
        return Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: Timer

    private func timerSection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            switch snap.mode {
            case .idle:
                Text("Ready to start").font(.title3.weight(.semibold))
                deliverablePicker(snap)
                primaryButton("Start working") {
                    model.send(.startWork(deliverableID: selectedDeliverable))
                }
                if snap.bankSeconds >= 60 {
                    secondary("\(Format.short(snap.bankSeconds)) of break banked")
                }

            case .working:
                VStack(alignment: .leading, spacing: Space.xs) {
                    secondary("Working on")
                    Text(snap.currentDeliverableName ?? "No deliverable")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    clock(snap.elapsedSeconds)
                    secondary("\(Format.clock(snap.bankSeconds)) of break earned").monospacedDigit()
                }
                if let info = snap.returnInfo {
                    returnInfoBox(info)
                }
                primaryButton("Take a break · \(Format.short(snap.bankSeconds))") {
                    startBreak(nil)
                }
                if !snap.partialBreakOptions.isEmpty {
                    HStack(spacing: Space.s) {
                        secondary("Or take just")
                        ForEach(snap.partialBreakOptions, id: \.self) { seconds in
                            Button("\(Int(seconds / 60)) min") { startBreak(seconds) }
                        }
                    }
                }

            case .breaking:
                let remaining = snap.breakRemainingSeconds ?? 0
                Text("On a break").font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: Space.xs) {
                    clock(abs(remaining))
                    secondary(remaining >= 0 ? "left of this break" : "past the end of this break")
                    if let note = breakBudgetNote(snap, remaining: remaining) {
                        secondary(note)
                    }
                }
                breakNotes(snap)
                deliverablePicker(snap)
                primaryButton("Resume work") {
                    model.send(.resumeWork(deliverableID: selectedDeliverable))
                }
            }
        }
    }

    /// Answers "can I afford this break?" while the break is still inside what was earned.
    private func breakBudgetNote(_ snap: Snapshot, remaining: Double) -> String? {
        guard remaining >= 0 else {
            // Past the end of a partial break: say what is still in the bank.
            return snap.bankSeconds >= 60 ? "\(Format.short(snap.bankSeconds)) of break still banked." : nil
        }
        var parts: [String] = []
        let staysBanked = snap.bankSeconds - remaining
        if staysBanked >= 60 {
            parts.append("\(Format.short(staysBanked)) more stays banked.")
        }
        if let current = snap.activeDeliverables.first(where: { $0.id == snap.currentDeliverableID }),
           !current.deadlinePassed {
            parts.append("This break is budgeted: \(Format.short(current.runwaySeconds)) of work time still left.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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

    private func startBreak(_ seconds: Double?) {
        checkpointText = ""
        handoffText = ""
        model.send(.startBreak(seconds: seconds))
    }

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
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(cardRadius)
    }

    private func deliverablePicker(_ snap: Snapshot) -> some View {
        Picker("Deliverable", selection: $selectedDeliverable) {
            Text("None").tag(UUID?.none)
            ForEach(snap.activeDeliverables) { d in
                Text(d.name).tag(UUID?.some(d.id))
            }
        }
    }

    // MARK: Ratio

    private func ratioSection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Break ratio")
            Picker("Break ratio", selection: Binding(
                get: { snap.ratioDenominator },
                set: { model.send(.setRatio(denominator: $0)) }
            )) {
                ForEach(Engine.allowedDenominators, id: \.self) { d in
                    Text("1/\(d)").tag(d)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("An hour of work earns \(60 / snap.ratioDenominator) min of break. A change applies from now on.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Deliverables

    private func deliverablesSection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Deliverables")
            if snap.activeDeliverables.isEmpty {
                secondary("Add what you have to deliver and when. Third Timer then shows how much work time is left.")
            }
            ForEach(snap.activeDeliverables) { d in
                if editingID == d.id {
                    editRow(d)
                } else {
                    deliverableRow(d)
                }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                TextField("New deliverable", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDeliverable)
                HStack(spacing: Space.s) {
                    Text("Due").font(.callout).foregroundStyle(.secondary)
                    DatePicker("Due", selection: $newDeadline).labelsHidden()
                    Spacer()
                    Button("Add", action: addDeliverable)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
        model.send(.addDeliverable(id: UUID(), name: newName, deadline: newDeadline))
        newName = ""
    }

    private func deliverableRow(_ d: DeliverableView) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(d.name).fontWeight(.medium).lineLimit(2)
                // The number that answers "can I afford a break?" leads; the rest is secondary.
                if d.deadlinePassed {
                    Text("Past its deadline").font(.callout)
                } else {
                    (Text(Format.short(d.runwaySeconds)).fontWeight(.semibold)
                        + Text(" of work time left").foregroundColor(.secondary))
                        .font(.callout)
                        .monospacedDigit()
                }
                secondary("Due \(d.deadline.formatted(date: .abbreviated, time: .shortened)) · \(Format.short(d.investedSeconds)) invested")
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
            // Row actions are quiet links: none of them is the main action of the panel.
            HStack(spacing: Space.m) {
                Button("Edit") {
                    editingID = d.id
                    editName = d.name
                    editDeadline = d.deadline
                }
                if !d.checkpoints.isEmpty {
                    Button(copiedID == d.id ? "Copied" : "Copy log") { copyLog(d.id) }
                }
                Button("Mark done") { model.send(.completeDeliverable(id: d.id)) }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(cardRadius)
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
                Text("Due").font(.callout).foregroundStyle(.secondary)
                DatePicker("Due", selection: $editDeadline).labelsHidden()
            }
            HStack(spacing: Space.s) {
                Button("Save") {
                    model.send(.editDeliverable(id: d.id, name: editName, deadline: editDeadline))
                    editingID = nil
                }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { editingID = nil }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(cardRadius)
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
                secondary("Hours invested and checkpoints are kept.")
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

/// Settings: hand-off prompt, start at login, working hours.
struct SettingsSection: View {
    @EnvironmentObject private var model: AppModel

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// Monday first in the list, as most working weeks start there.
    private static let dayOrder = [1, 2, 3, 4, 5, 6, 0]
    private static let halfHours = Array(stride(from: 0, through: 24 * 60, by: 30))

    var body: some View {
        DisclosureGroup("Settings") {
            VStack(alignment: .leading, spacing: Space.s) {
                Toggle("Ask what Claude can work on during a break", isOn: Binding(
                    get: { model.state.settings.handoffPrompt },
                    set: { model.send(.setHandoffPrompt($0)) }
                ))
                Toggle("Start at login", isOn: Binding(
                    get: { model.state.settings.launchAtLogin },
                    set: { model.send(.setLaunchAtLogin($0)) }
                ))
                Text("Working hours").fontWeight(.medium).padding(.top, Space.s)
                Text("Work time left is counted inside these hours.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(SettingsSection.dayOrder, id: \.self) { index in
                    dayRow(index)
                }
            }
            .font(.callout)
            .padding(.top, Space.s)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func dayRow(_ index: Int) -> some View {
        let day = model.state.workingHours[index]
        return HStack(spacing: Space.s) {
            Toggle(SettingsSection.dayNames[index], isOn: Binding(
                get: { day.enabled },
                set: { newValue in change(index) { $0.enabled = newValue } }
            ))
            .frame(width: 64, alignment: .leading)
            minutePicker(index, isStart: true)
            Text("to")
            minutePicker(index, isStart: false)
        }
        .foregroundStyle(.primary)
    }

    private func change(_ index: Int, _ edit: (inout DayHours) -> Void) {
        var hours = model.state.workingHours
        edit(&hours[index])
        model.send(.setWorkingHours(hours))
    }

    private func minutePicker(_ index: Int, isStart: Bool) -> some View {
        let day = model.state.workingHours[index]
        return Picker("", selection: Binding(
            get: { isStart ? day.startMinute : day.endMinute },
            set: { newValue in
                change(index) { if isStart { $0.startMinute = newValue } else { $0.endMinute = newValue } }
            }
        )) {
            ForEach(SettingsSection.halfHours, id: \.self) { minute in
                Text(String(format: "%02d:%02d", minute / 60, minute % 60)).tag(minute)
            }
        }
        .labelsHidden()
        .frame(width: 80)
    }
}
