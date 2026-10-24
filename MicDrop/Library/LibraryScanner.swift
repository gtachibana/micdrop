import Foundation

enum LibraryScanner {
    static let documentsSourceID = "docs"

    /// Audio formats that can accompany a .cdg file, in order of preference.
    static let audioExtensions = ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf"]
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]
    static let zipExtension = "zip"
    static let cdgExtension = "cdg"

    private static let knownExtensions: Set<String> =
        Set(audioExtensions).union(videoExtensions).union([zipExtension, cdgExtension])

    private struct Group {
        let baseName: String
        var files: [String: URL] = [:]
    }

    /// Recursively scans a folder and pairs up files that share a base name
    /// (e.g. "Song.mp3" + "Song.cdg") into songs.
    static func scan(root: URL, sourceID: String, order: FilenameOrder) -> [Song] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        let rootPath = normalizedPath(root)
        var groups: [String: Group] = [:]

        for case let url as URL in enumerator {
            var name = url.lastPathComponent
            var fileURL = url
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true

            if name.hasPrefix(".") {
                // iCloud Drive files that aren't downloaded yet appear as ".Name.ext.icloud".
                guard !isDirectory, name.hasSuffix(".icloud") else {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                name = String(name.dropFirst().dropLast(".icloud".count))
                fileURL = url.deletingLastPathComponent().appendingPathComponent(name)
            }
            guard !isDirectory else { continue }

            let ext = (name as NSString).pathExtension.lowercased()
            guard knownExtensions.contains(ext) else { continue }
            let base = (name as NSString).deletingPathExtension
            let key = fileURL.deletingLastPathComponent().path + "/" + base.lowercased()
            groups[key, default: Group(baseName: base)].files[ext] = fileURL
        }

        var songs: [Song] = []
        for group in groups.values {
            let (artist, title) = FilenameParser.parse(group.baseName, order: order)

            func makeSong(_ kind: SongKind, _ url: URL, cdg: URL? = nil) -> Song {
                Song(
                    id: sourceID + "/" + relativePath(of: url, rootPath: rootPath),
                    kind: kind,
                    mediaURL: url,
                    cdgURL: cdg,
                    artist: artist,
                    title: title,
                    fileName: url.lastPathComponent
                )
            }

            let cdg = group.files[cdgExtension]
            let cdgAudio = audioExtensions.first { group.files[$0] != nil }
            if let cdg, let cdgAudio, let audioURL = group.files[cdgAudio] {
                songs.append(makeSong(.cdg, audioURL, cdg: cdg))
            }
            for (ext, url) in group.files {
                if videoExtensions.contains(ext) {
                    songs.append(makeSong(.video, url))
                } else if ext == zipExtension {
                    songs.append(makeSong(.zip, url))
                } else if cdg == nil, audioExtensions.contains(ext) {
                    songs.append(makeSong(.audio, url))
                }
            }
        }
        return songs
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return path
    }

    private static func relativePath(of url: URL, rootPath: String) -> String {
        let path = normalizedPath(url)
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
