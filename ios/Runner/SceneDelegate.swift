import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    private var privacyCover: UIView?

    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        guard let windowScene = scene as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else {
            return
        }

        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = UIColor.systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle"))
        icon.tintColor = UIColor.secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
        ])

        privacyCover?.removeFromSuperview()
        privacyCover = cover
        window.addSubview(cover)
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        privacyCover?.removeFromSuperview()
        privacyCover = nil
    }
}
