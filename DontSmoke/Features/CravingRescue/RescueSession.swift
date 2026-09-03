import Foundation

enum RescuePhase: Equatable {
    case grounding
    case breathing
    case checkIn
    case myWhy
    case continuedBreathing
    case completed
    case extended
}

enum RescueSoundscape: String, CaseIterable, Identifiable, Codable {
    case rain
    case ocean
    case forest
    case breeze
    case night
    case warmAmbient
    case silence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: "Soft Rain"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .breeze: "Gentle Breeze"
        case .night: "Night Ambience"
        case .warmAmbient: "Warm Ambient"
        case .silence: "Silence"
        }
    }

    var resourceName: String { rawValue }
    var resourceFilename: String? { self == .silence ? nil : "\(resourceName).wav" }
    func resourceURL(in bundle: Bundle = .main) -> URL? {
        guard self != .silence else { return nil }
        return bundle.url(forResource: resourceName, withExtension: "wav")
    }
}

struct RescueAccess: Equatable {
    let sessionDuration: TimeInterval
    let availableSoundscapes: [RescueSoundscape]
    let canExtend: Bool

    static let free = RescueAccess(
        sessionDuration: 300,
        availableSoundscapes: RescueSoundscape.allCases,
        canExtend: true
    )

    static let premium = RescueAccess(
        sessionDuration: 300,
        availableSoundscapes: RescueSoundscape.allCases,
        canExtend: true
    )
}

protocol RescueEntitlementProviding {
    var rescueAccess: RescueAccess { get }
}

struct DefaultRescueEntitlements: RescueEntitlementProviding {
    // Development access is unrestricted. StoreKit restrictions will be added later.
    let rescueAccess = RescueAccess.free
}

enum RescueSoundSelection: Equatable {
    case random
    case soundscape(RescueSoundscape)
}

enum RescueSoundSelector {
    static func randomSound(
        from available: [RescueSoundscape],
        excluding lastSound: RescueSoundscape?,
        randomIndex: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) -> RescueSoundscape? {
        var candidates = available.filter { $0 != .silence }
        if candidates.count > 1, let lastSound {
            candidates.removeAll { $0 == lastSound }
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[randomIndex(candidates.indices)]
    }
}

struct RescueSession {
    static let groundingDuration: TimeInterval = 20
    static let checkInTime: TimeInterval = 120
    static let extensionDuration: TimeInterval = 300

    let access: RescueAccess
    let startDate: Date
    private(set) var now: Date
    private(set) var phase: RescuePhase = .grounding {
        didSet {
            #if DEBUG
            if oldValue != phase { print("[Rescue] Phase: \(oldValue) -> \(phase); elapsed: \(Int(elapsed))s") }
            #endif
        }
    }
    private(set) var selectedSound: RescueSoundscape?
    private(set) var soundSelection: RescueSoundSelection = .random
    private(set) var isMuted = false
    private(set) var extensionStartDate: Date?
    private(set) var extensionUsed = false

    init(
        access: RescueAccess,
        startDate: Date = .now,
        lastRandomSound: RescueSoundscape? = nil,
        randomIndex: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) {
        self.access = access
        self.startDate = startDate
        now = startDate
        selectedSound = RescueSoundSelector.randomSound(
            from: access.availableSoundscapes,
            excluding: lastRandomSound,
            randomIndex: randomIndex
        )
        logRandomSound()
    }

    var elapsed: TimeInterval {
        max(0, now.timeIntervalSince(startDate))
    }

    var extensionElapsed: TimeInterval {
        guard let extensionStartDate else { return 0 }
        return max(0, now.timeIntervalSince(extensionStartDate))
    }

    var canExtend: Bool { access.canExtend && !extensionUsed }

    var breathingPhase: BreathingPhase {
        let breathingElapsed: TimeInterval
        if phase == .extended {
            breathingElapsed = extensionElapsed
        } else {
            breathingElapsed = max(0, elapsed - Self.groundingDuration)
        }
        let cyclePosition = breathingElapsed.truncatingRemainder(dividingBy: 12)
        switch cyclePosition {
        case 0..<4: return .inhale
        case 4..<6: return .hold
        default: return .exhale
        }
    }

    var breathingSecondsRemaining: Int {
        let breathingElapsed = phase == .extended ? extensionElapsed : max(0, elapsed - Self.groundingDuration)
        let cyclePosition = breathingElapsed.truncatingRemainder(dividingBy: 12)
        let boundary: TimeInterval = cyclePosition < 4 ? 4 : (cyclePosition < 6 ? 6 : 12)
        return max(1, Int(ceil(boundary - cyclePosition)))
    }

    mutating func update(now: Date) {
        self.now = now
        if phase == .extended {
            if extensionElapsed >= Self.extensionDuration { phase = .completed }
            return
        }
        if phase == .completed { return }
        if elapsed >= access.sessionDuration { phase = .completed; return }
        if phase == .checkIn || phase == .myWhy { return }
        if elapsed < Self.groundingDuration {
            phase = .grounding
        } else if elapsed < Self.checkInTime {
            phase = .breathing
        } else if phase == .continuedBreathing {
            if elapsed >= access.sessionDuration { phase = .completed }
        } else {
            phase = .checkIn
        }
    }

    mutating func answerCheckIn(isEasier: Bool) {
        guard phase == .checkIn else { return }
        if !isEasier {
            phase = .myWhy
        } else {
            continueAfterCheckIn()
        }
    }

    mutating func continueAfterWhy() {
        guard phase == .myWhy else { return }
        continueAfterCheckIn()
    }

    mutating func startExtension(at date: Date) {
        guard phase == .completed, canExtend else { return }
        extensionUsed = true
        extensionStartDate = date
        now = date
        phase = .extended
    }

    mutating func select(_ selection: RescueSoundSelection, randomIndex: (Range<Int>) -> Int = { Int.random(in: $0) }) {
        switch selection {
        case .random:
            soundSelection = selection
            selectedSound = RescueSoundSelector.randomSound(
                from: access.availableSoundscapes,
                excluding: selectedSound,
                randomIndex: randomIndex
            )
            logRandomSound()
        case .soundscape(let soundscape):
            guard access.availableSoundscapes.contains(soundscape) else { return }
            soundSelection = selection
            selectedSound = soundscape
        }
        isMuted = selectedSound == .silence
    }

    mutating func toggleMute() {
        isMuted.toggle()
    }

    private mutating func continueAfterCheckIn() {
        phase = elapsed >= access.sessionDuration ? .completed : .continuedBreathing
    }

    private func logRandomSound() {
        #if DEBUG
        print("[Rescue] Random sound selected: \(selectedSound?.title ?? "Silence")")
        #endif
    }
}

enum BreathingPhase: CaseIterable {
    case inhale, hold, exhale

    var title: String {
        switch self {
        case .inhale: "Breathe in"
        case .hold: "Hold"
        case .exhale: "Breathe out"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .inhale: 4
        case .hold: 2
        case .exhale: 6
        }
    }

    var circleSize: CGFloat {
        switch self {
        case .inhale, .hold: 280
        case .exhale: 190
        }
    }
}
