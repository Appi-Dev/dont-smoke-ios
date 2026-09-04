import XCTest
@testable import DontSmoke

final class CravingReminderTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!; return calendar
    }()

    func testTriggerWithTimeSchedulesTenMinutesBefore() async {
        let center = FakeNotificationCenter(permission: .authorized)
        let scheduler = CravingReminderScheduler(center: center, calendar: calendar)
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let time = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 8, minute: 0))!
        await scheduler.synchronize([.init(id: id, trigger: .morningCoffee, cravingTime: time, enabled: true)])
        let requests = await center.added
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].cravingTime.hour, 8)
        XCTAssertEqual(requests[0].cravingTime.minute, 0)
        XCTAssertEqual(requests[0].notificationTime.hour, 7)
        XCTAssertEqual(requests[0].notificationTime.minute, 50)
        XCTAssertEqual(requests[0].identifier, "craving.11111111-1111-1111-1111-111111111111")
    }

    func testTriggerWithoutTimeDoesNotSchedule() async {
        let center = FakeNotificationCenter(permission: .authorized)
        let scheduler = CravingReminderScheduler(center: center, calendar: calendar)
        let id = UUID()
        await scheduler.synchronize([.init(id: id, trigger: .driving, cravingTime: nil, enabled: true)])
        let added = await center.added; let removed = await center.removed
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(removed, [CravingReminderScheduler.identifier(for: id)])
    }

    func testChangingTimeReplacesStableRequest() async {
        let center = FakeNotificationCenter(permission: .authorized)
        let scheduler = CravingReminderScheduler(center: center, calendar: calendar)
        let id = UUID(); let first = Date(timeIntervalSince1970: 1_800_000_000); let second = first.addingTimeInterval(3600)
        await scheduler.scheduleReminder(id: id, trigger: .lateNight, cravingTime: first)
        await scheduler.scheduleReminder(id: id, trigger: .lateNight, cravingTime: second)
        let removed = await center.removed
        XCTAssertEqual(removed, [CravingReminderScheduler.identifier(for: id), CravingReminderScheduler.identifier(for: id)])
        let added = await center.added
        XCTAssertEqual(added[0].identifier, added[1].identifier)
        XCTAssertNotEqual(added[0].notificationTime.hour, added[1].notificationTime.hour)
    }

    func testDisabledAndRemovedTriggersCancelStableRequest() async {
        let center = FakeNotificationCenter(permission: .authorized)
        let scheduler = CravingReminderScheduler(center: center, calendar: calendar)
        let disabled = UUID(); let removed = UUID()
        await scheduler.synchronize([.init(id: disabled, trigger: .afterLunch, cravingTime: .now, enabled: false)])
        await scheduler.cancelReminder(id: removed)
        let cancelled = await center.removed
        XCTAssertEqual(Set(cancelled), Set([CravingReminderScheduler.identifier(for: disabled), CravingReminderScheduler.identifier(for: removed)]))
    }

    func testDisableAllCancelsOnlyCravingRequestsThroughCenter() async {
        let center = FakeNotificationCenter(permission: .authorized)
        await CravingReminderScheduler(center: center, calendar: calendar).cancelAllCravingReminders()
        let count = await center.removeAllCount; XCTAssertEqual(count, 1)
    }

    func testDeniedPermissionIsNotRequestedAgain() async {
        let center = FakeNotificationCenter(permission: .denied)
        let result = await CravingReminderScheduler(center: center, calendar: calendar).requestAuthorizationIfNeeded()
        XCTAssertEqual(result, .denied)
        let count = await center.authorizationRequestCount; XCTAssertEqual(count, 0)
    }

    func testNotDeterminedPermissionIsRequestedOnce() async {
        let center = FakeNotificationCenter(permission: .notDetermined, authorizationResult: true)
        let scheduler = CravingReminderScheduler(center: center, calendar: calendar)
        let result = await scheduler.requestAuthorizationIfNeeded(); let count = await center.authorizationRequestCount
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(count, 1)
    }

    func testLocalClockComponentsDoNotStoreUTCDate() {
        let time = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 0, minute: 5))!
        let request = CravingReminderScheduler.makeRequest(id: UUID(), trigger: .lateNight, cravingTime: time, calendar: calendar)
        XCTAssertNil(request.notificationTime.timeZone)
        XCTAssertNil(request.notificationTime.year)
        XCTAssertEqual(request.notificationTime.hour, 23)
        XCTAssertEqual(request.notificationTime.minute, 55)
    }

    func testWelcomeRoutingAndSeenFlag() {
        XCTAssertTrue(FirstRunPreferences.shouldShowWelcome(hasProfile: false, hasSeenWelcome: false))
        XCTAssertFalse(FirstRunPreferences.shouldShowWelcome(hasProfile: false, hasSeenWelcome: true))
        XCTAssertFalse(FirstRunPreferences.shouldShowWelcome(hasProfile: true, hasSeenWelcome: false))
    }
}

private actor FakeNotificationCenter: CravingNotificationCenter {
    var currentPermission: CravingNotificationPermission
    let authorizationResult: Bool
    var added: [CravingReminderRequest] = []
    var removed: [String] = []
    var removeAllCount = 0
    var authorizationRequestCount = 0
    init(permission: CravingNotificationPermission, authorizationResult: Bool = false) {
        currentPermission = permission; self.authorizationResult = authorizationResult
    }
    func permission() async -> CravingNotificationPermission { currentPermission }
    func requestAuthorization() async throws -> Bool { authorizationRequestCount += 1; currentPermission = authorizationResult ? .authorized : .denied; return authorizationResult }
    func add(_ request: CravingReminderRequest) async throws { added.append(request) }
    func remove(identifier: String) async { removed.append(identifier) }
    func removeAllCravingRequests() async { removeAllCount += 1 }
}
