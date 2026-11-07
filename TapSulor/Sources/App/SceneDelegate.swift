import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let coordinator = AppCoordinator()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let mainController = MainViewController(coordinator: coordinator)
        coordinator.attach(mainController)
        window.backgroundColor = UIColor(red: 0.957, green: 0.969, blue: 0.984, alpha: 1)
        window.rootViewController = mainController
        window.makeKeyAndVisible()
        self.window = window
        coordinator.start()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        coordinator.appDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        coordinator.appWillResignActive()
    }
}
