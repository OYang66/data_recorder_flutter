import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else {
      super.scene(scene, openURLContexts: URLContexts)
      return
    }
    if (UIApplication.shared.delegate as? AppDelegate)?.handleExternalDeliveryOrderUrl(url) == true {
      return
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
