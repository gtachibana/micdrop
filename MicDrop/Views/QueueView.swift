import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var queue: QueueStore
    @EnvironmentObject private var player: PlayerController

    @State private var editingEntry: QueueEntry?
    @State private var singerName = ""
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                if let now = player.nowPlaying {
                    Section("Now Singing") {
                        QueueRow(entry: now, position: nil)
                            .contentShape(Rectangle())
                            .onTapGesture { player.isNowPlayingPresented = true }
                    }
                }
                Section {
                    ForEach(Array(queue.entries.enumerated()), id: \.element.id) { index, entry in
                        QueueRow(entry: entry, position: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                singerName = entry.singer
                                editingEntry = entry
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    queue.remove(entry)
                                    player.play(entry)
                                } label: {
                                    Label("Sing Now", systemImage: "play.fill")
                                }
                                .tint(.pink)
                            }
                    }
                    .onDelete(perform: queue.remove(atOffsets:))
                    .onMove(perform: queue.move(fromOffsets:toOffset:))
                } header: {
                    Text("Up Next")
                } footer: {
                    Text(queue.entries.isEmpty
                         ? "Add songs from the Songs tab. Tap a queued song to set the singer, drag to reorder."
                         : "Tap to set the singer. Drag to reorder, swipe to remove.")
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !queue.entries.isEmpty {
                        Button("Clear", role: .destructive) { confirmingClear = true }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if player.nowPlaying == nil && !queue.entries.isEmpty {
                        Button {
                            player.playNext()
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                    }
                    EditButton()
                }
            }
            .confirmationDialog("Clear the whole queue?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Queue", role: .destructive) { queue.clear() }
            }
            .alert(
                "Singer",
                isPresented: Binding(get: { editingEntry != nil }, set: { if !$0 { editingEntry = nil } }),
                presenting: editingEntry
            ) { entry in
                TextField("Singer name", text: $singerName)
                    .textInputAutocapitalization(.words)
                Button("Save") { queue.setSinger(singerName.trimmingCharacters(in: .whitespaces), for: entry) }
                Button("Cancel", role: .cancel) {}
            } message: { entry in
                Text(entry.song.title)
            }
        }
        .miniPlayerInset()
    }
}

private struct QueueRow: View {
    let entry: QueueEntry
    let position: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let position {
                Text("\(position)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24)
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .frame(minWidth: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !entry.singer.isEmpty {
                    Text(entry.singer)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(entry.song.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !entry.song.artist.isEmpty {
                    Text(entry.song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
