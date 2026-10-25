import SwiftUI
import UniformTypeIdentifiers

enum LibrarySort: String, CaseIterable, Identifiable {
    case artist, title
    var id: String { rawValue }
    var label: String { self == .artist ? "Artist" : "Title" }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: QueueStore
    @EnvironmentObject private var player: PlayerController
    @AppStorage(SettingsKey.librarySort) private var sort: LibrarySort = .artist

    @State private var searchText = ""
    @State private var actionSong: Song?
    @State private var singerPromptSong: Song?
    @State private var singerName = ""
    @State private var showImporter = false
    @State private var importingFolder = false
    @State private var showingFolders = false
    @State private var showingOpenKJ = false

    var body: some View {
        NavigationStack {
            Group {
                if library.songs.isEmpty {
                    if library.isScanning {
                        ProgressView("Scanning…")
                    } else {
                        emptyState
                    }
                } else {
                    songList
                }
            }
            .navigationTitle("Songs")
            .searchable(text: $searchText, prompt: "Artist, title or file name")
            .toolbar { toolbar }
            .confirmationDialog(
                actionSong?.title ?? "",
                isPresented: Binding(get: { actionSong != nil }, set: { if !$0 { actionSong = nil } }),
                titleVisibility: .visible,
                presenting: actionSong
            ) { song in
                Button("Sing Now") { player.play(QueueEntry(song: song)) }
                Button("Add to Queue") { queue.add(song) }
                Button("Add to Queue with Singer…") {
                    singerName = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { singerPromptSong = song }
                }
                Button("Play Next") { queue.addNext(song) }
            } message: { song in
                Text(song.artist.isEmpty ? song.fileName : song.artist)
            }
            .alert(
                "Who's singing?",
                isPresented: Binding(get: { singerPromptSong != nil }, set: { if !$0 { singerPromptSong = nil } }),
                presenting: singerPromptSong
            ) { song in
                TextField("Singer name", text: $singerName)
                    .textInputAutocapitalization(.words)
                Button("Add to Queue") { queue.add(song, singer: singerName.trimmingCharacters(in: .whitespaces)) }
                Button("Cancel", role: .cancel) {}
            } message: { song in
                Text(song.title)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importingFolder ? [.folder] : [.item],
                allowsMultipleSelection: !importingFolder
            ) { result in
                guard case .success(let urls) = result else { return }
                if importingFolder {
                    if let folder = urls.first { library.linkFolder(folder) }
                } else {
                    library.importItems(urls)
                }
            }
            .sheet(isPresented: $showingFolders) {
                LinkedFoldersView().environmentObject(library)
            }
            .sheet(isPresented: $showingOpenKJ) {
                OpenKJView()
                    .environmentObject(library)
                    .environmentObject(OpenKJStore.shared)
            }
        }
        .miniPlayerInset()
    }

    private var visibleSongs: [Song] {
        let base = sort == .artist ? library.songs : library.songsByTitle
        let terms = searchText.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return base }
        return base.filter { song in terms.allSatisfy { song.searchText.contains($0) } }
    }

    private var songList: some View {
        let songs = visibleSongs
        return List {
            Section {
                ForEach(songs) { song in
                    SongRow(song: song)
                        .contentShape(Rectangle())
                        .onTapGesture { actionSong = song }
                        .swipeActions(edge: .leading) {
                            Button { queue.add(song) } label: {
                                Label("Queue", systemImage: "text.badge.plus")
                            }
                            .tint(.indigo)
                        }
                        .swipeActions(edge: .trailing) {
                            if song.isInAppDocuments {
                                Button(role: .destructive) { library.delete(song) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                Text(songs.count == 1 ? "1 song" : "\(songs.count) songs")
            }
        }
        .listStyle(.plain)
        .refreshable { await library.refreshAndWait() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Songs Yet", systemImage: "music.mic")
        } description: {
            Text("Copy karaoke files into Files › On My iPhone › MicDrop, tap + to import them, or link a folder from iCloud Drive or a USB drive.\n\nSupports MP3+CDG (zipped or not), MP4/M4V/MOV and audio files.")
        } actions: {
            Button("Import Files") {
                importingFolder = false
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
            Button("Link a Folder") {
                importingFolder = true
                showImporter = true
            }
            Button("Get from OpenKJ") {
                showingOpenKJ = true
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    importingFolder = false
                    showImporter = true
                } label: {
                    Label("Import Files…", systemImage: "square.and.arrow.down")
                }
                Button {
                    importingFolder = true
                    showImporter = true
                } label: {
                    Label("Link Folder…", systemImage: "folder.badge.plus")
                }
                Button {
                    showingOpenKJ = true
                } label: {
                    Label("Get from OpenKJ…", systemImage: "server.rack")
                }
                Button {
                    showingFolders = true
                } label: {
                    Label("Linked Folders", systemImage: "folder")
                }
                Divider()
                Button {
                    library.refresh()
                } label: {
                    Label("Rescan Library", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !song.artist.isEmpty {
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(song.kind.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}

struct LinkedFoldersView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.folders) { folder in
                        Label(folder.name, systemImage: "folder")
                    }
                    .onDelete { library.unlinkFolders(at: $0) }
                } footer: {
                    Text("Linked folders are scanned in place without copying. Swipe to unlink; your files are not deleted. Songs in Files › On My iPhone › MicDrop are always included.")
                }
            }
            .overlay {
                if library.folders.isEmpty {
                    ContentUnavailableView("No Linked Folders", systemImage: "folder",
                                           description: Text("Use + › Link Folder… to add one."))
                }
            }
            .navigationTitle("Linked Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
