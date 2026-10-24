import AVFoundation
import SwiftUI
import UIKit

/// The "screen" part of karaoke: CD+G graphics, video, or a title card.
struct StageView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var queue: QueueStore
    var showsQueueWhenIdle = false

    var body: some View {
        ZStack {
            Color.black
            switch player.stage {
            case .cdg:
                CDGLayerView(renderer: player.cdgRenderer)
            case .video:
                if let avPlayer = player.videoPlayer {
                    VideoLayerView(player: avPlayer)
                }
            case .audioOnly:
                if let entry = player.nowPlaying {
                    TitleCard(heading: entry.singer.isEmpty ? "Now Playing" : entry.singer, entry: entry)
                }
            case .idle:
                if player.isLoading, let entry = player.nowPlaying {
                    TitleCard(heading: entry.singer.isEmpty ? "Get Ready" : "Get ready, \(entry.singer)!", entry: entry)
                } else if showsQueueWhenIdle, let next = queue.entries.first {
                    TitleCard(heading: next.singer.isEmpty ? "Up Next" : "Up Next: \(next.singer)", entry: next)
                } else {
                    IdleCard()
                }
            }
        }
    }
}

private struct TitleCard: View {
    let heading: String
    let entry: QueueEntry

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 600, 2.5)
            VStack(spacing: 12 * scale) {
                Text(heading)
                    .font(.system(size: 22 * scale, weight: .semibold))
                    .foregroundStyle(.pink)
                Text(entry.song.title)
                    .font(.system(size: 36 * scale, weight: .bold))
                    .foregroundStyle(.white)
                if !entry.song.artist.isEmpty {
                    Text(entry.song.artist)
                        .font(.system(size: 24 * scale))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct IdleCard: View {
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 600, 2.5)
            VStack(spacing: 8 * scale) {
                Image(systemName: "music.mic")
                    .font(.system(size: 48 * scale))
                    .foregroundStyle(.pink)
                Text("MicDrop")
                    .font(.system(size: 32 * scale, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CDGLayerView: UIViewRepresentable {
    let renderer: CDGRenderer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.contentsGravity = .resizeAspect
        view.layer.magnificationFilter = .nearest
        renderer.attach(view.layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        renderer.attach(uiView.layer)
    }
}

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}
