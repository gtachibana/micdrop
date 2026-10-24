import AVFoundation
import Combine
import MediaPlayer
import UIKit

@MainActor
final class PlayerController: ObservableObject {
    static let shared = PlayerController()

    enum Stage {
        case idle, cdg, video, audioOnly
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var nowPlaying: QueueEntry?
    @Published private(set) var videoPlayer: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var semitones = 0
    @Published private(set) var tempo = 1.0
    @Published var errorMessage: String?
    @Published var isNowPlayingPresented = false
    @Published var externalDisplayConnected = false

    let cdgRenderer = CDGRenderer()

    private var audioEngine: AudioFileEngine?
    private var videoEngine: VideoEngine?
    private var ticker: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var loadToken = UUID()

    static let semitoneRange = -12...12
    static let tempoRange = 0.5...1.5

    init() {
        configureRemoteCommands()
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.pause()
            }
            .store(in: &cancellables)
    }

    /// Key change is done with AVAudioEngine, which we only use for audio files (incl. MP3+CDG).
    var supportsKeyChange: Bool { stage == .cdg || stage == .audioOnly }

    // MARK: - Loading

    func play(_ entry: QueueEntry) {
        teardown()
        let token = UUID()
        loadToken = token
        nowPlaying = entry
        stage = .idle
        semitones = 0
        tempo = 1
        currentTime = 0
        duration = 0
        isLoading = true
        isNowPlayingPresented = true

        let song = entry.song
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try MediaResolver.resolve(song) }
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.isLoading = false
                do {
                    try self.start(result.get())
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    private func start(_ media: ResolvedMedia) throws {
        try? AVAudioSession.sharedInstance().setActive(true)
        switch media {
        case let .cdg(audioURL, cdgURL):
            let decoder = try CDGDecoder(contentsOf: cdgURL)
            let engine = try AudioFileEngine(url: audioURL)
            engine.onFinish = { [weak self] in self?.songFinished() }
            audioEngine = engine
            duration = engine.duration
            cdgRenderer.load(decoder) { [weak engine] in
                (engine?.currentTime ?? 0) + AppSettings.lyricsOffset
            }
            stage = .cdg
            engine.play()
            cdgRenderer.start()

        case .video(let url):
            let engine = VideoEngine(url: url)
            engine.onFinish = { [weak self] in self?.songFinished() }
            videoEngine = engine
            videoPlayer = engine.player
            stage = .video
            engine.play()

        case .audio(let url):
            let engine = try AudioFileEngine(url: url)
            engine.onFinish = { [weak self] in self?.songFinished() }
            audioEngine = engine
            duration = engine.duration
            stage = .audioOnly
            engine.play()
        }
        isPlaying = true
        startTicker()
        playbackStateChanged()
    }

    private func fail(_ error: Error) {
        let name = nowPlaying?.song.fileName ?? "this song"
        teardown()
        nowPlaying = nil
        stage = .idle
        errorMessage = "Couldn't play \(name).\n\(error.localizedDescription)"
        playbackStateChanged()
    }

    private func teardown() {
        loadToken = UUID()
        ticker = nil
        cdgRenderer.unload()
        audioEngine?.stop()
        audioEngine = nil
        videoEngine?.stop()
        videoEngine = nil
        videoPlayer = nil
        isPlaying = false
        isLoading = false
    }

    // MARK: - Transport

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        audioEngine?.pause()
        videoEngine?.pause()
        isPlaying = false
        playbackStateChanged()
    }

    func resume() {
        guard nowPlaying != nil, !isLoading else {
            if nowPlaying == nil { playNext() }
            return
        }
        audioEngine?.play()
        videoEngine?.play()
        isPlaying = audioEngine?.isPlaying ?? videoEngine?.isPlaying ?? false
        playbackStateChanged()
    }

    func seek(to time: Double) {
        let clamped = min(max(time, 0), duration > 0 ? duration : time)
        audioEngine?.seek(to: clamped)
        videoEngine?.seek(to: clamped)
        currentTime = clamped
        playbackStateChanged()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func restart() {
        seek(to: 0)
    }

    /// Starts the next queued song, or stops if the queue is empty.
    func playNext() {
        if let next = QueueStore.shared.popFirst() {
            play(next)
        } else {
            stopPlayback()
        }
    }

    func stopPlayback() {
        teardown()
        nowPlaying = nil
        stage = .idle
        currentTime = 0
        duration = 0
        playbackStateChanged()
    }

    private func songFinished() {
        if AppSettings.autoAdvance, let next = QueueStore.shared.popFirst() {
            play(next)
        } else {
            stopPlayback()
        }
    }

    // MARK: - Key & tempo

    func setSemitones(_ value: Int) {
        semitones = min(max(value, Self.semitoneRange.lowerBound), Self.semitoneRange.upperBound)
        audioEngine?.pitchCents = Float(semitones * 100)
    }

    func setTempo(_ value: Double) {
        tempo = min(max((value * 100).rounded() / 100, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
        audioEngine?.rate = Float(tempo)
        videoEngine?.rate = Float(tempo)
    }

    // MARK: - Clock

    private func startTicker() {
        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if let audioEngine {
            currentTime = audioEngine.currentTime
            if isPlaying != audioEngine.isPlaying {
                isPlaying = audioEngine.isPlaying
                playbackStateChanged()
            }
        } else if let videoEngine {
            if let error = videoEngine.error {
                fail(error)
                return
            }
            currentTime = videoEngine.currentTime
            if duration == 0, videoEngine.duration > 0 {
                duration = videoEngine.duration
                updateNowPlayingInfo()
            }
        }
    }

    // MARK: - System integration

    private func playbackStateChanged() {
        UIApplication.shared.isIdleTimerDisabled = isPlaying && AppSettings.keepAwake
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let entry = nowPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: entry.song.title,
            MPMediaItemPropertyArtist: entry.singer.isEmpty ? entry.song.artist : "\(entry.song.artist) — \(entry.singer)",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? tempo : 0,
        ]
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }
}
