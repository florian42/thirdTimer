import Foundation
import Testing
import ThirdTimerCore

/// Every test drives the session engine through its one entry point:
/// events with times go in, and the state the user would see is checked.
/// A fresh suite value is made for each test, so nothing leaks between them.
struct EngineTests {
    let engine: Engine
    var state = EngineState()
    var lastEffects: [Effect] = []

    let report = UUID()
    let slides = UUID()

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        engine = Engine(calendar: calendar)
    }

    func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.001
    }

    /// Monday 9 November 2026, at the given time, UTC.
    func mon(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 9) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return engine.calendar.date(from: c)!
    }

    mutating func send(_ event: Event, at time: Date) {
        let (next, effects) = engine.reduce(state, event, now: time)
        state = next
        lastEffects = effects
    }

    func view(at time: Date) -> Snapshot {
        engine.snapshot(state, now: time)
    }

    mutating func addReport() {
        send(.addDeliverable(id: report, name: "Report"), at: mon(8))
    }

    let minute = 60.0
    let hour = 3600.0

    // MARK: Menu bar and basic timing (stories 2-4, 6-8, 12)

    @Test mutating func idleIsShownAsIdle() {
        #expect(view(at: mon(9)).mode == .idle)
        #expect(view(at: mon(9)).menuTitle == "Idle")
    }

    @Test mutating func workingShowsDeliverableAndElapsedTime() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        let v = view(at: mon(9, 34))
        #expect(v.mode == .working)
        #expect(v.menuTitle == "Report · 34m")
        #expect(v.elapsedSeconds == 34 * minute)
    }

    @Test mutating func longStintShowsHoursAndMinutes() {
        send(.startWork(deliverableID: nil), at: mon(9))
        #expect(view(at: mon(10, 5)).menuTitle == "Working · 1h 05m")
    }

    @Test mutating func breakShowsCountdown() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        let v = view(at: mon(9, 53, 48))
        #expect(v.mode == .breaking)
        #expect(near(v.breakRemainingSeconds!, 6 * minute + 12))
        #expect(v.menuTitle == "Break · 6:12 left")
    }

    @Test mutating func resumeReturnsToWorking() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(10))
        #expect(view(at: mon(10, 1)).mode == .working)
        #expect(view(at: mon(10, 1)).elapsedSeconds == minute)
    }

    @Test mutating func eventsThatDoNotFitTheModeChangeNothing() {
        let before = state
        send(.startBreak(seconds: nil), at: mon(9))
        send(.resumeWork(deliverableID: nil), at: mon(9))
        send(.recordCheckpoint("x"), at: mon(9))
        #expect(state == before)
        #expect(lastEffects == [])
        send(.startWork(deliverableID: nil), at: mon(9))
        let working = state
        send(.startWork(deliverableID: nil), at: mon(9, 30))
        #expect(state == working)
    }

    @Test mutating func resetClearsTheSessionButKeepsTheRecord() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: 60), at: mon(10))
        send(.resumeWork(deliverableID: report), at: mon(10, 1))
        send(.resetSession, at: mon(10, 31))
        let v = view(at: mon(10, 31))
        #expect(v.mode == .idle)
        #expect(v.bankSeconds == 0)
        #expect(v.activeDeliverables[0].investedSeconds == 90 * minute)
        #expect(v.todayWorkSeconds == 90 * minute)
        #expect(state.ratioDenominator == 3)
    }

    @Test mutating func resetDuringABreakCancelsTheAlarm() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resetSession, at: mon(10, 5))
        #expect(lastEffects.contains(.cancelAlarm))
        #expect(view(at: mon(10, 5)).todayBreakSeconds == 5 * minute)
    }

    // MARK: Break bank and ratio (stories 13-24)

    @Test mutating func defaultRatioIsOneThird() {
        #expect(view(at: mon(9)).ratioDenominator == 3)
    }

    @Test(arguments: zip([2, 3, 4, 5, 6], [30.0, 20.0, 15.0, 12.0, 10.0]))
    mutating func anHourOfWorkEarnsBreakAtEachRatio(denominator: Int, expectedMinutes: Double) {
        send(.setRatio(denominator: denominator), at: mon(8))
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(near(view(at: mon(10)).bankSeconds, expectedMinutes * minute))
    }

    @Test mutating func ratiosOutsideTheListAreRefused() {
        send(.setRatio(denominator: 1), at: mon(9))
        send(.setRatio(denominator: 7), at: mon(9))
        #expect(state.ratioDenominator == 3)
    }

    @Test mutating func bankGrowsLiveWhileWorking() {
        send(.startWork(deliverableID: nil), at: mon(9))
        #expect(near(view(at: mon(9, 30)).bankSeconds, 10 * minute))
    }

    @Test mutating func fullBreakUsesTheWholeBank() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        #expect(near(view(at: mon(9, 45)).breakRemainingSeconds!, 15 * minute))
        send(.resumeWork(deliverableID: nil), at: mon(10))
        #expect(near(view(at: mon(10)).bankSeconds, 0))
    }

    @Test mutating func endingABreakEarlyKeepsTheRest() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(9, 55))
        #expect(near(view(at: mon(9, 55)).bankSeconds, 5 * minute))
    }

    @Test mutating func savedBreakTimeAddsToTheNextBreak() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(9, 55))
        send(.startBreak(seconds: nil), at: mon(10, 25))
        #expect(near(view(at: mon(10, 25)).breakRemainingSeconds!, 15 * minute))
    }

    @Test mutating func partialBreakCountsDownTheChosenLength() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: 3 * minute), at: mon(10))
        #expect(near(view(at: mon(10)).breakRemainingSeconds!, 3 * minute))
        #expect(lastEffects.first == .scheduleAlarm(at: mon(10, 3)))
    }

    @Test mutating func partialBreakKeepsTheRestBanked() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: 3 * minute), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 3))
        #expect(near(view(at: mon(10, 3)).bankSeconds, 17 * minute))
    }

    @Test mutating func partialBreakCannotExceedTheBank() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: 50 * minute), at: mon(9, 30))
        #expect(near(view(at: mon(9, 30)).breakRemainingSeconds!, 10 * minute))
    }

    @Test mutating func partialBreakOptionsAreOnlyThoseTheBankCovers() {
        send(.startWork(deliverableID: nil), at: mon(9))
        #expect(view(at: mon(9, 5)).partialBreakOptions == [])
        #expect(view(at: mon(9, 12)).partialBreakOptions == [180])
        #expect(view(at: mon(9, 45)).partialBreakOptions == [180, 300, 600])
    }

    @Test mutating func ratioChangeMidStintAppliesOnlyToLaterWork() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.setRatio(denominator: 6), at: mon(9, 30))
        // 30 min at 1/3 = 10 min, then 30 min at 1/6 = 5 min.
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(near(view(at: mon(10)).bankSeconds, 15 * minute))
    }

    @Test mutating func ratioChangeDoesNotAlterTimeAlreadyBanked() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.setRatio(denominator: 6), at: mon(10))
        #expect(near(view(at: mon(10)).bankSeconds, 20 * minute))
    }

    // MARK: End of break (stories 25-30)

    @Test mutating func alarmIsScheduledForTheEndOfTheBreak() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        #expect(lastEffects.contains(.scheduleAlarm(at: mon(10))))
    }

    @Test mutating func alarmIsCancelledWhenWorkResumes() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(9, 50))
        #expect(lastEffects.contains(.cancelAlarm))
    }

    @Test mutating func overrunIsShownInNeutralWords() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        let v = view(at: mon(10, 2, 5))
        #expect(near(v.breakRemainingSeconds!, -(2 * minute + 5)))
        #expect(v.menuTitle == "Break · 2:05 past")
    }

    @Test mutating func overrunLeavesTheBankAtZeroWithNoDebt() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        #expect(view(at: mon(10, 30)).bankSeconds == 0)
        send(.resumeWork(deliverableID: nil), at: mon(10, 30))
        #expect(view(at: mon(10, 30)).bankSeconds == 0)
        // The next stint earns from zero, not from below it.
        send(.startBreak(seconds: nil), at: mon(11))
        #expect(near(view(at: mon(11)).bankSeconds, 10 * minute))
    }

    @Test mutating func overrunIsRecordedAsBreakTime() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(10, 30))
        #expect(near(view(at: mon(10, 30)).todayBreakSeconds, 45 * minute))
    }

    @Test mutating func alarmIsRearmedAfterARestartDuringABreak() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.launch, at: mon(9, 50))
        #expect(lastEffects == [.scheduleAlarm(at: mon(10))])
    }

    @Test mutating func alarmDoesNotFireTwice() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.alarmFired, at: mon(10))
        send(.launch, at: mon(10, 5))
        #expect(lastEffects == [])
    }

    // MARK: Deliverables and hours invested (stories 31-36, 43-46)

    @Test mutating func aDeliverableNeedsOnlyAName() {
        addReport()
        let v = view(at: mon(9))
        #expect(v.activeDeliverables.map(\.name) == ["Report"])
        #expect(v.activeDeliverables[0].investedSeconds == 0)
    }

    @Test mutating func deliverableWithoutANameIsRefused() {
        send(.addDeliverable(id: report, name: "   "), at: mon(8))
        #expect(view(at: mon(9)).activeDeliverables == [])
    }

    @Test mutating func workIsAttributedToTheChosenDeliverable() {
        addReport()
        send(.addDeliverable(id: slides, name: "Slides"), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resumeWork(deliverableID: slides), at: mon(10, 20))
        let v = view(at: mon(10, 50))
        #expect(v.activeDeliverables[0].investedSeconds == hour)
        #expect(v.activeDeliverables[1].investedSeconds == 30 * minute)
        #expect(v.currentDeliverableName == "Slides")
    }

    @Test mutating func lastUsedDeliverableIsPreselected() {
        addReport()
        send(.addDeliverable(id: slides, name: "Slides"), at: mon(8))
        #expect(view(at: mon(9)).preselectedDeliverableID == nil)
        send(.startWork(deliverableID: slides), at: mon(9))
        send(.resetSession, at: mon(9, 30))
        #expect(view(at: mon(9, 30)).preselectedDeliverableID == slides)
    }

    @Test mutating func stintWithoutADeliverableIsTimed() {
        addReport()
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        let v = view(at: mon(10))
        #expect(v.todayWorkSeconds == hour)
        #expect(v.activeDeliverables[0].investedSeconds == 0)
    }

    @Test mutating func renamingADeliverableKeepsItsHours() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.renameDeliverable(id: report, name: "Board report"), at: mon(10))
        let d = view(at: mon(10)).activeDeliverables[0]
        #expect(d.name == "Board report")
        #expect(d.investedSeconds == hour)
    }

    @Test mutating func completedDeliverableLeavesTheActiveListAndKeepsItsHours() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(11))
        send(.completeDeliverable(id: report), at: mon(11))
        let v = view(at: mon(11))
        #expect(v.activeDeliverables == [])
        #expect(v.doneDeliverables.map(\.name) == ["Report"])
        #expect(v.doneDeliverables[0].investedSeconds == 2 * hour)
        #expect(v.preselectedDeliverableID == nil)
    }

    // MARK: Checkpoints (stories 47-51)

    @Test mutating func startingABreakAsksForACheckpoint() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(lastEffects.contains(.askCheckpoint))
        #expect(view(at: mon(10)).awaitingCheckpoint)
    }

    @Test mutating func checkpointCanBeSkipped() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 10))
        #expect(view(at: mon(10, 10)).mode == .working)
        #expect(state.checkpoints == [])
        #expect(view(at: mon(10, 10)).returnInfo == nil)
    }

    @Test mutating func checkpointIsShownOnReturn() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordCheckpoint("Intro done,\nsection 2 half drafted "), at: mon(10, 1))
        #expect(!view(at: mon(10, 1)).awaitingCheckpoint)
        send(.resumeWork(deliverableID: report), at: mon(10, 15))
        let expected = ReturnInfo(checkpoint: "Intro done, section 2 half drafted", handoff: nil)
        #expect(lastEffects.contains(.showReturn(expected)))
        #expect(view(at: mon(10, 15)).returnInfo == expected)
    }

    @Test mutating func checkpointsFormALogPerDeliverable() {
        addReport()
        send(.addDeliverable(id: slides, name: "Slides"), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordCheckpoint("Intro done"), at: mon(10))
        send(.resumeWork(deliverableID: slides), at: mon(10, 10))
        send(.startBreak(seconds: nil), at: mon(11))
        send(.recordCheckpoint("Outline agreed"), at: mon(11))
        send(.resumeWork(deliverableID: report), at: mon(11, 10))
        send(.startBreak(seconds: nil), at: mon(12))
        send(.recordCheckpoint("Section 2 drafted"), at: mon(12))

        let v = view(at: mon(12))
        #expect(v.activeDeliverables[0].checkpoints.map(\.text) == ["Intro done", "Section 2 drafted"])
        #expect(v.activeDeliverables[1].checkpoints.map(\.text) == ["Outline agreed"])
        #expect(engine.checkpointLog(state, deliverableID: report) == "2026-11-09 10:00  Intro done\n2026-11-09 12:00  Section 2 drafted")
    }

    @Test mutating func aSecondCheckpointInTheSameBreakReplacesTheFirst() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordCheckpoint("First try"), at: mon(10))
        send(.recordCheckpoint("Better wording"), at: mon(10, 1))
        #expect(state.checkpoints.map(\.text) == ["Better wording"])
    }

    @Test mutating func startingTheDayShowsTheLastCheckpointOfThatDeliverable() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(15))
        send(.startBreak(seconds: nil), at: mon(16))
        send(.recordCheckpoint("Tables still missing"), at: mon(16))
        send(.resetSession, at: mon(16, 30))
        send(.startWork(deliverableID: report), at: mon(9, day: 10))
        #expect(view(at: mon(9, day: 10)).returnInfo?.checkpoint == "Tables still missing")
    }

    // MARK: Hand-off (stories 52-56)

    @Test mutating func startingABreakAsksForAHandoff() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(lastEffects.contains(.askHandoff))
        #expect(view(at: mon(10)).awaitingHandoff)
    }

    @Test mutating func handoffNoteIsShownOnReturn() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordHandoff("Claude: check the figures in section 3"), at: mon(10))
        #expect(!view(at: mon(10)).awaitingHandoff)
        send(.resumeWork(deliverableID: nil), at: mon(10, 15))
        #expect(view(at: mon(10, 15)).returnInfo?.handoff == "Claude: check the figures in section 3")
    }

    @Test mutating func handoffCanBeSkipped() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 15))
        #expect(view(at: mon(10, 15)).mode == .working)
        #expect(view(at: mon(10, 15)).returnInfo == nil)
    }

    @Test mutating func handoffPromptCanBeTurnedOff() {
        send(.setHandoffPrompt(false), at: mon(8))
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(!lastEffects.contains(.askHandoff))
        #expect(!view(at: mon(10)).awaitingHandoff)
        #expect(lastEffects.contains(.askCheckpoint))
    }

    @Test mutating func returnInfoIsClearedWhenTheNextBreakStarts() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordHandoff("Something"), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 15))
        send(.startBreak(seconds: nil), at: mon(11))
        #expect(view(at: mon(11)).returnInfo == nil)
    }

    // MARK: Persistence and the day (stories 10-11, 24, 57-60)

    @Test mutating func everyChangeAsksForASave() {
        send(.startWork(deliverableID: nil), at: mon(9))
        #expect(lastEffects.contains(.save))
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(lastEffects.contains(.save))
        send(.setRatio(denominator: 4), at: mon(10))
        #expect(lastEffects.contains(.save))
    }

    @Test mutating func aRunningStintContinuesAfterARestart() throws {
        addReport()
        send(.setRatio(denominator: 4), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        let data = try Persistence.encode(state)

        state = try Persistence.decode(data)
        send(.launch, at: mon(9, 40))
        let v = view(at: mon(9, 40))
        #expect(v.mode == .working)
        #expect(v.elapsedSeconds == 40 * minute)
        #expect(v.menuTitle == "Report · 40m")
        #expect(v.ratioDenominator == 4)
        send(.startBreak(seconds: nil), at: mon(10))
        #expect(near(view(at: mon(10)).bankSeconds, 15 * minute))
    }

    @Test mutating func aRunningBreakContinuesAfterARestart() throws {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.recordCheckpoint("Half way"), at: mon(9, 46))
        let data = try Persistence.encode(state)

        state = try Persistence.decode(data)
        send(.launch, at: mon(9, 52))
        #expect(lastEffects == [.scheduleAlarm(at: mon(10))])
        #expect(near(view(at: mon(9, 52)).breakRemainingSeconds!, 8 * minute))
        send(.resumeWork(deliverableID: nil), at: mon(9, 55))
        #expect(near(view(at: mon(9, 55)).bankSeconds, 5 * minute))
        #expect(view(at: mon(9, 55)).returnInfo?.checkpoint == "Half way")
    }

    @Test mutating func savedStateRoundTripsExactly() throws {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: 5 * minute), at: mon(9, 47, 13))
        send(.recordHandoff("Something"), at: mon(9, 48))
        #expect(try Persistence.decode(Persistence.encode(state)) == state)
    }

    @Test mutating func stateFromANewerVersionIsRefused() throws {
        state.version = EngineState.currentVersion + 1
        let data = try Persistence.encode(state)
        #expect(throws: (any Error).self) { try Persistence.decode(data) }
    }

    @Test mutating func todayTotalsCountOnlyToday() {
        send(.startWork(deliverableID: nil), at: mon(15))
        send(.startBreak(seconds: nil), at: mon(16))
        send(.resumeWork(deliverableID: nil), at: mon(16, 20))
        send(.resetSession, at: mon(17))
        // Tuesday.
        send(.startWork(deliverableID: nil), at: mon(9, day: 10))
        let v = view(at: mon(9, 30, day: 10))
        #expect(v.todayWorkSeconds == 30 * minute)
        #expect(v.todayBreakSeconds == 0)
        let monday = view(at: mon(17))
        #expect(monday.todayWorkSeconds == 100 * minute)
        #expect(monday.todayBreakSeconds == 20 * minute)
    }

    @Test mutating func launchAtLoginSettingIsPassedToTheSystem() {
        send(.setLaunchAtLogin(true), at: mon(9))
        #expect(lastEffects.contains(.setLaunchAtLogin(true)))
        #expect(state.settings.launchAtLogin)
        send(.setLaunchAtLogin(false), at: mon(9))
        #expect(lastEffects.contains(.setLaunchAtLogin(false)))
    }

    // MARK: The article's own examples

    @Test mutating func articleExamples() {
        // "After 15 minutes of dealing with emails, you could stop for up to 5 minutes."
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 15))
        #expect(near(view(at: mon(9, 15)).bankSeconds, 5 * minute))
        send(.resumeWork(deliverableID: nil), at: mon(9, 20))
        // "After an hour-long meeting, you can take a good 20-minute break."
        send(.startBreak(seconds: nil), at: mon(10, 20))
        #expect(near(view(at: mon(10, 20)).bankSeconds, 20 * minute))
        // "If you end a break 5 minutes early, add 5 minutes to your next break."
        send(.resumeWork(deliverableID: nil), at: mon(10, 35))
        send(.startBreak(seconds: nil), at: mon(11, 20))
        #expect(near(view(at: mon(11, 20)).bankSeconds, 20 * minute))
    }

    // MARK: Worst-case data

    @Test mutating func aLongDeliverableNameIsCutShortInTheMenuBar() {
        let name = "Aleksandra Wiśniewska-Kowalczyk: Q3 board report for Northwind Industries Holdings"
        send(.addDeliverable(id: report, name: name), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        let v = view(at: mon(9, 34))
        #expect(v.menuTitle == "Aleksandra Wiśniewska-K… · 34m")
        // The panel still has the whole name.
        #expect(v.currentDeliverableName == name)
    }

    @Test mutating func aNameAtTheMenuBarLimitIsShownWhole() {
        let name = String(repeating: "x", count: Engine.menuNameLimit)
        send(.addDeliverable(id: report, name: name), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        #expect(view(at: mon(9, 1)).menuTitle == "\(name) · 1m")
    }

    @Test mutating func aOneLetterNameWorks() {
        send(.addDeliverable(id: report, name: "X"), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        #expect(view(at: mon(9, 1)).menuTitle == "X · 1m")
    }

    @Test mutating func namesAndNotesHaveALengthLimit() {
        let long = String(repeating: "word ", count: 100)
        send(.addDeliverable(id: report, name: long), at: mon(8))
        #expect(view(at: mon(8)).activeDeliverables[0].name.count <= Engine.nameLimit)
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordCheckpoint(long), at: mon(10))
        send(.recordHandoff(long), at: mon(10))
        #expect(state.checkpoints[0].text.count <= Engine.noteLimit)
        #expect((state.currentBreak?.handoff?.count ?? 0) <= Engine.noteLimit)
    }

    @Test mutating func aStintLeftRunningOvernightStillReadsCorrectly() {
        send(.startWork(deliverableID: nil), at: mon(9))
        let v = view(at: mon(11, 14, 9, day: 10))
        #expect(v.menuTitle == "Working · 26h 14m")
        #expect(Format.clock(v.elapsedSeconds) == "26:14:09")
    }

    // MARK: Saved state from the first version

    @Test mutating func stateSavedByTheFirstVersionIsMigrated() throws {
        let start = mon(9).timeIntervalSinceReferenceDate
        let json = """
        {
          "version": 1, "mode": "working", "ratioDenominator": 4, "bankSeconds": 300,
          "stint": { "start": \(start), "earnedSeconds": 0, "earnAnchor": \(start) },
          "deliverables": [], "workLog": [], "breakLog": [], "checkpoints": [],
          "workingHours": [
            {"enabled": false, "startMinute": 540, "endMinute": 1020},
            {"enabled": true, "startMinute": 540, "endMinute": 1020},
            {"enabled": true, "startMinute": 540, "endMinute": 1020},
            {"enabled": true, "startMinute": 540, "endMinute": 1020},
            {"enabled": true, "startMinute": 540, "endMinute": 1020},
            {"enabled": true, "startMinute": 540, "endMinute": 1020},
            {"enabled": false, "startMinute": 540, "endMinute": 1020}
          ],
          "settings": { "handoffPrompt": false, "launchAtLogin": true }
        }
        """
        state = try Persistence.decode(Data(json.utf8))
        #expect(state.version == EngineState.currentVersion)
        let v = view(at: mon(9, 40))
        #expect(v.mode == .working)
        #expect(v.elapsedSeconds == 40 * minute)
        #expect(v.ratioDenominator == 4)
        // 5 minutes banked plus 40 minutes at 1/4.
        #expect(near(v.bankSeconds, 15 * minute))
        #expect(!state.settings.handoffPrompt)
    }
}
