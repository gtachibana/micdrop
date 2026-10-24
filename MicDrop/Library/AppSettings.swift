import Foundation

enum SettingsKey {
    static let autoAdvance = "autoAdvance"
    static let keepAwake = "keepAwake"
    static let lyricsOffset = "lyricsOffset"
    static let filenameOrder = "filenameOrder"
    static let librarySort = "librarySort"
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static var autoAdvance: Bool {
        defaults.object(forKey: SettingsKey.autoAdvance) as? Bool ?? true
    }

    static var keepAwake: Bool {
        defaults.object(forKey: SettingsKey.keepAwake) as? Bool ?? true
    }

    /// Seconds to shift CD+G graphics relative to the audio; positive shows lyrics earlier.
    static var lyricsOffset: Double {
        defaults.double(forKey: SettingsKey.lyricsOffset)
    }

    static var filenameOrder: FilenameOrder {
        FilenameOrder(rawValue: defaults.string(forKey: SettingsKey.filenameOrder) ?? "") ?? .artistTitle
    }
}
