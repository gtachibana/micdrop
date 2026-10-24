import Foundation
import ZIPFoundation

enum ResolvedMedia {
    case cdg(audio: URL, cdg: URL)
    case video(URL)
    case audio(URL)
}

enum MediaError: LocalizedError {
    case missingCDG
    case nothingPlayableInArchive(String)

    var errorDescription: String? {
        switch self {
        case .missingCDG:
            return "The .cdg file for this song is missing."
        case .nothingPlayableInArchive(let name):
            return "\(name) doesn't contain a playable song (expected an audio file + .cdg, or a video)."
        }
    }
}

/// Turns a library Song into local files ready to play: downloads iCloud files and
/// extracts zipped MP3+CDG pairs. Runs synchronously; call it off the main thread.
enum MediaResolver {
    static var extractionRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Extracted", isDirectory: true)
    }

    static func clearExtractionCache() {
        try? FileManager.default.removeItem(at: extractionRoot)
    }

    static func resolve(_ song: Song) throws -> ResolvedMedia {
        switch song.kind {
        case .cdg:
            guard let cdg = song.cdgURL else { throw MediaError.missingCDG }
            try ensureLocal(song.mediaURL)
            try ensureLocal(cdg)
            return .cdg(audio: song.mediaURL, cdg: cdg)
        case .video:
            try ensureLocal(song.mediaURL)
            return .video(song.mediaURL)
        case .audio:
            try ensureLocal(song.mediaURL)
            return .audio(song.mediaURL)
        case .zip:
            return try extract(song.mediaURL)
        }
    }

    /// Coordinated reads make iCloud Drive / File Provider download the file if needed.
    private static func ensureLocal(_ url: URL) throws {
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { _ in }
        if let coordinatorError { throw coordinatorError }
    }

    private static func extract(_ zipURL: URL) throws -> ResolvedMedia {
        try ensureLocal(zipURL)
        let fm = FileManager.default
        let destination = extractionRoot.appendingPathComponent(stableHash(zipURL.path), isDirectory: true)

        if !fm.fileExists(atPath: destination.path) {
            let temp = extractionRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            do {
                try fm.unzipItem(at: zipURL, to: temp)
                try fm.moveItem(at: temp, to: destination)
            } catch {
                try? fm.removeItem(at: temp)
                throw error
            }
        }

        let files = (fm.enumerator(at: destination, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { !$0.path.contains("__MACOSX") && !$0.lastPathComponent.hasPrefix(".") }
        func ext(_ url: URL) -> String { url.pathExtension.lowercased() }
        func base(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent.lowercased() }
        let audio = files.filter { LibraryScanner.audioExtensions.contains(ext($0)) }
        let cdgs = files.filter { ext($0) == LibraryScanner.cdgExtension }

        for cdg in cdgs {
            if let match = audio.first(where: { base($0) == base(cdg) }) {
                return .cdg(audio: match, cdg: cdg)
            }
        }
        if let cdg = cdgs.first, let first = audio.first {
            return .cdg(audio: first, cdg: cdg)
        }
        if let video = files.first(where: { LibraryScanner.videoExtensions.contains(ext($0)) }) {
            return .video(video)
        }
        if let first = audio.first {
            return .audio(first)
        }
        throw MediaError.nothingPlayableInArchive(zipURL.lastPathComponent)
    }

    /// FNV-1a; String.hashValue is randomized per launch so can't be used for cache keys.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
