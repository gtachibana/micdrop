import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: QueueStore
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Songs", systemImage: "music.mic") }
            QueueView()
                .tabItem { Label("Queue", systemImage: "list.number") }
                .badge(queue.entries.count)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.pink)
        .task { library.refresh() }
        .fullScreenCover(isPresented: $player.isNowPlayingPresented) {
            NowPlayingView()
                .environmentObject(library)
                .environmentObject(queue)
                .environmentObject(player)
        }
        .alert("Playback Problem", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
        .alert("Library Problem", isPresented: Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let entry = player.nowPlaying {
            HStack(spacing: 12) {
                Image(systemName: entry.song.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.song.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.singer.isEmpty ? entry.song.artist : "\(entry.singer) · \(entry.song.artist)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                Button { player.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
            .onTapGesture { player.isNowPlayingPresented = true }
        }
    }
}

extension View {
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}

func formatTime(_ seconds: Double) -> String {
    let total = Int(max(seconds, 0).rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
}
