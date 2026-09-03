import XCTest
@testable import DontSmoke

final class QuitCalculationsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testSmokeFreeDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = calendar.date(byAdding: DateComponents(day: 3, hour: 14, minute: 26), to: start)!
        XCTAssertEqual(QuitCalculations.duration(since: start, now: end, calendar: calendar), .init(days: 3, hours: 14, minutes: 26))
    }

    func testCigarettesAvoided() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(QuitCalculations.cigarettesAvoided(since: start, now: start.addingTimeInterval(2.5 * 86_400), cigarettesPerDay: 10), 25)
    }

    func testMoneySavedUsesDecimalArithmetic() {
        XCTAssertEqual(QuitCalculations.moneySaved(cigarettesAvoided: 47, costPerCigarette: Decimal(20)), Decimal(940))
    }

    func testFutureDateProducesZeroProgress() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(QuitCalculations.cigarettesAvoided(since: now.addingTimeInterval(60), now: now, cigarettesPerDay: 10), 0)
    }
}
