import XCTest
@testable import DontSmoke

final class RescueSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testDevelopmentAccessUsesFiveMinutesWithoutEntitlementRestriction() {
        XCTAssertEqual(RescueAccess.free.sessionDuration, 300)
        XCTAssertEqual(RescueAccess.premium.sessionDuration, 300)
        XCTAssertEqual(DefaultRescueEntitlements().rescueAccess, .free)
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

    func testALittleContinuesSameSessionAfterTwoMinutes() {
        var session = RescueSession(access: .free, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: true)
        XCTAssertEqual(session.phase, .continuedBreathing)
        XCTAssertEqual(session.startDate, start)
        XCTAssertEqual(session.elapsed, 120)
        session.update(now: start.addingTimeInterval(299))
        XCTAssertEqual(session.phase, .continuedBreathing)
        session.update(now: start.addingTimeInterval(300))
        XCTAssertEqual(session.phase, .completed)
    }

    func testNotYetShowsMyWhyBeforeContinuing() {
        var session = RescueSession(access: .premium, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: false)
        XCTAssertEqual(session.phase, .myWhy)
        session.update(now: start.addingTimeInterval(145))
        XCTAssertEqual(session.phase, .myWhy)
        XCTAssertEqual(session.elapsed, 145)
        session.continueAfterWhy()
        XCTAssertEqual(session.phase, .continuedBreathing)
        XCTAssertEqual(session.startDate, start)
        XCTAssertEqual(session.elapsed, 145)
        session.update(now: start.addingTimeInterval(300))
        XCTAssertEqual(session.phase, .completed)
    }

    func testPremiumCompletionAndExtensionFlow() {
        var session = RescueSession(access: .premium, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: true)
        session.update(now: start.addingTimeInterval(269))
        XCTAssertEqual(session.phase, .continuedBreathing)
        session.update(now: start.addingTimeInterval(270))
        XCTAssertEqual(session.phase, .continuedBreathing)
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
        XCTAssertEqual(Set(RescueAccess.free.availableSoundscapes), Set(RescueSoundscape.allCases))
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

    func testDevelopmentAccessAllowsAllSoundsAndExtension() {
        var session = RescueSession(access: .free, startDate: start)
        session.select(.soundscape(.forest))
        XCTAssertEqual(session.selectedSound, .forest)
        XCTAssertEqual(session.soundSelection, .soundscape(.forest))
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: true)
        session.update(now: start.addingTimeInterval(300))
        session.startExtension(at: start.addingTimeInterval(300))
        XCTAssertEqual(session.phase, .extended)
        XCTAssertEqual(session.extensionStartDate, start.addingTimeInterval(300))
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
        XCTAssertNotEqual(session.selectedSound, .silence)
        XCTAssertNotNil(session.selectedSound)
        session.toggleMute()
        XCTAssertTrue(session.isMuted)
        XCTAssertEqual(session.startDate, start)
    }

    func testCompletionOccursEvenWhileMyWhyIsOpen() {
        var session = RescueSession(access: .free, startDate: start)
        session.update(now: start.addingTimeInterval(120))
        session.answerCheckIn(isEasier: false)
        session.update(now: start.addingTimeInterval(300))
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.elapsed, 300)
    }

    func testNewSessionRandomUsesAllSoundsAndExcludesPrevious() {
        let session = RescueSession(access: .free, startDate: start, lastRandomSound: .rain, randomIndex: { $0.lowerBound })
        XCTAssertEqual(session.selectedSound, .ocean)
        let last = RescueSession(access: .free, startDate: start, randomIndex: { $0.upperBound - 1 })
        XCTAssertEqual(last.selectedSound, .warmAmbient)
    }

    func testEveryAmbientSoundMapsToItsOwnBundledRecording() throws {
        let expected: [RescueSoundscape: String] = [
            .rain: "rain.mp3", .ocean: "ocean.mp3", .forest: "forest.mp3",
            .breeze: "breeze.mp3", .night: "night.mp3", .warmAmbient: "warmAmbient.mp3"
        ]
        XCTAssertEqual(expected.count, RescueSoundscape.allCases.count - 1)
        for (sound, filename) in expected {
            XCTAssertEqual(sound.resourceFilename, filename)
            let url = try XCTUnwrap(sound.resourceURL(), "Missing bundled asset: \(filename)")
            XCTAssertEqual(url.lastPathComponent, filename)
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 1_024)
        }
        XCTAssertNil(RescueSoundscape.silence.resourceFilename)
        XCTAssertNil(RescueSoundscape.silence.resourceURL())
    }
}
