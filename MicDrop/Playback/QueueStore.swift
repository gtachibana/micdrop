import Foundation

@MainActor
final class QueueStore: ObservableObject {
    static let shared = QueueStore()

    @Published private(set) var entries: [QueueEntry] = [] {
        didSet { save() }
    }

    private struct StoredEntry: Codable {
        let id: UUID
        let songID: String
        let singer: String
    }

    private var pendingRestore: [StoredEntry]?

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queue.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            pendingRestore = try? JSONDecoder().decode([StoredEntry].self, from: data)
        }
    }

    /// The saved queue refers to songs by ID, so it can only be rebuilt after a library scan.
    func restoreIfNeeded(from library: LibraryStore) {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        let restored = pending.compactMap { stored in
            library.song(withID: stored.songID).map { QueueEntry(id: stored.id, song: $0, singer: stored.singer) }
        }
        entries = restored + entries
    }

    func add(_ song: Song, singer: String = "") {
        entries.append(QueueEntry(song: song, singer: singer))
    }

    func addNext(_ song: Song, singer: String = "") {
        entries.insert(QueueEntry(song: song, singer: singer), at: 0)
    }

    func popFirst() -> QueueEntry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    func remove(_ entry: QueueEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func remove(atOffsets offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    func setSinger(_ singer: String, for entry: QueueEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].singer = singer
    }

    func clear() {
        entries = []
    }

    private func save() {
        guard pendingRestore == nil else { return }
        let stored = entries.map { StoredEntry(id: $0.id, songID: $0.song.id, singer: $0.singer) }
        do {
            let url = Self.fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: .atomic)
        } catch {
            // The queue is a convenience; losing it isn't worth interrupting the user.
        }
    }
}
