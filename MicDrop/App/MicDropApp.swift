import AVFoundation
import SwiftUI

@main
struct MicDropApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(LibraryStore.shared)
                .environmentObject(QueueStore.shared)
                .environmentObject(PlayerController.shared)
                .onOpenURL { url in
                    LibraryStore.shared.importItems([url])
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up files added through the Files app while we were in the background.
            if phase == .active { LibraryStore.shared.refresh() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        DispatchQueue.global(qos: .utility).async {
            MediaResolver.clearExtractionCache()
            Self.createReadmeIfEmpty()
        }
        return true
    }

    /// Gives the TV its own scene (showing just the lyrics/video) instead of mirroring the phone UI.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            config.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return config
    }

    /// The app's folder only shows up under "On My iPhone" in Files once it has something in it.
    nonisolated private static func createReadmeIfEmpty() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        guard contents.isEmpty else { return }
        let text = """
        Put your karaoke files in this folder (subfolders are fine).

        Supported: MP3+CDG pairs with matching names, zipped MP3+CDG, MP4/M4V/MOV video, and plain audio.
        Name files "Artist - Title" (an optional disc ID prefix like "SC8123-05 - " is ignored).
        """
        try? text.write(to: documents.appendingPathComponent("Put karaoke files here.txt"), atomically: true, encoding: .utf8)
    }
}
