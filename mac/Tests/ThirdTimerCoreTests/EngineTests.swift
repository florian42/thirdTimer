import XCTest
@testable import ThirdTimerCore

/// Every test drives the session engine through its one entry point:
/// events with times go in, and the state the user would see is checked.
final class EngineTests: XCTestCase {
    var engine: Engine!
    var state: EngineState!
    var lastEffects: [Effect] = []

    let report = UUID()
    let slides = UUID()

    override func setUp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        engine = Engine(calendar: calendar)
        state = EngineState()
        lastEffects = []
    }

    /// Monday 9 November 2026, at the given time, UTC.
    func mon(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 9) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return engine.calendar.date(from: c)!
    }

    func send(_ event: Event, at time: Date) {
        let (next, effects) = engine.reduce(state, event, now: time)
        state = next
        lastEffects = effects
    }

    func view(at time: Date) -> Snapshot {
        engine.snapshot(state, now: time)
    }

    func addReport(deadline: Date? = nil) {
        send(.addDeliverable(id: report, name: "Report", deadline: deadline ?? mon(17, day: 13)), at: mon(8))
    }

    let minute = 60.0
    let hour = 3600.0

    // MARK: Menu bar and basic timing (stories 2-4, 6-8, 12)

    func testIdleIsShownAsIdle() {
        XCTAssertEqual(view(at: mon(9)).mode, .idle)
        XCTAssertEqual(view(at: mon(9)).menuTitle, "⏸ Idle")
    }

    func testWorkingShowsDeliverableAndElapsedTime() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        let v = view(at: mon(9, 34))
        XCTAssertEqual(v.mode, .working)
        XCTAssertEqual(v.menuTitle, "🟢 Report · 34m")
        XCTAssertEqual(v.elapsedSeconds, 34 * minute)
    }

    func testLongStintShowsHoursAndMinutes() {
        send(.startWork(deliverableID: nil), at: mon(9))
        XCTAssertEqual(view(at: mon(10, 5)).menuTitle, "🟢 Working · 1h 05m")
    }

    func testBreakShowsCountdown() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        let v = view(at: mon(9, 53, 48))
        XCTAssertEqual(v.mode, .breaking)
        XCTAssertEqual(v.breakRemainingSeconds!, 6 * minute + 12, accuracy: 0.001)
        XCTAssertEqual(v.menuTitle, "🔵 Break · 6:12 left")
    }

    func testResumeReturnsToWorking() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(10))
        XCTAssertEqual(view(at: mon(10, 1)).mode, .working)
        XCTAssertEqual(view(at: mon(10, 1)).elapsedSeconds, minute)
    }

    func testEventsThatDoNotFitTheModeChangeNothing() {
        let before = state
        send(.startBreak(seconds: nil), at: mon(9))
        send(.resumeWork(deliverableID: nil), at: mon(9))
        send(.recordCheckpoint("x"), at: mon(9))
        XCTAssertEqual(state, before)
        XCTAssertEqual(lastEffects, [])
        send(.startWork(deliverableID: nil), at: mon(9))
        let working = state
        send(.startWork(deliverableID: nil), at: mon(9, 30))
        XCTAssertEqual(state, working)
    }

    func testResetClearsTheSessionButKeepsTheRecord() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: 60), at: mon(10))
        send(.resumeWork(deliverableID: report), at: mon(10, 1))
        send(.resetSession, at: mon(10, 31))
        let v = view(at: mon(10, 31))
        XCTAssertEqual(v.mode, .idle)
        XCTAssertEqual(v.bankSeconds, 0)
        XCTAssertEqual(v.activeDeliverables[0].investedSeconds, 90 * minute)
        XCTAssertEqual(v.todayWorkSeconds, 90 * minute)
        XCTAssertEqual(state.ratioDenominator, 3)
    }

    func testResetDuringABreakCancelsTheAlarm() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resetSession, at: mon(10, 5))
        XCTAssertTrue(lastEffects.contains(.cancelAlarm))
        XCTAssertEqual(view(at: mon(10, 5)).todayBreakSeconds, 5 * minute)
    }

    // MARK: Break bank and ratio (stories 13-24)

    func testDefaultRatioIsOneThird() {
        XCTAssertEqual(view(at: mon(9)).ratioDenominator, 3)
    }

    func testWorkEarnsBreakAtEachRatio() {
        for (denominator, expectedMinutes) in [(2, 30.0), (3, 20.0), (4, 15.0), (5, 12.0), (6, 10.0)] {
            setUp()
            send(.setRatio(denominator: denominator), at: mon(8))
            send(.startWork(deliverableID: nil), at: mon(9))
            send(.startBreak(seconds: nil), at: mon(10))
            XCTAssertEqual(view(at: mon(10)).bankSeconds, expectedMinutes * minute, accuracy: 0.001,
                           "ratio 1/\(denominator)")
        }
    }

    func testRatiosOutsideTheListAreRefused() {
        send(.setRatio(denominator: 1), at: mon(9))
        send(.setRatio(denominator: 7), at: mon(9))
        XCTAssertEqual(state.ratioDenominator, 3)
    }

    func testBankGrowsLiveWhileWorking() {
        send(.startWork(deliverableID: nil), at: mon(9))
        XCTAssertEqual(view(at: mon(9, 30)).bankSeconds, 10 * minute, accuracy: 0.001)
    }

    func testFullBreakUsesTheWholeBank() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        XCTAssertEqual(view(at: mon(9, 45)).breakRemainingSeconds!, 15 * minute, accuracy: 0.001)
        send(.resumeWork(deliverableID: nil), at: mon(10))
        XCTAssertEqual(view(at: mon(10)).bankSeconds, 0, accuracy: 0.001)
    }

    func testEndingABreakEarlyKeepsTheRest() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(9, 55))
        XCTAssertEqual(view(at: mon(9, 55)).bankSeconds, 5 * minute, accuracy: 0.001)
    }

    func testSavedBreakTimeAddsToTheNextBreak() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(9, 55))
        send(.startBreak(seconds: nil), at: mon(10, 25))
        XCTAssertEqual(view(at: mon(10, 25)).breakRemainingSeconds!, 15 * minute, accuracy: 0.001)
    }

    func testPartialBreakCountsDownTheChosenLength() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: 3 * minute), at: mon(10))
        XCTAssertEqual(view(at: mon(10)).breakRemainingSeconds!, 3 * minute, accuracy: 0.001)
        XCTAssertEqual(lastEffects.first, .scheduleAlarm(at: mon(10, 3)))
    }

    func testPartialBreakKeepsTheRestBanked() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: 3 * minute), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 3))
        XCTAssertEqual(view(at: mon(10, 3)).bankSeconds, 17 * minute, accuracy: 0.001)
    }

    func testPartialBreakCannotExceedTheBank() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: 50 * minute), at: mon(9, 30))
        XCTAssertEqual(view(at: mon(9, 30)).breakRemainingSeconds!, 10 * minute, accuracy: 0.001)
    }

    func testPartialBreakOptionsAreOnlyThoseTheBankCovers() {
        send(.startWork(deliverableID: nil), at: mon(9))
        XCTAssertEqual(view(at: mon(9, 5)).partialBreakOptions, [])
        XCTAssertEqual(view(at: mon(9, 12)).partialBreakOptions, [180])
        XCTAssertEqual(view(at: mon(9, 45)).partialBreakOptions, [180, 300, 600])
    }

    func testRatioChangeMidStintAppliesOnlyToLaterWork() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.setRatio(denominator: 6), at: mon(9, 30))
        // 30 min at 1/3 = 10 min, then 30 min at 1/6 = 5 min.
        send(.startBreak(seconds: nil), at: mon(10))
        XCTAssertEqual(view(at: mon(10)).bankSeconds, 15 * minute, accuracy: 0.001)
    }

    func testRatioChangeDoesNotAlterTimeAlreadyBanked() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.setRatio(denominator: 6), at: mon(10))
        XCTAssertEqual(view(at: mon(10)).bankSeconds, 20 * minute, accuracy: 0.001)
    }

    // MARK: End of break (stories 25-30)

    func testAlarmIsScheduledForTheEndOfTheBreak() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        XCTAssertTrue(lastEffects.contains(.scheduleAlarm(at: mon(10))))
    }

    func testAlarmIsCancelledWhenWorkResumes() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(9, 50))
        XCTAssertTrue(lastEffects.contains(.cancelAlarm))
    }

    func testOverrunIsShownInNeutralWords() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        let v = view(at: mon(10, 2, 5))
        XCTAssertEqual(v.breakRemainingSeconds!, -(2 * minute + 5), accuracy: 0.001)
        XCTAssertEqual(v.menuTitle, "🔵 Break · 2:05 past")
    }

    func testOverrunLeavesTheBankAtZeroWithNoDebt() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        XCTAssertEqual(view(at: mon(10, 30)).bankSeconds, 0)
        send(.resumeWork(deliverableID: nil), at: mon(10, 30))
        XCTAssertEqual(view(at: mon(10, 30)).bankSeconds, 0)
        // The next stint earns from zero, not from below it.
        send(.startBreak(seconds: nil), at: mon(11))
        XCTAssertEqual(view(at: mon(11)).bankSeconds, 10 * minute, accuracy: 0.001)
    }

    func testOverrunIsRecordedAsBreakTime() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.resumeWork(deliverableID: nil), at: mon(10, 30))
        XCTAssertEqual(view(at: mon(10, 30)).todayBreakSeconds, 45 * minute, accuracy: 0.001)
    }

    func testAlarmIsRearmedAfterARestartDuringABreak() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.launch, at: mon(9, 50))
        XCTAssertEqual(lastEffects, [.scheduleAlarm(at: mon(10))])
    }

    func testAlarmDoesNotFireTwice() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.alarmFired, at: mon(10))
        send(.launch, at: mon(10, 5))
        XCTAssertEqual(lastEffects, [])
    }

    // MARK: Deliverables and hours invested (stories 31-36, 43-46)

    func testDeliverableNeedsOnlyANameAndADeadline() {
        addReport()
        let v = view(at: mon(9))
        XCTAssertEqual(v.activeDeliverables.map(\.name), ["Report"])
        XCTAssertEqual(v.activeDeliverables[0].deadline, mon(17, day: 13))
        XCTAssertEqual(v.activeDeliverables[0].investedSeconds, 0)
    }

    func testDeliverableWithoutANameIsRefused() {
        send(.addDeliverable(id: report, name: "   ", deadline: mon(17)), at: mon(8))
        XCTAssertEqual(view(at: mon(9)).activeDeliverables, [])
    }

    func testWorkIsAttributedToTheChosenDeliverable() {
        addReport()
        send(.addDeliverable(id: slides, name: "Slides", deadline: mon(17, day: 12)), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resumeWork(deliverableID: slides), at: mon(10, 20))
        let v = view(at: mon(10, 50))
        XCTAssertEqual(v.activeDeliverables[0].investedSeconds, hour)
        XCTAssertEqual(v.activeDeliverables[1].investedSeconds, 30 * minute)
        XCTAssertEqual(v.currentDeliverableName, "Slides")
    }

    func testLastUsedDeliverableIsPreselected() {
        addReport()
        send(.addDeliverable(id: slides, name: "Slides", deadline: mon(17, day: 12)), at: mon(8))
        XCTAssertNil(view(at: mon(9)).preselectedDeliverableID)
        send(.startWork(deliverableID: slides), at: mon(9))
        send(.resetSession, at: mon(9, 30))
        XCTAssertEqual(view(at: mon(9, 30)).preselectedDeliverableID, slides)
    }

    func testStintWithoutADeliverableIsTimed() {
        addReport()
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        let v = view(at: mon(10))
        XCTAssertEqual(v.todayWorkSeconds, hour)
        XCTAssertEqual(v.activeDeliverables[0].investedSeconds, 0)
    }

    func testEditingADeliverable() {
        addReport()
        send(.editDeliverable(id: report, name: "Board report", deadline: mon(12, day: 12)), at: mon(9))
        let d = view(at: mon(9)).activeDeliverables[0]
        XCTAssertEqual(d.name, "Board report")
        XCTAssertEqual(d.deadline, mon(12, day: 12))
    }

    func testCompletedDeliverableLeavesTheActiveListAndKeepsItsHours() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(11))
        send(.completeDeliverable(id: report), at: mon(11))
        let v = view(at: mon(11))
        XCTAssertEqual(v.activeDeliverables, [])
        XCTAssertEqual(v.doneDeliverables.map(\.name), ["Report"])
        XCTAssertEqual(v.doneDeliverables[0].investedSeconds, 2 * hour)
        XCTAssertNil(v.preselectedDeliverableID)
    }

    // MARK: Runway (stories 37-42)

    func testRunwayIsWorkingHoursTimesTheWorkingShare() {
        // Monday 09:00 to Friday 17:00 at 8 hours a day is 40 working hours; 75% of it is work.
        addReport()
        XCTAssertEqual(view(at: mon(9)).activeDeliverables[0].runwaySeconds, 30 * hour, accuracy: 0.001)
    }

    func testRunwayIgnoresTimeOutsideWorkingHoursAndDaysOff() {
        // Deadline the following Monday 13:00: the weekend adds nothing.
        addReport(deadline: mon(13, day: 16))
        XCTAssertEqual(view(at: mon(9)).activeDeliverables[0].runwaySeconds, 33 * hour, accuracy: 0.001)
        // In the evening only the coming days count.
        XCTAssertEqual(view(at: mon(20)).activeDeliverables[0].runwaySeconds, 27 * hour, accuracy: 0.001)
    }

    func testAnHourOfWorkLowersRunwayByAnHour() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        XCTAssertEqual(view(at: mon(10)).activeDeliverables[0].runwaySeconds, 29 * hour, accuracy: 0.001)
    }

    func testAnEarnedBreakLeavesRunwayUnchanged() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        let atStart = view(at: mon(10)).activeDeliverables[0].runwaySeconds
        let midway = view(at: mon(10, 10)).activeDeliverables[0].runwaySeconds
        send(.resumeWork(deliverableID: report), at: mon(10, 20))
        let atEnd = view(at: mon(10, 20)).activeDeliverables[0].runwaySeconds
        XCTAssertEqual(atStart, 29 * hour, accuracy: 0.001)
        XCTAssertEqual(midway, atStart, accuracy: 0.001)
        XCTAssertEqual(atEnd, atStart, accuracy: 0.001)
    }

    func testAnOverrunDoesLowerRunway() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        // 20 earned minutes, then 40 more: those 40 minutes cost 30 minutes of work time.
        XCTAssertEqual(view(at: mon(11)).activeDeliverables[0].runwaySeconds, 28.5 * hour, accuracy: 0.001)
    }

    func testATighterRatioRaisesRunway() {
        addReport()
        send(.setRatio(denominator: 6), at: mon(9))
        XCTAssertEqual(view(at: mon(9)).activeDeliverables[0].runwaySeconds, 40 * hour * 6 / 7, accuracy: 0.001)
    }

    func testRunwayFollowsADeadlineChange() {
        addReport()
        send(.editDeliverable(id: report, name: "Report", deadline: mon(17, day: 11)), at: mon(9))
        XCTAssertEqual(view(at: mon(9)).activeDeliverables[0].runwaySeconds, 18 * hour, accuracy: 0.001)
    }

    func testRunwayFollowsWorkingHours() {
        addReport()
        var hours = EngineState.defaultWorkingHours
        hours[5] = DayHours(enabled: false, startMinute: 0, endMinute: 0)      // Friday off
        hours[1] = DayHours(enabled: true, startMinute: 8 * 60, endMinute: 18 * 60) // Monday 08-18
        send(.setWorkingHours(hours), at: mon(8))
        // Monday 10h + Tue, Wed, Thu 8h each = 34h; 75% is 25.5h.
        XCTAssertEqual(view(at: mon(8)).activeDeliverables[0].runwaySeconds, 25.5 * hour, accuracy: 0.001)
    }

    func testRunwayIsZeroOnceTheDeadlineHasPassed() {
        addReport(deadline: mon(12))
        XCTAssertEqual(view(at: mon(13)).activeDeliverables[0].runwaySeconds, 0)
        send(.startWork(deliverableID: report), at: mon(13))
        XCTAssertEqual(view(at: mon(15)).activeDeliverables[0].runwaySeconds, 0)
    }

    // MARK: Checkpoints (stories 47-51)

    func testStartingABreakAsksForACheckpoint() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        XCTAssertTrue(lastEffects.contains(.askCheckpoint))
        XCTAssertTrue(view(at: mon(10)).awaitingCheckpoint)
    }

    func testCheckpointCanBeSkipped() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 10))
        XCTAssertEqual(view(at: mon(10, 10)).mode, .working)
        XCTAssertEqual(state.checkpoints, [])
        XCTAssertNil(view(at: mon(10, 10)).returnInfo)
    }

    func testCheckpointIsShownOnReturn() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordCheckpoint("Intro done,\nsection 2 half drafted "), at: mon(10, 1))
        XCTAssertFalse(view(at: mon(10, 1)).awaitingCheckpoint)
        send(.resumeWork(deliverableID: report), at: mon(10, 15))
        let expected = ReturnInfo(checkpoint: "Intro done, section 2 half drafted", handoff: nil)
        XCTAssertTrue(lastEffects.contains(.showReturn(expected)))
        XCTAssertEqual(view(at: mon(10, 15)).returnInfo, expected)
    }

    func testCheckpointsFormALogPerDeliverable() {
        addReport()
        send(.addDeliverable(id: slides, name: "Slides", deadline: mon(17, day: 12)), at: mon(8))
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
        XCTAssertEqual(v.activeDeliverables[0].checkpoints.map(\.text), ["Intro done", "Section 2 drafted"])
        XCTAssertEqual(v.activeDeliverables[1].checkpoints.map(\.text), ["Outline agreed"])
        XCTAssertEqual(
            engine.checkpointLog(state, deliverableID: report),
            "2026-11-09 10:00  Intro done\n2026-11-09 12:00  Section 2 drafted"
        )
    }

    func testASecondCheckpointInTheSameBreakReplacesTheFirst() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordCheckpoint("First try"), at: mon(10))
        send(.recordCheckpoint("Better wording"), at: mon(10, 1))
        XCTAssertEqual(state.checkpoints.map(\.text), ["Better wording"])
    }

    func testStartingTheDayShowsTheLastCheckpointOfThatDeliverable() {
        addReport()
        send(.startWork(deliverableID: report), at: mon(15))
        send(.startBreak(seconds: nil), at: mon(16))
        send(.recordCheckpoint("Tables still missing"), at: mon(16))
        send(.resetSession, at: mon(16, 30))
        send(.startWork(deliverableID: report), at: mon(9, day: 10))
        XCTAssertEqual(view(at: mon(9, day: 10)).returnInfo?.checkpoint, "Tables still missing")
    }

    // MARK: Hand-off (stories 52-56)

    func testStartingABreakAsksForAHandoff() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        XCTAssertTrue(lastEffects.contains(.askHandoff))
        XCTAssertTrue(view(at: mon(10)).awaitingHandoff)
    }

    func testHandoffNoteIsShownOnReturn() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordHandoff("Claude: check the figures in section 3"), at: mon(10))
        XCTAssertFalse(view(at: mon(10)).awaitingHandoff)
        send(.resumeWork(deliverableID: nil), at: mon(10, 15))
        XCTAssertEqual(view(at: mon(10, 15)).returnInfo?.handoff, "Claude: check the figures in section 3")
    }

    func testHandoffCanBeSkipped() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 15))
        XCTAssertEqual(view(at: mon(10, 15)).mode, .working)
        XCTAssertNil(view(at: mon(10, 15)).returnInfo)
    }

    func testHandoffPromptCanBeTurnedOff() {
        send(.setHandoffPrompt(false), at: mon(8))
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        XCTAssertFalse(lastEffects.contains(.askHandoff))
        XCTAssertFalse(view(at: mon(10)).awaitingHandoff)
        XCTAssertTrue(lastEffects.contains(.askCheckpoint))
    }

    func testReturnInfoIsClearedWhenTheNextBreakStarts() {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(10))
        send(.recordHandoff("Something"), at: mon(10))
        send(.resumeWork(deliverableID: nil), at: mon(10, 15))
        send(.startBreak(seconds: nil), at: mon(11))
        XCTAssertNil(view(at: mon(11)).returnInfo)
    }

    // MARK: Persistence and the day (stories 10-11, 24, 57-60)

    func testEveryChangeAsksForASave() {
        send(.startWork(deliverableID: nil), at: mon(9))
        XCTAssertTrue(lastEffects.contains(.save))
        send(.startBreak(seconds: nil), at: mon(10))
        XCTAssertTrue(lastEffects.contains(.save))
        send(.setRatio(denominator: 4), at: mon(10))
        XCTAssertTrue(lastEffects.contains(.save))
    }

    func testARunningStintContinuesAfterARestart() throws {
        addReport()
        send(.setRatio(denominator: 4), at: mon(8))
        send(.startWork(deliverableID: report), at: mon(9))
        let data = try Persistence.encode(state)

        state = try Persistence.decode(data)
        send(.launch, at: mon(9, 40))
        let v = view(at: mon(9, 40))
        XCTAssertEqual(v.mode, .working)
        XCTAssertEqual(v.elapsedSeconds, 40 * minute)
        XCTAssertEqual(v.menuTitle, "🟢 Report · 40m")
        XCTAssertEqual(v.ratioDenominator, 4)
        send(.startBreak(seconds: nil), at: mon(10))
        XCTAssertEqual(view(at: mon(10)).bankSeconds, 15 * minute, accuracy: 0.001)
    }

    func testARunningBreakContinuesAfterARestart() throws {
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 45))
        send(.recordCheckpoint("Half way"), at: mon(9, 46))
        let data = try Persistence.encode(state)

        state = try Persistence.decode(data)
        send(.launch, at: mon(9, 52))
        XCTAssertEqual(lastEffects, [.scheduleAlarm(at: mon(10))])
        XCTAssertEqual(view(at: mon(9, 52)).breakRemainingSeconds!, 8 * minute, accuracy: 0.001)
        send(.resumeWork(deliverableID: nil), at: mon(9, 55))
        XCTAssertEqual(view(at: mon(9, 55)).bankSeconds, 5 * minute, accuracy: 0.001)
        XCTAssertEqual(view(at: mon(9, 55)).returnInfo?.checkpoint, "Half way")
    }

    func testSavedStateRoundTripsExactly() throws {
        addReport()
        send(.startWork(deliverableID: report), at: mon(9))
        send(.startBreak(seconds: 5 * minute), at: mon(9, 47, 13))
        send(.recordHandoff("Something"), at: mon(9, 48))
        XCTAssertEqual(try Persistence.decode(Persistence.encode(state)), state)
    }

    func testStateFromANewerVersionIsRefused() throws {
        state.version = EngineState.currentVersion + 1
        let data = try Persistence.encode(state)
        XCTAssertThrowsError(try Persistence.decode(data))
    }

    func testTodayTotalsCountOnlyToday() {
        send(.startWork(deliverableID: nil), at: mon(15))
        send(.startBreak(seconds: nil), at: mon(16))
        send(.resumeWork(deliverableID: nil), at: mon(16, 20))
        send(.resetSession, at: mon(17))
        // Tuesday.
        send(.startWork(deliverableID: nil), at: mon(9, day: 10))
        let v = view(at: mon(9, 30, day: 10))
        XCTAssertEqual(v.todayWorkSeconds, 30 * minute)
        XCTAssertEqual(v.todayBreakSeconds, 0)
        let monday = view(at: mon(17))
        XCTAssertEqual(monday.todayWorkSeconds, 100 * minute)
        XCTAssertEqual(monday.todayBreakSeconds, 20 * minute)
    }

    func testLaunchAtLoginSettingIsPassedToTheSystem() {
        send(.setLaunchAtLogin(true), at: mon(9))
        XCTAssertTrue(lastEffects.contains(.setLaunchAtLogin(true)))
        XCTAssertTrue(state.settings.launchAtLogin)
        send(.setLaunchAtLogin(false), at: mon(9))
        XCTAssertTrue(lastEffects.contains(.setLaunchAtLogin(false)))
    }

    // MARK: The article's own examples

    func testArticleExamples() {
        // "After 15 minutes of dealing with emails, you could stop for up to 5 minutes."
        send(.startWork(deliverableID: nil), at: mon(9))
        send(.startBreak(seconds: nil), at: mon(9, 15))
        XCTAssertEqual(view(at: mon(9, 15)).bankSeconds, 5 * minute, accuracy: 0.001)
        send(.resumeWork(deliverableID: nil), at: mon(9, 20))
        // "After an hour-long meeting, you can take a good 20-minute break."
        send(.startBreak(seconds: nil), at: mon(10, 20))
        XCTAssertEqual(view(at: mon(10, 20)).bankSeconds, 20 * minute, accuracy: 0.001)
        // "If you end a break 5 minutes early, add 5 minutes to your next break."
        send(.resumeWork(deliverableID: nil), at: mon(10, 35))
        send(.startBreak(seconds: nil), at: mon(11, 20))
        XCTAssertEqual(view(at: mon(11, 20)).bankSeconds, 20 * minute, accuracy: 0.001)
    }
}
