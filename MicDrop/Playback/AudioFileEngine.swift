import AVFoundation
import Combine

/// Plays an audio file through AVAudioEngine so key (pitch) and tempo can be changed
/// independently, and exposes a precise playback clock for syncing CD+G graphics.
final class AudioFileEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let file: AVAudioFile
    private let sampleRate: Double
    private var startFrame: AVAudioFramePosition = 0
    private var pausedTime: Double = 0
    private var lastKnownTime: Double = 0
    private var generation = 0
    private var outputLatency: Double = 0
    private var observers: Set<AnyCancellable> = []

    private(set) var isPlaying = false
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        sampleRate = file.processingFormat.sampleRate
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.connect(playerNode, to: timePitch, format: file.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
        engine.prepare()
        try engine.start()
        schedule(from: 0)

        updateOutputLatency()

        NotificationCenter.default
            .publisher(for: .AVAudioEngineConfigurationChange, object: engine)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recoverFromConfigurationChange() }
            .store(in: &observers)
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateOutputLatency() }
            .store(in: &observers)
    }

    var duration: Double { Double(file.length) / sampleRate }

    var currentTime: Double {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return pausedTime }
        // The render clock runs ahead of what's audible by the output latency (large over
        // Bluetooth/AirPlay). Latency is in real time, so scale it to file time by the tempo.
        let rendered = Double(startFrame + playerTime.sampleTime) / sampleRate
        let time = min(max(rendered - outputLatency * Double(timePitch.rate), 0), duration)
        lastKnownTime = time
        return time
    }

    /// Key change in cents (100 per semitone).
    var pitchCents: Float {
        get { timePitch.pitch }
        set { timePitch.pitch = newValue }
    }

    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = newValue }
    }

    func play() {
        guard !isPlaying else { return }
        if !engine.isRunning { try? engine.start() }
        updateOutputLatency()
        playerNode.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        playerNode.pause()
        isPlaying = false
    }

    func seek(to time: Double) {
        let wasPlaying = isPlaying
        isPlaying = false
        let clamped = min(max(time, 0), max(duration - 0.05, 0))
        schedule(from: AVAudioFramePosition(clamped * sampleRate))
        if wasPlaying { play() }
    }

    func stop() {
        generation += 1
        playerNode.stop()
        engine.stop()
        isPlaying = false
    }

    private func schedule(from frame: AVAudioFramePosition) {
        generation += 1
        let scheduled = generation
        playerNode.stop()
        startFrame = frame
        pausedTime = Double(frame) / sampleRate
        lastKnownTime = pausedTime
        let remaining = file.length - frame
        guard remaining > 0 else { return }
        playerNode.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == scheduled else { return }
                self.isPlaying = false
                self.pausedTime = self.duration
                self.onFinish?()
            }
        }
    }

    private func updateOutputLatency() {
        let session = AVAudioSession.sharedInstance()
        outputLatency = session.outputLatency + session.ioBufferDuration + timePitch.auAudioUnit.latency
    }

    /// The engine stops itself when the output route changes (e.g. headphones unplugged).
    /// Resume from where we were, paused, like other audio apps do.
    private func recoverFromConfigurationChange() {
        let time = lastKnownTime
        isPlaying = false
        try? engine.start()
        updateOutputLatency()
        schedule(from: AVAudioFramePosition(time * sampleRate))
    }
}
