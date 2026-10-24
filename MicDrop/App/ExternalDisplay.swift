import SwiftUI
import UIKit

/// Drives a TV connected by AirPlay screen mirroring or an HDMI adapter.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let host = UIHostingController(rootView: ExternalStageView()
            .environmentObject(PlayerController.shared)
            .environmentObject(QueueStore.shared))
        host.view.backgroundColor = .black
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        PlayerController.shared.externalDisplayConnected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        PlayerController.shared.externalDisplayConnected = false
    }
}

struct ExternalStageView: View {
    var body: some View {
        StageView(showsQueueWhenIdle: true)
            .ignoresSafeArea()
    }
}
