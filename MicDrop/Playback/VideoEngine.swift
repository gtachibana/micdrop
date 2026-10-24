import AVFoundation
import Combine

/// Plays video karaoke files (MP4/MOV/M4V) with AVPlayer.
final class VideoEngine {
    let player: AVPlayer
    private let item: AVPlayerItem
    private var endObserver: AnyCancellable?

    private(set) var isPlaying = false
    var onFinish: (() -> Void)?

    var rate: Float = 1 {
        didSet { if isPlaying { player.rate = rate } }
    }

    init(url: URL) {
        item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: item)
        // Keep video in our own stage so the TV scene controls what is shown.
        player.allowsExternalPlayback = false
        endObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.onFinish?()
            }
    }

    var currentTime: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var duration: Double {
        let d = item.duration.seconds
        return d.isFinite ? d : 0
    }

    var error: Error? {
        item.status == .failed ? item.error : nil
    }

    func play() {
        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to time: Double) {
        player.seek(to: CMTime(seconds: max(time, 0), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
    }
}
