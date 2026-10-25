import Foundation
import Security

/// A song in the OpenKJ library, as `/local/admin/library` lists it.
struct RemoteSong: Identifiable, Decodable, Hashable {
    let id: Int
    let artist: String
    let title: String
    /// Lowercased extension of the file on the server; "cdg" is an MP3+CDG pair.
    let format: String
    let discID: String?

    enum CodingKeys: String, CodingKey {
        case id = "song_id", artist, title, format, discID = "discid"
    }

    /// OpenKJ sends MP3+CDG pairs as a single zip.
    var downloadExtension: String { format == LibraryScanner.cdgExtension ? LibraryScanner.zipExtension : format }

    var isPlayable: Bool {
        format == LibraryScanner.cdgExtension || format == LibraryScanner.zipExtension
            || LibraryScanner.videoExtensions.contains(format) || LibraryScanner.audioExtensions.contains(format)
    }

    var formatLabel: String { format.isEmpty ? "?" : format.uppercased() }

    /// Matches songs already in the library by artist and title, ignoring case and accents.
    var libraryKey: String { Self.libraryKey(artist: artist, title: title) }

    static func libraryKey(artist: String, title: String) -> String {
        func fold(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return fold(artist) + "|" + fold(title)
    }
}

enum DownloadState: Equatable {
    case queued
    case downloading(Double)
    case done
    case failed(String)

    var isActive: Bool {
        switch self {
        case .queued, .downloading: return true
        case .done, .failed: return false
        }
    }
}

enum OpenKJError: LocalizedError {
    case badAddress
    case notSignedIn
    case authExpired
    case server(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badAddress: return "That doesn't look like a server address."
        case .notSignedIn: return "Not connected to OpenKJ."
        case .authExpired: return "OpenKJ no longer accepts the saved password. Sign in again."
        case .server(let message): return message
        case .http(let code): return "OpenKJ answered with HTTP \(code)."
        }
    }
}

/// Browses and downloads songs from an OpenKJ server's Local Mode API, signed in as the KJ.
@MainActor
final class OpenKJStore: ObservableObject {
    static let shared = OpenKJStore()

    @Published private(set) var host: String
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var downloads: [Int: DownloadState] = [:]

    static let defaultPort = 5050
    static let pageSize = 200
    private static let maxConcurrentDownloads = 2
    private static let hostKey = "openkjHost"
    private static let tokenKey = "openkjToken"
    private static let passwordAccount = "openkj-admin"

