import XCTest
@testable import DontSmoke

final class ProductWalkthroughTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ProductWalkthroughTests")!
        defaults.removePersistentDomain(forName: "ProductWalkthroughTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ProductWalkthroughTests")
        defaults = nil
        super.tearDown()
    }

    func testFirstCompletedOnboardingRoutesToWalkthrough() {
        XCTAssertTrue(ProductWalkthroughPreferences.shouldPresent(onboardingCompleted: true, hasSeen: false))
        XCTAssertFalse(ProductWalkthroughPreferences.shouldPresent(onboardingCompleted: false, hasSeen: false))
    }

    func testSeenWalkthroughRoutesDirectlyToToday() {
        XCTAssertFalse(ProductWalkthroughPreferences.shouldPresent(onboardingCompleted: true, hasSeen: true))
    }

    func testSkippingMarksWalkthroughAsSeen() {
        let state = ProductWalkthroughState(isReplay: false)
        state.finish(.skipped, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: ProductWalkthroughPreferences.seenKey))
    }

    func testStartingFromFinalPageMarksWalkthroughAsSeen() {
        let state = ProductWalkthroughState(page: .keepWhatYouGained, isReplay: false)
        XCTAssertTrue(state.isLastPage)
        state.finish(.started, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: ProductWalkthroughPreferences.seenKey))
    }

    func testReplayDoesNotChangeSeenFlagOrTourProgression() {
        defaults.set(false, forKey: ProductWalkthroughPreferences.seenKey)
        var state = ProductWalkthroughState(isReplay: true)
        state.next()
        XCTAssertEqual(state.page, .gains)
        state.finish(.started, defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: ProductWalkthroughPreferences.seenKey))
    }

    func testReplayDoesNotResetProfileData() {
        let quitDate = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = QuitProfile(
            quitDate: quitDate, cigarettesPerDay: 12, packPrice: 450, packSize: 20,
            currencyCode: "INR", primaryReason: .family, reasons: [.family],
            personalReasonText: "More time together", triggers: [.workStress], notificationPreference: .deferred
        )
        let replay = ProductWalkthroughState(isReplay: true)
        replay.finish(.started, defaults: defaults)
        XCTAssertEqual(profile.quitDate, quitDate)
        XCTAssertEqual(profile.cigarettesPerDay, 12)
        XCTAssertEqual(profile.packPrice, 450)
        XCTAssertEqual(profile.currencyCode, "INR")
        XCTAssertEqual(profile.personalReasonText, "More time together")
    }

    func testPageNavigationIsBounded() {
        var state = ProductWalkthroughState(isReplay: false)
        state.back()
        XCTAssertEqual(state.page, .progress)
        for _ in 0..<8 { state.next() }
        XCTAssertEqual(state.page, .keepWhatYouGained)
    }
}
