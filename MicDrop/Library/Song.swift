import Foundation

enum SongKind: String, Codable {
    case cdg, zip, video, audio

    var label: String {
        switch self {
        case .cdg: return "CDG"
        case .zip: return "ZIP"
        case .video: return "VIDEO"
        case .audio: return "AUDIO"
        }
    }

    var symbol: String {
        switch self {
        case .cdg, .zip: return "music.mic"
        case .video: return "film"
        case .audio: return "music.note"
        }
    }
}

struct Song: Identifiable, Hashable {
    /// Stable key, "<source id>/<relative path>", so queues survive rescans and reinstalls.
    let id: String
    let kind: SongKind
    /// The audio file for CDG songs; otherwise the zip, video or audio file itself.
    let mediaURL: URL
    let cdgURL: URL?
    let artist: String
    let title: String
    let fileName: String
    let searchText: String

    init(id: String, kind: SongKind, mediaURL: URL, cdgURL: URL? = nil, artist: String, title: String, fileName: String) {
        self.id = id
        self.kind = kind
        self.mediaURL = mediaURL
        self.cdgURL = cdgURL
        self.artist = artist
        self.title = title
        self.fileName = fileName
        searchText = "\(artist) \(title) \(fileName)".lowercased()
    }

    var isInAppDocuments: Bool { id.hasPrefix(LibraryScanner.documentsSourceID + "/") }
}

struct QueueEntry: Identifiable, Hashable {
    let id: UUID
    let song: Song
    var singer: String

    init(id: UUID = UUID(), song: Song, singer: String = "") {
        self.id = id
        self.song = song
        self.singer = singer
    }
}

struct LinkedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bookmark: Data
}