    private var token: String?
    private var pending: [RemoteSong] = []
    /// Songs holding a download slot, including any still waiting on a sign-in.
    private var running: Set<Int> = []
    private var tasks: [Int: URLSessionDownloadTask] = [:]
    private var progressObservations: [Int: NSKeyValueObservation] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static var downloadFolder: URL {
        LibraryStore.documentsURL.appendingPathComponent("OpenKJ", isDirectory: true)
    }

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
        token = UserDefaults.standard.string(forKey: Self.tokenKey)
        isSignedIn = !host.isEmpty && Keychain.get(Self.passwordAccount) != nil
    }

    // MARK: - Session

    func signIn(host: String, password: String) async throws {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard let base = Self.baseURL(for: host) else { throw OpenKJError.badAddress }
        let token = try await login(base: base, password: password)
        self.host = host
        self.token = token
        isSignedIn = true
        UserDefaults.standard.set(host, forKey: Self.hostKey)
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        Keychain.set(password, for: Self.passwordAccount)
    }

    func signOut() {
        if let base = Self.baseURL(for: host), let token {
            var request = URLRequest(url: base.appending(path: "local/auth/logout"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["token": token])
            session.dataTask(with: request).resume()
        }
        cancelAll()
        token = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        Keychain.set(nil, for: Self.passwordAccount)
    }

    /// Accepts "192.168.1.20", "pc.local:5050" or a full http:// URL.
    static func baseURL(for host: String) -> URL? {
        var text = host.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text), components.host?.isEmpty == false else { return nil }
        if components.port == nil { components.port = defaultPort }
        components.path = ""
        components.query = nil
        return components.url
    }

    private func login(base: URL, password: String) async throws -> String {
        struct Reply: Decodable { let ok: Bool; let token: String?; let error: String? }
        var request = URLRequest(url: base.appending(path: "local/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["password": password])
        request.timeoutInterval = 10
        let reply: Reply = try await fetchJSON(request)
        guard reply.ok, let token = reply.token else { throw OpenKJError.server(reply.error ?? "Sign-in failed.") }
        return token
    }

    /// OpenKJ's admin sessions last a week, so a saved password lets an expired one renew quietly.
    private func currentToken(renew: Bool) async throws -> String {
        if !renew, let token { return token }
        guard isSignedIn, let base = Self.baseURL(for: host), let password = Keychain.get(Self.passwordAccount) else {
            throw OpenKJError.notSignedIn
        }
        do {
            let fresh = try await login(base: base, password: password)
            token = fresh
            UserDefaults.standard.set(fresh, forKey: Self.tokenKey)
            return fresh
        } catch OpenKJError.server {
            // The password itself was refused, so asking again is the only way forward.
            signOut()
            throw OpenKJError.authExpired
        }
    }

    // MARK: - Browsing

    func search(_ query: String, offset: Int = 0) async throws -> [RemoteSong] {
        struct Reply: Decodable { let ok: Bool; let songs: [RemoteSong]?; let error: String? }
        guard let base = Self.baseURL(for: host) else { throw OpenKJError.notSignedIn }

        for renew in [false, true] {
            let token = try await currentToken(renew: renew)
            var components = URLComponents(url: base.appending(path: "local/admin/library"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "token", value: token),
            ]
            // OpenKJ reads '+' as a space, the way browsers send one.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let reply: Reply = try await fetchJSON(URLRequest(url: components.url!))
            if reply.ok { return reply.songs ?? [] }
            if reply.error != Self.authRequiredMessage || renew {
                throw OpenKJError.server(reply.error ?? "OpenKJ couldn't search its library.")
            }
        }
        return []
    }

    private static let authRequiredMessage = "Admin authentication required"

    private func fetchJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenKJError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Downloading

    func download(_ songs: [RemoteSong]) {
        for song in songs where song.isPlayable && downloads[song.id]?.isActive != true {
            downloads[song.id] = .queued
            pending.append(song)
        }
        startPending()
    }

    func cancel(_ song: RemoteSong) {
        pending.removeAll { $0.id == song.id }
        tasks[song.id]?.cancel()
        downloads[song.id] = nil
    }

    func cancelAll() {
        pending.removeAll()
        tasks.values.forEach { $0.cancel() }
        downloads = downloads.filter { !$0.value.isActive }
    }

    var activeCount: Int { downloads.values.filter(\.isActive).count }

    private func startPending() {
        while running.count < Self.maxConcurrentDownloads, !pending.isEmpty {
            let song = pending.removeFirst()
            running.insert(song.id)
            Task { await self.run(song) }
        }
    }

    private func run(_ song: RemoteSong) async {
        defer {
            running.remove(song.id)
            tasks[song.id] = nil
            progressObservations[song.id] = nil
            startPending()
        }
        do {
            var file: URL?
            for renew in [false, true] {
                let token = try await currentToken(renew: renew)
                // Cancelled while the token was being fetched.
                guard downloads[song.id]?.isActive == true else { return }
                let (location, status) = try await fetchFile(song, token: token)
                if status == 200 {
                    file = location
                    break
                }
                // Errors come back as {"ok": false, "error": "..."}.
                struct Reply: Decodable { let error: String? }
                let message = (try? Data(contentsOf: location)).flatMap { try? JSONDecoder().decode(Reply.self, from: $0) }?.error
                try? FileManager.default.removeItem(at: location)
                if status != 401 || renew { throw message.map(OpenKJError.server) ?? OpenKJError.http(status) }
            }
            guard let file else { return }
            try save(file, for: song)
            downloads[song.id] = .done
            LibraryStore.shared.refresh()
        } catch let error as URLError where error.code == .cancelled {
            downloads[song.id] = nil
        } catch {
            downloads[song.id] = .failed(error.localizedDescription)
        }
    }

    /// Downloads to a temporary file and returns it with the HTTP status.
    private func fetchFile(_ song: RemoteSong, token: String) async throws -> (URL, Int) {
        guard let base = Self.baseURL(for: host) else { throw OpenKJError.notSignedIn }
        var components = URLComponents(url: base.appending(path: "local/admin/song-file"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(song.id)),
            URLQueryItem(name: "token", value: token),
        ]
        let songID = song.id
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: components.url!) { location, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let location, let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                // The system deletes the download as soon as this handler returns.
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: location, to: kept)
                    continuation.resume(returning: (kept, http.statusCode))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            let throttle = ProgressThrottle()
            progressObservations[songID] = task.progress.observe(\.fractionCompleted) { progress, _ in
                guard let fraction = throttle.next(progress.fractionCompleted) else { return }
                Task { @MainActor in
                    if OpenKJStore.shared.downloads[songID]?.isActive == true {
                        OpenKJStore.shared.downloads[songID] = .downloading(fraction)
                    }
                }
            }
            tasks[songID] = task
            downloads[songID] = .downloading(0)
            task.resume()
        }
    }

    private func save(_ file: URL, for song: RemoteSong) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.downloadFolder, withIntermediateDirectories: true)
        let destination = LibraryStore.uniqueDestination(for: Self.fileName(for: song), in: Self.downloadFolder)
        try fm.moveItem(at: file, to: destination)
    }

    /// Named the way the library's file name setting expects, so the scan reads artist and title back correctly.
    static func fileName(for song: RemoteSong) -> String {
        let artist = song.artist.trimmingCharacters(in: .whitespaces)
        let title = song.title.trimmingCharacters(in: .whitespaces)
        var base: String
        if artist.isEmpty {
            base = title
        } else {
            base = AppSettings.filenameOrder == .artistTitle ? "\(artist) - \(title)" : "\(title) - \(artist)"
        }
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        base = base.components(separatedBy: unsafe).joined(separator: "_")
        if base.isEmpty || base.hasPrefix(".") { base = "Song \(song.id)" }
        return "\(base).\(song.downloadExtension)"
    }
}

/// Lets through whole-percent changes only, so a fast download doesn't flood the main actor.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1

    func next(_ fraction: Double) -> Double? {
        let percent = Int(fraction * 100)
        lock.lock()
        defer { lock.unlock() }
        guard percent != last else { return nil }
        last = percent
        return Double(percent) / 100
    }
}

private enum Keychain {
    private static let service = "com.gtachibana.micdrop.openkj"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
