import SwiftUI
import ThirdTimerCore

/// Settings: the rhythm of breaks, the bell, the hand-off prompt and start at login.
struct SettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var watcher = AppModel.shared.meetings

    /// Lunchtimes offered, in minutes after midnight: 11:00 to 14:30.
    private static let lunchTimes = Array(stride(from: 11 * 60, through: 14 * 60 + 30, by: 30))
    /// Times offered for the afternoon dip: 12:00 to 17:00.
    private static let dipTimes = Array(stride(from: 12 * 60, through: 17 * 60, by: 30))

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    var body: some View {
        let rhythm = model.state.rhythm
        Group {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Break ratio")
                    Picker("Break ratio", selection: Binding(
                        get: { model.state.ratioDenominator },
                        set: { model.send(.setRatio(denominator: $0)) }
                    )) {
                        ForEach(Engine.allowedDenominators, id: \.self) { d in
                            Text("1/\(d)").tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("An hour of work earns \(60 / model.state.ratioDenominator) min of break. A change applies from now on.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Toggle("Suggest a pause after unbroken work", isOn: Binding(
                        get: { model.state.rhythm.nudgeEnabled },
                        set: { value in change { $0.nudgeEnabled = value } }
                    ))
                    if rhythm.nudgeEnabled {
                        Stepper("After \(rhythm.firstNudgeMinutes) min, then every \(rhythm.repeatNudgeMinutes)", value: Binding(
                            get: { model.state.rhythm.firstNudgeMinutes },
                            set: { value in change { $0.firstNudgeMinutes = value } }
                        ), in: 15...180, step: 15)
                        .padding(.leading, 20)
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Toggle("Suggest lunch", isOn: Binding(
                        get: { model.state.rhythm.lunchEnabled },
                        set: { value in change { $0.lunchEnabled = value } }
                    ))
                    if rhythm.lunchEnabled {
                        HStack(spacing: Space.s) {
                            Text("At")
                            Picker("Lunchtime", selection: Binding(
                                get: { model.state.rhythm.lunchMinuteOfDay },
                                set: { value in change { $0.lunchMinuteOfDay = value } }
                            )) {
                                ForEach(SettingsSection.lunchTimes, id: \.self) { minute in
                                    Text(SettingsSection.clock(minute)).tag(minute)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            Stepper("for \(rhythm.lunchLengthMinutes) min", value: Binding(
                                get: { model.state.rhythm.lunchLengthMinutes },
                                set: { value in change { $0.lunchLengthMinutes = value } }
                            ), in: 15...180, step: 15)
                        }
                        .padding(.leading, 20)
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Toggle("Suggest a pause sooner in the afternoon dip", isOn: Binding(
                        get: { model.state.rhythm.dipEnabled },
                        set: { value in change { $0.dipEnabled = value } }
                    ))
                    if rhythm.dipEnabled {
                        HStack(spacing: Space.s) {
                            Picker("Dip starts", selection: Binding(
                                get: { model.state.rhythm.dipStartMinute },
                                set: { value in change { $0.dipStartMinute = value } }
                            )) {
                                ForEach(SettingsSection.dipTimes, id: \.self) { minute in
                                    Text(SettingsSection.clock(minute)).tag(minute)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            Text("to")
                            Picker("Dip ends", selection: Binding(
                                get: { model.state.rhythm.dipEndMinute },
                                set: { value in change { $0.dipEndMinute = value } }
                            )) {
                                ForEach(SettingsSection.dipTimes, id: \.self) { minute in
                                    Text(SettingsSection.clock(minute)).tag(minute)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                        }
                        .padding(.leading, 20)
                        Text("In these hours a pause is suggested after \(rhythm.dipNudgeMinutes) min, and a walk for the break.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                }

                Toggle("Pause during calendar meetings", isOn: Binding(
                    get: { model.state.meetings.pauseEnabled },
                    set: { on in
                        model.send(.setMeetingPause(on))
                        if on { model.watchCalendar() }
                    }
                ))
                if model.state.meetings.pauseEnabled, watcher.access == .denied {
                    Text("Third Timer can't read your calendar. Allow it in System Settings › Privacy & Security › Calendars, then restart the app.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Toggle("Pause while I'm away from the Mac", isOn: Binding(
                        get: { model.state.presence.pauseEnabled },
                        set: { model.send(.setAwayPause($0)) }
                    ))
                    Text("Away means: screen locked, display off, Mac asleep, or no input for 10 min while working. Work starts again when you are back.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                Toggle("Hold suggestions during calls", isOn: Binding(
                    get: { model.state.presence.quietOnCalls },
                    set: { model.send(.setQuietOnCalls($0)) }
                ))

                Toggle("Ring a soft bell", isOn: Binding(
                    get: { model.state.rhythm.bellEnabled },
                    set: { value in change { $0.bellEnabled = value } }
                ))
                Toggle("Ask what Claude can work on during a break", isOn: Binding(
                    get: { model.state.settings.handoffPrompt },
                    set: { model.send(.setHandoffPrompt($0)) }
                ))
                Toggle("Start at login", isOn: Binding(
                    get: { model.state.settings.launchAtLogin },
                    set: { model.send(.setLaunchAtLogin($0)) }
                ))
            }
            .font(.callout)
            .foregroundStyle(.primary)
        }
    }

    private func change(_ edit: (inout Rhythm) -> Void) {
        var rhythm = model.state.rhythm
        edit(&rhythm)
        model.send(.setRhythm(rhythm))
    }
}
