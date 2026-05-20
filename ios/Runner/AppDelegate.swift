import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var legacyStorageChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerLegacyStorageChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerLegacyStorageChannel(messenger: FlutterBinaryMessenger) {
    legacyStorageChannel = FlutterMethodChannel(
      name: "com.example.datarecorder/legacy_storage",
      binaryMessenger: messenger
    )
    legacyStorageChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "readPreferences":
        guard let name = self.preferenceName(from: call) else {
          result([String: Any]())
          return
        }
        result(UserDefaults.standard.dictionary(forKey: self.preferenceKey(name)) ?? [String: Any]())
      case "writePreferences":
        guard let name = self.preferenceName(from: call),
              let arguments = call.arguments as? [String: Any],
              let values = arguments["values"] as? [String: Any] else {
          result(false)
          return
        }
        var stored = UserDefaults.standard.dictionary(forKey: self.preferenceKey(name)) ?? [String: Any]()
        values.forEach { key, value in stored[key] = value }
        UserDefaults.standard.set(stored, forKey: self.preferenceKey(name))
        result(true)
      case "removePreferences":
        guard let name = self.preferenceName(from: call),
              let arguments = call.arguments as? [String: Any],
              let keys = arguments["keys"] as? [String] else {
          result(false)
          return
        }
        var stored = UserDefaults.standard.dictionary(forKey: self.preferenceKey(name)) ?? [String: Any]()
        keys.forEach { stored.removeValue(forKey: $0) }
        UserDefaults.standard.set(stored, forKey: self.preferenceKey(name))
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func preferenceName(from call: FlutterMethodCall) -> String? {
    guard let arguments = call.arguments as? [String: Any],
          let name = arguments["name"] as? String,
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return name
  }

  private func preferenceKey(_ name: String) -> String {
    return "legacy_storage.\(name)"
  }
}
