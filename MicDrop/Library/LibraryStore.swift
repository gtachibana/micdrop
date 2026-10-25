import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var songs: [Song] = []
    @Published private(set) var songsByTitle: [Song] = []
    @Published private(set) var isScanning = false
    @Published private(set) var folders: [LinkedFolder] = []
    @Published var lastError: String?

    private var songsByID: [String: Song] = [:]
    private var accessedFolders: [UUID: URL] = [:]
    private var rescanRequested = false
    private var scanWaiters: [CheckedContinuation<Void, Never>] = []

    private static let foldersKey = "linkedFolders"

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.foldersKey),
           let saved = try? JSONDecoder().decode([LinkedFolder].self, from: data) {
            folders = saved
        }
    }

    func song(withID id: String) -> Song? { songsByID[id] }

    // MARK: - Scanning

    func refresh() {
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        let order = AppSettings.filenameOrder
        var roots: [(URL, String)] = [(Self.documentsURL, LibraryScanner.documentsSourceID)]
        for folder in folders {
            if let url = resolve(folder) { roots.append((url, folder.id.uuidString)) }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var all: [Song] = []
            for (url, sourceID) in roots {
                all += LibraryScanner.scan(root: url, sourceID: sourceID, order: order)
            }
            let byArtist = all.sorted(by: Self.artistOrder)
            let byTitle = all.sorted(by: Self.titleOrder)
            DispatchQueue.main.async {
                self.finishScan(byArtist: byArtist, byTitle: byTitle)
            }
        }
    }

    func refreshAndWait() async {
        await withCheckedContinuation { continuation in
            scanWaiters.append(continuation)
            refresh()
        }
    }

    private func finishScan(byArtist: [Song], byTitle: [Song]) {
        songs = byArtist
        songsByTitle = byTitle
        songsByID = Dictionary(byArtist.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        isScanning = false
        QueueStore.shared.restoreIfNeeded(from: self)

        if rescanRequested {
            rescanRequested = false
            refresh()
        } else {
            let waiters = scanWaiters
            scanWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated private static func artistOrder(_ a: Song, _ b: Song) -> Bool {
        let artistA = a.artist.isEmpty ? a.title : a.artist
        let artistB = b.artist.isEmpty ? b.title : b.artist
        let c = artistA.localizedStandardCompare(artistB)
        if c != .orderedSame { return c == .orderedAscending }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    nonisolated private static func titleOrder(_ a: Song, _ b: Song) -> Bool {
        let c = a.title.localizedStandardCompare(b.title)
        if c != .orderedSame { return c == .orderedAscending }
        return a.artist.localizedStandardCompare(b.artist) == .orderedAscending
    }

    // MARK: - Importing

    /// Copies picked or shared files/folders into the app's Documents folder.
    func importItems(_ urls: [URL]) {
        let documents = Self.documentsURL
        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if url.standardizedFileURL.path.hasPrefix(documents.standardizedFileURL.path) { continue }
                do {
                    try FileManager.default.copyItem(at: url, to: Self.uniqueDestination(for: url.lastPathComponent, in: documents))
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                if !failures.isEmpty { self.lastError = failures.joined(separator: "\n") }
                self.refresh()
            }
        }
    }

    nonisolated static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            n += 1
        }
        return candidate
    }

    func delete(_ song: Song) {
        guard song.isInAppDocuments else { return }
        do {
            try FileManager.default.removeItem(at: song.mediaURL)
            if let cdg = song.cdgURL { try? FileManager.default.removeItem(at: cdg) }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    // MARK: - Linked folders

    /// Links a folder (Files app, iCloud Drive, USB drive…) without copying its contents.
    func linkFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let folder = LinkedFolder(id: UUID(), name: url.lastPathComponent, bookmark: bookmark)
            if scoped { accessedFolders[folder.id] = url }
            folders.append(folder)
            saveFolders()
            refresh()
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            lastError = "Couldn't link \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func unlinkFolders(at offsets: IndexSet) {
        for index in offsets {
            let folder = folders[index]
            accessedFolders.removeValue(forKey: folder.id)?.stopAccessingSecurityScopedResource()
        }
        folders.remove(atOffsets: offsets)
        saveFolders()
        refresh()
    }

    private func resolve(_ folder: LinkedFolder) -> URL? {
        if let url = accessedFolders[folder.id] { return url }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if url.startAccessingSecurityScopedResource() {
            accessedFolders[folder.id] = url
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
           let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index].bookmark = fresh
            saveFolders()
        }
        return url
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.foldersKey)
        }
    }
}
