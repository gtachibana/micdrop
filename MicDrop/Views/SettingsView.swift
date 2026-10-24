import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = true
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @AppStorage(SettingsKey.lyricsOffset) private var lyricsOffset = 0.0
    @AppStorage(SettingsKey.filenameOrder) private var filenameOrder: FilenameOrder = .artistTitle

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-play next in queue", isOn: $autoAdvance)
                    Toggle("Keep screen awake while playing", isOn: $keepAwake)
                    Stepper(value: $lyricsOffset, in: -2...2, step: 0.05) {
                        LabeledContent("CDG lyrics offset", value: String(format: "%+.2f s", lyricsOffset))
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("A positive offset shows CD+G lyrics earlier. Useful with Bluetooth speakers, which add audio delay.")
                }

                Section {
                    Picker("File names are", selection: $filenameOrder) {
                        ForEach(FilenameOrder.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Songs", value: "\(library.songs.count)")
                    LabeledContent("Linked folders", value: "\(library.folders.count)")
                } header: {
                    Text("Library")
                } footer: {
                    Text("Disc IDs at the start of a name, like \"SC8123-05 - \", are ignored.")
                }

                Section("Using a TV") {
                    Text("Connect with AirPlay Screen Mirroring (Control Center › Screen Mirroring) or an HDMI adapter. The TV shows only the lyrics or video, full screen, while your phone stays the remote. Between songs the TV shows who's up next.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: filenameOrder) { _, _ in library.refresh() }
        }
        .miniPlayerInset()
    }
}
