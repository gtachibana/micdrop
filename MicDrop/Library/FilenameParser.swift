import Foundation

enum FilenameOrder: String, CaseIterable, Identifiable {
    case artistTitle
    case titleArtist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .artistTitle: return "Artist - Title"
        case .titleArtist: return "Title - Artist"
        }
    }
}

/// Extracts artist and title from karaoke file names such as
/// "Artist - Title", "SC8123-05 - Artist - Title" or "01 - Artist - Title".
enum FilenameParser {
    static func parse(_ baseName: String, order: FilenameOrder) -> (artist: String, title: String) {
        let cleaned = baseName.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        var parts = cleaned.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count >= 3, looksLikeDiscID(parts[0]) {
            parts.removeFirst()
        }
        guard parts.count >= 2 else { return ("", cleaned) }

        switch order {
        case .artistTitle:
            return (parts[0], parts.dropFirst().joined(separator: " - "))
        case .titleArtist:
            return (parts[parts.count - 1], parts.dropLast().joined(separator: " - "))
        }
    }

    /// Disc/track IDs like "SC8123-05", "SF001-01" or "01" contain digits and no spaces.
    private static func looksLikeDiscID(_ s: String) -> Bool {
        s.rangeOfCharacter(from: .decimalDigits) != nil && !s.contains(" ")
    }
}
