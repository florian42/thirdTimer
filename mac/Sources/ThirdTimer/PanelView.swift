import AppKit
import SwiftUI
import ThirdTimerCore

/// The panel that opens from the menu bar item.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedDeliverable: UUID?
    @State private var checkpointText = ""
    @State private var handoffText = ""
    @State private var newName = ""
    @State private var newDeadline = Date().addingTimeInterval(3 * 86400)
    @State private var editingID: UUID?
    @State private var editName = ""
    @State private var editDeadline = Date()

    var body: some View {
        let snap = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let problem = model.loadProblem {
                    Text(problem).font(.caption).foregroundColor(.secondary)
                }
                timerSection(snap)
                Divider()
                ratioSection(snap)
                Divider()
                deliverablesSection(snap)
                Divider()
                todaySection(snap)
                SettingsSection()
                Divider()
                footer
            }
            .padding(16)
        }
        .frame(width: 360)
        .frame(maxHeight: 640)
        .onAppear { selectedDeliverable = snap.currentDeliverableID ?? snap.preselectedDeliverableID }
    }

    // MARK: Timer

    @ViewBuilder
    private func timerSection(_ snap: Snapshot) -> some View {
        switch snap.mode {
        case .idle:
            Text("Ready to start").font(.headline)
            deliverablePicker(snap)
            Button("Start working") {
                model.send(.startWork(deliverableID: selectedDeliverable))
            }
            .keyboardShortcut(.defaultAction)
            if snap.bankSeconds >= 1 {
                Text("Break time banked: \(Format.short(snap.bankSeconds))")
                    .font(.callout).foregroundColor(.secondary)
            }

        case .working:
            Text("Working on \(snap.currentDeliverableName ?? "no deliverable")").font(.headline)
            Text(Format.clock(snap.elapsedSeconds))
                .font(.system(size: 40, weight: .medium, design: .monospaced))
            Text("Break time earned: \(Format.clock(snap.bankSeconds))")
                .font(.callout).foregroundColor(.secondary)
            if let info = snap.returnInfo {
                returnInfoBox(info)
            }
            Button("Take a break (\(Format.short(snap.bankSeconds)))") {
                startBreak(nil)
            }
            .keyboardShortcut(.defaultAction)
            if !snap.partialBreakOptions.isEmpty {
                HStack {
                    Text("Or just:").foregroundColor(.secondary)
                    ForEach(snap.partialBreakOptions, id: \.self) { seconds in
                        Button("\(Int(seconds / 60)) min") { startBreak(seconds) }
                    }
                }
            }

        case .breaking:
            let remaining = snap.breakRemainingSeconds ?? 0
            Text("On a break").font(.headline)
            Text(Format.clock(abs(remaining)))
                .font(.system(size: 40, weight: .medium, design: .monospaced))
            Text(remaining >= 0 ? "left of this break" : "past the end of this break")
                .font(.callout).foregroundColor(.secondary)
            if snap.bankSeconds >= 1 {
                Text("Still banked: \(Format.short(snap.bankSeconds))")
                    .font(.callout).foregroundColor(.secondary)
            }
            breakNotes(snap)
            deliverablePicker(snap)
            Button("Resume work") {
                model.send(.resumeWork(deliverableID: selectedDeliverable))
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func startBreak(_ seconds: Double?) {
        checkpointText = ""
        handoffText = ""
        model.send(.startBreak(seconds: seconds))
    }

    @ViewBuilder
    private func breakNotes(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if snap.awaitingCheckpoint {
                Text("Where did you leave off? (optional)").font(.callout)
                HStack {
                    TextField("One line on the state of the work", text: $checkpointText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveCheckpoint() }
                    Button("Save") { saveCheckpoint() }
                        .disabled(checkpointText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if let text = model.state.currentBreak?.checkpoint {
                Text("Checkpoint: \(text)").font(.callout)
            }
            if snap.awaitingHandoff {
                Text("Anything Claude can work on while you're away? (optional)").font(.callout)
                HStack {
                    TextField("What you handed off", text: $handoffText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveHandoff() }
                    Button("Save") { saveHandoff() }
                        .disabled(handoffText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if let text = model.state.currentBreak?.handoff {
                Text("Handed off: \(text)").font(.callout)
            }
        }
    }

    private func saveCheckpoint() {
        model.send(.recordCheckpoint(checkpointText))
        checkpointText = ""
    }

    private func saveHandoff() {
        model.send(.recordHandoff(handoffText))
        handoffText = ""
    }

    private func returnInfoBox(_ info: ReturnInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let checkpoint = info.checkpoint {
                Text("Where you left off: \(checkpoint)")
            }
            if let handoff = info.handoff {
                Text("Handed off: \(handoff)")
            }
        }
        .font(.callout)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12))
        .cornerRadius(6)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Break ratio").font(.headline)
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
            Text("A change applies to work from now on. Break time already earned stays.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: Deliverables

    @ViewBuilder
    private func deliverablesSection(_ snap: Snapshot) -> some View {
        Text("Deliverables").font(.headline)
        if snap.activeDeliverables.isEmpty {
            Text("None yet. Add one below.").font(.callout).foregroundColor(.secondary)
        }
        ForEach(snap.activeDeliverables) { d in
            if editingID == d.id {
                editRow(d)
            } else {
                deliverableRow(d)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            TextField("New deliverable", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                DatePicker("Due", selection: $newDeadline)
                Button("Add") {
                    model.send(.addDeliverable(id: UUID(), name: newName, deadline: newDeadline))
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if !snap.doneDeliverables.isEmpty {
            DisclosureGroup("Done (\(snap.doneDeliverables.count))") {
                ForEach(snap.doneDeliverables) { d in
                    HStack {
                        Text(d.name)
                        Spacer()
                        Text(Format.short(d.investedSeconds)).foregroundColor(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func deliverableRow(_ d: DeliverableView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(d.name).fontWeight(.medium)
            Text("Due \(d.deadline.formatted(date: .abbreviated, time: .shortened))")
                .font(.callout).foregroundColor(.secondary)
            Text("Work time left: \(Format.short(d.runwaySeconds)) · Invested: \(Format.short(d.investedSeconds))")
                .font(.callout)
            if !d.checkpoints.isEmpty {
                DisclosureGroup("Checkpoints (\(d.checkpoints.count))") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(d.checkpoints.enumerated()), id: \.offset) { _, c in
                            Text("\(c.time.formatted(date: .abbreviated, time: .shortened))  \(c.text)")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.callout)
            }
            HStack {
                Button("Edit") {
                    editingID = d.id
                    editName = d.name
                    editDeadline = d.deadline
                }
                if !d.checkpoints.isEmpty {
                    Button("Copy log") { model.copyCheckpointLog(for: d.id) }
                }
                Button("Done") { model.send(.completeDeliverable(id: d.id)) }
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private func editRow(_ d: DeliverableView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $editName).textFieldStyle(.roundedBorder)
            DatePicker("Due", selection: $editDeadline)
            HStack {
                Button("Save") {
                    model.send(.editDeliverable(id: d.id, name: editName, deadline: editDeadline))
                    editingID = nil
                }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { editingID = nil }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: Today and footer

    private func todaySection(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today").font(.headline)
            Text("Work: \(Format.short(snap.todayWorkSeconds)) · Breaks: \(Format.short(snap.todayBreakSeconds))")
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Text("Hotkey: ⌃⌥T").font(.caption).foregroundColor(.secondary)
            Spacer()
            Button("Reset session") { model.send(.resetSession) }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
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
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Ask what Claude can work on during a break", isOn: Binding(
                    get: { model.state.settings.handoffPrompt },
                    set: { model.send(.setHandoffPrompt($0)) }
                ))
                Toggle("Start at login", isOn: Binding(
                    get: { model.state.settings.launchAtLogin },
                    set: { model.send(.setLaunchAtLogin($0)) }
                ))
                Text("Working hours").fontWeight(.medium)
                ForEach(SettingsSection.dayOrder, id: \.self) { index in
                    dayRow(index)
                }
            }
            .font(.callout)
            .padding(.top, 6)
        }
    }

    private func dayRow(_ index: Int) -> some View {
        let day = model.state.workingHours[index]
        return HStack {
            Toggle(SettingsSection.dayNames[index], isOn: Binding(
                get: { day.enabled },
                set: { newValue in change(index) { $0.enabled = newValue } }
            ))
            .frame(width: 70, alignment: .leading)
            minutePicker(value: day.startMinute) { newValue in change(index) { $0.startMinute = newValue } }
            Text("to")
            minutePicker(value: day.endMinute) { newValue in change(index) { $0.endMinute = newValue } }
        }
    }

    private func change(_ index: Int, _ edit: (inout DayHours) -> Void) {
        var hours = model.state.workingHours
        edit(&hours[index])
        model.send(.setWorkingHours(hours))
    }

    private func minutePicker(value: Int, set: @escaping (Int) -> Void) -> some View {
        Picker("", selection: Binding(get: { value }, set: set)) {
            ForEach(SettingsSection.halfHours, id: \.self) { minute in
                Text(String(format: "%02d:%02d", minute / 60, minute % 60)).tag(minute)
            }
        }
        .labelsHidden()
        .frame(width: 80)
    }
}
