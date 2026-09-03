import AVFoundation
import Foundation

@MainActor
final class RescueAudioService: NSObject, AVAudioPlayerDelegate {
    static let defaultRescueVolume: Float = 0.45
    private static let fadeInDuration: TimeInterval = 1.8
    private static let fadeOutDuration: TimeInterval = 0.35
    private static let lastSoundKey = "lastRescueRandomSound"

    private var player: AVAudioPlayer?
    private var desiredSound: RescueSoundscape?
    private var transitionTask: Task<Void, Never>?
    private var isInterrupted = false

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
        let requested = muted || soundscape == .silence ? nil : soundscape
        guard requested != desiredSound else { return }
        desiredSound = requested
        scheduleTransition()
    }

    private func scheduleTransition() {
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            if let player = self.player {
                player.setVolume(0, fadeDuration: Self.fadeOutDuration)
                do { try await Task.sleep(for: .seconds(Self.fadeOutDuration)) }
                catch { return }
                player.stop()
                self.player = nil
            }
            guard !Task.isCancelled else { return }
            if let desiredSound, !isInterrupted {
                startPlayer(for: desiredSound)
            } else if desiredSound == nil {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }
            transitionTask = nil
        }
    }

    private func startPlayer(for soundscape: RescueSoundscape) {
        guard let url = soundscape.resourceURL() else {
            #if DEBUG
            print("[Rescue] Missing resource: \(soundscape.resourceFilename ?? "Silence")")
            #endif
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            player.setVolume(Self.defaultRescueVolume, fadeDuration: Self.fadeInDuration)
            self.player = player
            #if DEBUG
            print("[Rescue] Playing resource: \(url.lastPathComponent)")
            #endif
        } catch {
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            #if DEBUG
            print("[Rescue] Audio could not start: \(error)")
            #endif
        }
    }

    func stop() {
        desiredSound = nil
        scheduleTransition()
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
            isInterrupted = true
            player?.pause()
        case .ended:
            isInterrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if desiredSound != nil, options.contains(.shouldResume) {
                scheduleTransition()
            }
        @unknown default:
            break
        }
    }
}
