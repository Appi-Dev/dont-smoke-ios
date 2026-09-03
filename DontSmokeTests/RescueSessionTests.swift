import XCTest
@testable import DontSmoke

final class RescueSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreeAndPremiumDurations() {
        XCTAssertEqual(RescueAccess.free.sessionDuration, 120)
        XCTAssertEqual(RescueAccess.premium.sessionDuration, 300)
    }

    func testGroundingBreathingAndCheckInTransitionsUseDates() {
        var session = RescueSession(access: .free, startDate: start)
        XCTAssertEqual(session.phase, .grounding)

        session.update(now: start.addingTimeInterval(20))
        XCTAssertEqual(session.phase, .breathing)

        session.update(now: start.addingTimeInterval(119))
        XCTAssertEqual(session.phase, .breathing)

        session.update(now: start.addingTimeInterval(120))
        XCTAssertEqual(session.phase, .checkIn)
        XCTAssertEqual(session.elapsed, 120)
    }

    func testFreeCheckInCompletesAfterTwoMinutes() {
        var session = RescueSession(access: .free, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: true)
        XCTAssertEqual(session.phase, .completed)
        XCTAssertFalse(session.canExtend)
    }

    func testNotYetShowsMyWhyBeforeContinuing() {
        var session = RescueSession(access: .premium, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: false)
        XCTAssertEqual(session.phase, .myWhy)
        session.continueAfterWhy()
        XCTAssertEqual(session.phase, .continuedBreathing)
    }

    func testPremiumCompletionAndExtensionFlow() {
        var session = RescueSession(access: .premium, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: true)
        session.update(now: start.addingTimeInterval(269))
        XCTAssertEqual(session.phase, .continuedBreathing)
        session.update(now: start.addingTimeInterval(270))
        XCTAssertEqual(session.phase, .settling)
        session.update(now: start.addingTimeInterval(300))
        XCTAssertEqual(session.phase, .completed)
        XCTAssertTrue(session.canExtend)

        let extensionStart = start.addingTimeInterval(300)
        session.startExtension(at: extensionStart)
        XCTAssertEqual(session.phase, .extended)
        XCTAssertFalse(session.canExtend)
        session.update(now: extensionStart.addingTimeInterval(299))
        XCTAssertEqual(session.phase, .extended)
        session.update(now: extensionStart.addingTimeInterval(300))
        XCTAssertEqual(session.phase, .completed)
    }

    func testRandomExcludesSilence() {
        let sound = RescueSoundSelector.randomSound(
            from: RescueSoundscape.allCases,
            excluding: nil,
            randomIndex: { $0.lowerBound }
        )
        XCTAssertNotEqual(sound, .silence)
    }

    func testRandomAvoidsImmediateRepeatWhenAlternativesExist() {
        let sound = RescueSoundSelector.randomSound(
            from: [.rain, .forest, .silence],
            excluding: .rain,
            randomIndex: { $0.lowerBound }
        )
        XCTAssertEqual(sound, .forest)
    }

    func testSoundAvailabilityMatchesAccessLevel() {
        XCTAssertEqual(Set(RescueAccess.free.availableSoundscapes), Set([.breeze, .silence]))
        XCTAssertEqual(Set(RescueAccess.premium.availableSoundscapes), Set(RescueSoundscape.allCases))
    }

    func testBreathingPatternIsFourTwoSix() {
        var session = RescueSession(access: .free, startDate: start)
        session.update(now: start.addingTimeInterval(20))
        XCTAssertEqual(session.breathingPhase, .inhale)
        session.update(now: start.addingTimeInterval(24))
        XCTAssertEqual(session.breathingPhase, .hold)
        session.update(now: start.addingTimeInterval(26))
        XCTAssertEqual(session.breathingPhase, .exhale)
    }

    func testBackgroundJumpKeepsElapsedTimeAndPendingCheckIn() {
        var session = RescueSession(access: .premium, startDate: start)
        session.update(now: start.addingTimeInterval(240))
        XCTAssertEqual(session.elapsed, 240)
        XCTAssertEqual(session.phase, .checkIn)
        session.answerCheckIn(isEasier: true)
        session.update(now: start.addingTimeInterval(301))
        XCTAssertEqual(session.phase, .completed)
    }

    func testFreeCannotExtendOrSelectPremiumAudio() {
        var session = RescueSession(access: .free, startDate: start)
        session.select(.soundscape(.forest))
        XCTAssertEqual(session.selectedSound, .breeze)
        XCTAssertEqual(session.soundSelection, .random)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: true)
        session.startExtension(at: start.addingTimeInterval(120))
        XCTAssertEqual(session.phase, .completed)
        XCTAssertNil(session.extensionStartDate)
    }

    func testSingleFreeSoundCanRepeatAndSilenceOnlyPoolIsEmpty() {
        XCTAssertEqual(RescueSoundSelector.randomSound(from: [.breeze, .silence], excluding: .breeze), .breeze)
        XCTAssertNil(RescueSoundSelector.randomSound(from: [.silence], excluding: nil))
    }

    func testMuteAndSilenceDoNotChangeSessionTiming() {
        var session = RescueSession(access: .free, startDate: start)
        session.select(.soundscape(.silence))
        XCTAssertTrue(session.isMuted)
        session.select(.random)
        XCTAssertFalse(session.isMuted)
        XCTAssertEqual(session.selectedSound, .breeze)
        session.toggleMute()
        XCTAssertTrue(session.isMuted)
        XCTAssertEqual(session.startDate, start)
    }
}
