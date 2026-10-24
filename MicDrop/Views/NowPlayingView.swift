import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var queue: QueueStore
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var scrubTime: Double?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .statusBarHidden(landscape)
            .persistentSystemOverlays(landscape ? .hidden : .automatic)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layouts

    private var portraitLayout: some View {
        VStack(spacing: 20) {
            topBar
            stage
                .aspectRatio(300.0 / 216.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            songInfo
            progress
            transport
            adjustments
            Spacer(minLength: 0)
            upNext
        }
        .padding()
    }

    private var landscapeLayout: some View {
        ZStack {
            stage
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
                }
            if controlsVisible {
                VStack {
                    topBar
                        .padding()
                        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                    Spacer()
                    VStack(spacing: 12) {
                        progress
                        HStack {
                            adjustments
                                .frame(maxWidth: 340)
                            Spacer()
                            transport
                        }
                    }
                    .padding()
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
        }
    }

    private var stage: some View {
        StageView()
            .overlay {
                if player.isLoading {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                if player.externalDisplayConnected {
                    Label("On TV", systemImage: "tv")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            if let singer = player.nowPlaying?.singer, !singer.isEmpty {
                Label(singer, systemImage: "music.mic")
                    .font(.headline)
                    .foregroundStyle(.pink)
            }
            Spacer()
            Button { player.stopPlayback() } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(player.nowPlaying == nil)
        }
        .foregroundStyle(.white)
    }

    private var songInfo: some View {
        VStack(spacing: 4) {
            Text(player.nowPlaying?.song.title ?? "Nothing Playing")
                .font(.title2.weight(.bold))
                .lineLimit(2)
            Text(player.nowPlaying?.song.artist ?? " ")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let time = scrubTime {
                        player.seek(to: time)
                        scrubTime = nil
                    }
                }
            )
            .disabled(player.nowPlaying == nil || player.isLoading)
            HStack {
                Text(formatTime(scrubTime ?? player.currentTime))
                Spacer()
                Text("-" + formatTime(player.duration - (scrubTime ?? player.currentTime)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            Button { player.restart() } label: {
                Image(systemName: "backward.end.fill").font(.title2)
            }
            Button { player.skip(by: -10) } label: {
                Image(systemName: "gobackward.10").font(.title2)
            }
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
            }
            Button { player.skip(by: 10) } label: {
                Image(systemName: "goforward.10").font(.title2)
            }
            Button { player.playNext() } label: {
                Image(systemName: "forward.end.fill").font(.title2)
            }
        }
        .foregroundStyle(.white)
        .disabled(player.isLoading)
    }

    private var adjustments: some View {
        HStack(spacing: 12) {
            AdjustControl(
                title: "Key",
                value: player.semitones == 0 ? "0" : String(format: "%+d", player.semitones),
                isModified: player.semitones != 0,
                minus: { player.setSemitones(player.semitones - 1) },
                plus: { player.setSemitones(player.semitones + 1) },
                reset: { player.setSemitones(0) }
            )
            .disabled(!player.supportsKeyChange)
            .opacity(player.supportsKeyChange ? 1 : 0.4)

            AdjustControl(
                title: "Tempo",
                value: "\(Int((player.tempo * 100).rounded()))%",
                isModified: player.tempo != 1,
                minus: { player.setTempo(player.tempo - 0.05) },
                plus: { player.setTempo(player.tempo + 0.05) },
                reset: { player.setTempo(1) }
            )
        }
        .disabled(player.nowPlaying == nil || player.isLoading)
    }

    @ViewBuilder
    private var upNext: some View {
        if let next = queue.entries.first {
            HStack {
                Text("Up next")
                    .foregroundStyle(.secondary)
                Text(next.singer.isEmpty ? next.song.title : "\(next.singer) – \(next.song.title)")
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            .font(.footnote)
        }
    }
}

private struct AdjustControl: View {
    let title: String
    let value: String
    let isModified: Bool
    let minus: () -> Void
    let plus: () -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Button(action: minus) {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 32)
                }
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isModified ? .pink : .white)
                    .frame(minWidth: 52)
                    .onTapGesture(count: 2, perform: reset)
                Button(action: plus) {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 32)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
