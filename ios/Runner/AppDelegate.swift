import AVFoundation
import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var legacyStorageChannel: FlutterMethodChannel?
  private var updateChannel: FlutterMethodChannel?
  private var fastVoiceChannel: FlutterMethodChannel?
  private let fastSpeechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
  private let fastAudioEngine = AVAudioEngine()
  private var fastRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var fastRecognitionTask: SFSpeechRecognitionTask?
  private var fastVoiceBestText = ""
  private var fastVoiceListening = false
  private var fastAudioTapInstalled = false
  private var fastVoiceStopResult: FlutterResult?
  private var fastVoiceFallbackWorkItem: DispatchWorkItem?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerLegacyStorageChannel(messenger: messenger)
    registerUpdateChannel(messenger: messenger)
    registerFastVoiceChannel(messenger: messenger)
  }

  private func registerFastVoiceChannel(messenger: FlutterBinaryMessenger) {
    fastVoiceChannel = FlutterMethodChannel(
      name: "com.example.datarecorder/fast_voice",
      binaryMessenger: messenger
    )
    fastVoiceChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "startListening":
        self.startFastVoiceListening(result: result)
      case "stopListening":
        self.stopFastVoiceListening(result: result)
      case "cancelListening":
        self.cancelFastVoiceListening(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startFastVoiceListening(result: @escaping FlutterResult) {
    if fastVoiceListening {
      result(nil)
      return
    }
    guard let recognizer = fastSpeechRecognizer, recognizer.isAvailable else {
      result(FlutterError(code: "unavailable", message: "当前设备不支持系统语音识别", details: nil))
      return
    }
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          result(FlutterError(code: "speech_permission_denied", message: "未授予语音识别权限", details: nil))
          return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async {
            guard granted else {
              result(FlutterError(code: "permission_denied", message: "未授予录音权限，无法使用语音识别", details: nil))
              return
            }
            self.beginFastVoiceListening(recognizer: recognizer, result: result)
          }
        }
      }
    }
  }

  private func beginFastVoiceListening(
    recognizer: SFSpeechRecognizer,
    result: @escaping FlutterResult
  ) {
    do {
      cleanupFastVoiceRecognition(cancelTask: true)
      fastVoiceBestText = ""
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      fastRecognitionRequest = request
      let inputNode = fastAudioEngine.inputNode
      let format = inputNode.outputFormat(forBus: 0)
      removeFastVoiceAudioTap()
      inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
      }
      fastAudioTapInstalled = true
      fastAudioEngine.prepare()
      try fastAudioEngine.start()
      fastVoiceListening = true
      fastRecognitionTask = recognizer.recognitionTask(with: request) { recognitionResult, error in
        DispatchQueue.main.async {
          if let recognitionResult = recognitionResult {
            self.fastVoiceBestText = recognitionResult.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if recognitionResult.isFinal {
              self.completeFastVoiceResult(self.fastVoiceBestText)
            }
          }
          if error != nil && self.fastVoiceStopResult != nil {
            self.completeFastVoiceResult(self.fastVoiceBestText)
          }
        }
      }
      result(nil)
    } catch {
      cleanupFastVoiceRecognition(cancelTask: true)
      result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func stopFastVoiceListening(result: @escaping FlutterResult) {
    if fastVoiceStopResult != nil {
      result("")
      return
    }
    fastVoiceStopResult = result
    guard fastVoiceListening else {
      completeFastVoiceResult(fastVoiceBestText)
      return
    }
    fastVoiceListening = false
    if fastAudioEngine.isRunning {
      fastAudioEngine.stop()
      removeFastVoiceAudioTap()
    }
    fastRecognitionRequest?.endAudio()
    let fallback = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.completeFastVoiceResult(self.fastVoiceBestText)
    }
    fastVoiceFallbackWorkItem = fallback
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: fallback)
  }

  private func cancelFastVoiceListening(result: FlutterResult) {
    cleanupFastVoiceRecognition(cancelTask: true)
    result(nil)
  }

  private func completeFastVoiceResult(_ text: String) {
    fastVoiceFallbackWorkItem?.cancel()
    fastVoiceFallbackWorkItem = nil
    let result = fastVoiceStopResult
    fastVoiceStopResult = nil
    cleanupFastVoiceRecognition(cancelTask: false)
    result?(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func removeFastVoiceAudioTap() {
    if fastAudioTapInstalled {
      fastAudioEngine.inputNode.removeTap(onBus: 0)
      fastAudioTapInstalled = false
    }
  }

  private func cleanupFastVoiceRecognition(cancelTask: Bool) {
    fastVoiceFallbackWorkItem?.cancel()
    fastVoiceFallbackWorkItem = nil
    if fastAudioEngine.isRunning {
      fastAudioEngine.stop()
    }
    removeFastVoiceAudioTap()
    if cancelTask {
      fastRecognitionTask?.cancel()
    }
    fastRecognitionTask = nil
    fastRecognitionRequest = nil
    fastVoiceListening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func registerUpdateChannel(messenger: FlutterBinaryMessenger) {
    updateChannel = FlutterMethodChannel(
      name: "com.example.datarecorder/update",
      binaryMessenger: messenger
    )
    updateChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "openUrl":
        guard let arguments = call.arguments as? [String: Any],
              let urlString = arguments["url"] as? String,
              let url = URL(string: urlString) else {
          result(FlutterError(code: "invalid_url", message: "链接地址无效", details: nil))
          return
        }
        UIApplication.shared.open(url) { success in
          result(success)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
