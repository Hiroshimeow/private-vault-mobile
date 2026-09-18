import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "private_vault/platform",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }

      switch call.method {
      case "getDisguiseCapabilities":
        result([
          "androidLauncherAliases": false,
          "iosAlternateIcons": UIApplication.shared.supportsAlternateIcons,
        ])
      case "setDisguise":
        guard let choice = call.arguments as? String else {
          result(
            FlutterError(
              code: "invalid_choice",
              message: "Unknown disguise choice",
              details: nil
            )
          )
          return
        }
        self.setDisguise(choice, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setDisguise(_ choice: String, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(false)
      return
    }

    let iconName: String?
    switch choice {
    case "calculator":
      iconName = nil
    case "notes":
      iconName = "NotesIcon"
    default:
      result(
        FlutterError(
          code: "invalid_choice",
          message: "Unknown disguise choice",
          details: nil
        )
      )
      return
    }

    UIApplication.shared.setAlternateIconName(iconName) { error in
      result(error == nil)
    }
  }
}
