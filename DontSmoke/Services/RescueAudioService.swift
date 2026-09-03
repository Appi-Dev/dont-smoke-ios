import AVFoundation
import Foundation

@MainActor
final class RescueAudioService: NSObject, AVAudioPlayerDelegate {
    static let playbackVolume: Float = 0.2
    private static let lastSoundKey = "lastRescueRandomSound"

    private var player: AVAudioPlayer?
    private var wasPlayingBeforeInterruption = false
    private var currentSound: RescueSoundscape?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interruptionReceived(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    static var lastRandomSound: RescueSoundscape? {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: lastSoundKey) else { return nil }
            return RescueSoundscape(rawValue: rawValue)
        }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: lastSoundKey) }
    }

    func play(_ soundscape: RescueSoundscape?, muted: Bool) {
        if !muted, currentSound == soundscape, player != nil { return }
        stop()
        guard !muted, let soundscape, soundscape != .silence,
              let url = Bundle.main.url(forResource: soundscape.resourceName, withExtension: "wav") else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.numberOfLoops = -1
            player.volume = Self.playbackVolume
            player.prepareToPlay()
            player.play()
            self.player = player
            currentSound = soundscape
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentSound = nil
        wasPlayingBeforeInterruption = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    @objc nonisolated private func interruptionReceived(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
        }
    }

    private func handleInterruption(rawType: UInt, rawOptions: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = player?.isPlaying == true
            player?.pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) { player?.play() }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }
}
