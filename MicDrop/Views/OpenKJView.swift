import SwiftUI

/// Search an OpenKJ server's library and download songs into Documents/OpenKJ.
struct OpenKJView: View {
    @EnvironmentObject private var openKJ: OpenKJStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if openKJ.isSignedIn {
                    OpenKJBrowseView()
                } else {
                    OpenKJSignInView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct OpenKJSignInView: View {
    @EnvironmentObject private var openKJ: OpenKJStore
    @State private var host = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Address, e.g. 192.168.1.20", text: $host)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Admin password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
            } footer: {
                Text("In OpenKJ, turn on Local Mode and its embedded server (Settings › Modes & Network). The port defaults to \(String(OpenKJStore.defaultPort)). Use the PC's IP address or a .local name. The password is OpenKJ's admin password.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: signIn) {
                    HStack {
                        Text("Connect")
                        if isSigningIn {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSigningIn || host.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Connect to OpenKJ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if host.isEmpty { host = openKJ.host } }
    }

    private func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                try await openKJ.signIn(host: host, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}

struct OpenKJBrowseView: View {
    @EnvironmentObject private var openKJ: OpenKJStore
    @EnvironmentObject private var library: LibraryStore

    @State private var searchText = ""
    @State private var results: [RemoteSong] = []
    @State private var canLoadMore = false
    // Starts true so the first frame shows a spinner rather than "No Results".
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var failedSong: RemoteSong?
    @State private var confirmDownloadAll = false
    /// Library keys of songs already on the device, rebuilt only when the library changes.
    @State private var owned: Set<String> = []

    var body: some View {
        let missing = results.filter { $0.isPlayable && !owned.contains($0.libraryKey) && openKJ.downloads[$0.id] == nil }

        List {
            Section {
                ForEach(results) { song in
                    RemoteSongRow(song: song, isOwned: owned.contains(song.libraryKey), state: openKJ.downloads[song.id])
                        .contentShape(Rectangle())
                        .onTapGesture { tap(song) }
                }
                if canLoadMore {
                    Button("Load More") { Task { await load(reset: false) } }
                        .disabled(isLoading)
                }
            } header: {
                if !results.isEmpty {
                    Text(canLoadMore ? "First \(results.count) songs" : (results.count == 1 ? "1 song" : "\(results.count) songs"))
                }
            } footer: {
                if results.contains(where: { !$0.isPlayable }) {
                    Text("Greyed-out songs are in a format MicDrop can't play.")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if let errorMessage, results.isEmpty {
                ContentUnavailableView {
                    Label("Can't Reach OpenKJ", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load(reset: true) } }
                }
            } else if isLoading && results.isEmpty {
                ProgressView()
            } else if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search OpenKJ")
        .task(id: searchText) {
            // Waits for a pause in typing; a new keystroke cancels this task.
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
                if Task.isCancelled { return }
            }
            await load(reset: true)
        }
        .refreshable { await load(reset: true) }
        .onChange(of: library.songs, initial: true) { _, songs in
            owned = Set(songs.map { RemoteSong.libraryKey(artist: $0.artist, title: $0.title) })
        }
        .navigationTitle("OpenKJ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        confirmDownloadAll = true
                    } label: {
                        Label("Download All Shown (\(missing.count))", systemImage: "arrow.down.circle")
                    }
                    .disabled(missing.isEmpty)
                    if openKJ.activeCount > 0 {
                        Button(role: .destructive) { openKJ.cancelAll() } label: {
                            Label("Cancel Downloads (\(openKJ.activeCount))", systemImage: "xmark.circle")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { openKJ.signOut() } label: {
                        Label("Disconnect from \(openKJ.host)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Download \(missing.count) songs?",
            isPresented: $confirmDownloadAll,
            titleVisibility: .visible
        ) {
            Button("Download \(missing.count)") { openKJ.download(missing) }
        } message: {
            Text("Songs you already have are skipped.")
        }
        .alert(
            "Download Failed",
            isPresented: Binding(get: { failedSong != nil }, set: { if !$0 { failedSong = nil } }),
            presenting: failedSong
        ) { song in
            Button("Retry") { openKJ.download([song]) }
            Button("Cancel", role: .cancel) {}
        } message: { song in
            if case .failed(let message) = openKJ.downloads[song.id] {
                Text(message)
            }
        }
    }

    private func tap(_ song: RemoteSong) {
        guard song.isPlayable else { return }
        switch openKJ.downloads[song.id] {
        case .queued, .downloading:
            openKJ.cancel(song)
        case .failed:
            failedSong = song
        case .done:
            break
        case nil:
            if !owned.contains(song.libraryKey) { openKJ.download([song]) }
        }
    }

    private func load(reset: Bool) async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let offset = reset ? 0 : results.count
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await openKJ.search(query, offset: offset)
            // A newer search has started since this one went out.
            guard query == searchText.trimmingCharacters(in: .whitespaces) else { return }
            results = reset ? page : results + page
            canLoadMore = page.count == OpenKJStore.pageSize
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            if reset { results = [] }
            canLoadMore = false
            errorMessage = error.localizedDescription
        }
    }
}

struct RemoteSongRow: View {
    let song: RemoteSong
    let isOwned: Bool
    let state: DownloadState?

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
            Text(song.formatLabel)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)
            status
                .frame(width: 28, height: 28)
        }
        .opacity(song.isPlayable ? 1 : 0.4)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .queued:
            ProgressRing(fraction: 0)
        case .downloading(let fraction):
            ProgressRing(fraction: fraction)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        case nil:
            if isOwned {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else if song.isPlayable {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// Download progress with a stop square in the middle, like the App Store's.
private struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(fraction, 0.02))
                .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: fraction)
            RoundedRectangle(cornerRadius: 2)
                .fill(.tint)
                .frame(width: 8, height: 8)
        }
        .padding(2)
    }
}
