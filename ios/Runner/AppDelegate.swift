import AVFoundation
import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var legacyStorageChannel: FlutterMethodChannel?
  private var updateChannel: FlutterMethodChannel?
  private var fastVoiceChannel: FlutterMethodChannel?
  private var exportShareChannel: FlutterMethodChannel?
  private var deliveryOrderIntakeChannel: FlutterMethodChannel?
  private var pendingDocumentPickerResult: FlutterResult?
  private var pendingDeliveryOrderFile: [String: Any]?
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

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return handleExternalDeliveryOrderUrl(url)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerLegacyStorageChannel(messenger: messenger)
    registerUpdateChannel(messenger: messenger)
    registerFastVoiceChannel(messenger: messenger)
    registerExportShareChannel(messenger: messenger)
    registerDeliveryOrderIntakeChannel(messenger: messenger)
  }

  @discardableResult
  func handleExternalDeliveryOrderUrl(_ url: URL) -> Bool {
    guard isSupportedDeliveryOrderFile(url) else {
      return false
    }
    do {
      let path = try copyUrlToCache(url)
      let payload: [String: Any] = [
        "path": path,
        "fileName": URL(fileURLWithPath: path).lastPathComponent,
        "source": "ios_open_in"
      ]
      pendingDeliveryOrderFile = payload
      notifyDeliveryOrderFile(payload)
      return true
    } catch {
      return false
    }
  }

  private func registerDeliveryOrderIntakeChannel(messenger: FlutterBinaryMessenger) {
    deliveryOrderIntakeChannel = FlutterMethodChannel(
      name: "com.example.datarecorder/delivery_order_intake",
      binaryMessenger: messenger
    )
    deliveryOrderIntakeChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "getInitialDeliveryOrderFile":
        let file = self.pendingDeliveryOrderFile
        self.pendingDeliveryOrderFile = nil
        result(file)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    if let pendingDeliveryOrderFile = pendingDeliveryOrderFile {
      notifyDeliveryOrderFile(pendingDeliveryOrderFile)
    }
  }

  private func notifyDeliveryOrderFile(_ payload: [String: Any]) {
    DispatchQueue.main.async {
      self.deliveryOrderIntakeChannel?.invokeMethod("onDeliveryOrderFile", arguments: payload)
    }
  }

  private func registerExportShareChannel(messenger: FlutterBinaryMessenger) {
    exportShareChannel = FlutterMethodChannel(
      name: "com.example.datarecorder/export_share",
      binaryMessenger: messenger
    )
    exportShareChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "shareTextFile":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "分享参数无效", details: nil))
          return
        }
        let fileName = self.stringArgument(arguments, "fileName", fallback: "export.txt")
        let content = self.stringArgument(arguments, "content", fallback: "")
        let title = self.stringArgument(arguments, "title", fallback: "分享文件")
        do {
          let path = try self.saveFile(fileName: fileName, data: Data(content.utf8))
          self.shareFile(path: path, title: title, result: result)
        } catch {
          result(FlutterError(code: "share_failed", message: error.localizedDescription, details: nil))
        }
      case "shareBytesFile":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "分享参数无效", details: nil))
          return
        }
        let fileName = self.stringArgument(arguments, "fileName", fallback: "export.xlsx")
        let title = self.stringArgument(arguments, "title", fallback: "分享文件")
        do {
          let data = try self.dataArgument(arguments, "bytes")
          let path = try self.saveFile(fileName: fileName, data: data)
          self.shareFile(path: path, title: title, result: result)
        } catch {
          result(FlutterError(code: "share_failed", message: error.localizedDescription, details: nil))
        }
      case "saveBytesFile":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "保存参数无效", details: nil))
          return
        }
        do {
          let fileName = self.stringArgument(arguments, "fileName", fallback: "export.xlsx")
          let data = try self.dataArgument(arguments, "bytes")
          result(try self.saveFile(fileName: fileName, data: data))
        } catch {
          result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
        }
      case "saveHistory":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "历史备份参数无效", details: nil))
          return
        }
        do {
          let fileName = self.stringArgument(arguments, "fileName", fallback: "history.json")
          let content = self.stringArgument(arguments, "content", fallback: "{}")
          result(try self.saveHistory(fileName: fileName, content: content))
        } catch {
          result(FlutterError(code: "history_save_failed", message: error.localizedDescription, details: nil))
        }
      case "listHistory":
        result(self.listHistory())
      case "readHistory":
        guard let arguments = call.arguments as? [String: Any] else {
          result("")
          return
        }
        result(self.readTextFile(path: self.stringArgument(arguments, "path", fallback: "")))
      case "deleteHistory":
        guard let arguments = call.arguments as? [String: Any] else {
          result(false)
          return
        }
        result(self.deleteFile(path: self.stringArgument(arguments, "path", fallback: "")))
      case "readBytesBase64":
        guard let arguments = call.arguments as? [String: Any] else {
          result("")
          return
        }
        result(self.readBytesBase64(uriString: self.stringArgument(arguments, "uri", fallback: "")))
      case "pickDeliveryOrderFile":
        self.pickDeliveryOrderFile(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func stringArgument(_ arguments: [String: Any], _ key: String, fallback: String) -> String {
    guard let value = arguments[key] as? String else {
      return fallback
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : value
  }

  private func dataArgument(_ arguments: [String: Any], _ key: String) throws -> Data {
    if let typedData = arguments[key] as? FlutterStandardTypedData {
      return typedData.data
    }
    if let data = arguments[key] as? Data {
      return data
    }
    if let bytes = arguments[key] as? [UInt8] {
      return Data(bytes)
    }
    throw NSError(domain: "DataRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件内容为空或格式无效"])
  }

  private func safeFileName(_ fileName: String) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let components = fileName.components(separatedBy: invalid)
    let safe = components.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    return safe.isEmpty ? "export_\(Int(Date().timeIntervalSince1970)).dat" : safe
  }

  private func saveFile(fileName: String, data: Data) throws -> String {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appendingPathComponent(safeFileName(fileName))
    try data.write(to: url, options: .atomic)
    return url.path
  }

  private func shareFile(path: String, title: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        result(FlutterError(code: "share_failed", message: "无法打开系统分享面板", details: nil))
        return
      }
      let controller = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
      controller.title = title
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      presenter.present(controller, animated: true) {
        result(nil)
      }
    }
  }

  private func pickDeliveryOrderFile(result: @escaping FlutterResult) {
    if pendingDocumentPickerResult != nil {
      result("")
      return
    }
    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        result(FlutterError(code: "picker_failed", message: "无法打开文件选择器", details: nil))
        return
      }
      self.pendingDocumentPickerResult = result
      let picker = UIDocumentPickerViewController(
        documentTypes: [
          "com.microsoft.excel.xls",
          "org.openxmlformats.spreadsheetml.sheet",
          "public.zip-archive",
          "com.pkware.zip-archive",
          "public.data"
        ],
        in: .import
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      presenter.present(picker, animated: true)
    }
  }

  private func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController
  ) -> UIViewController? {
    if let navigation = base as? UINavigationController {
      return topViewController(base: navigation.visibleViewController)
    }
    if let tab = base as? UITabBarController,
       let selected = tab.selectedViewController {
      return topViewController(base: selected)
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }

  private func isSupportedDeliveryOrderFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == "xlsx" || ext == "xls" || ext == "zip"
  }

  private func copyUrlToCache(_ url: URL) throws -> String {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }
    let fileName = safeFileName(url.lastPathComponent.isEmpty ? "delivery_order_\(Int(Date().timeIntervalSince1970)).xlsx" : url.lastPathComponent)
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: url, to: destination)
    return destination.path
  }

  private func historyDirectory() throws -> URL {
    let directory = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("history", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func saveHistory(fileName: String, content: String) throws -> String {
    let directory = try historyDirectory()
    let url = directory.appendingPathComponent(safeFileName(fileName))
    try content.write(to: url, atomically: true, encoding: .utf8)
    trimHistoryBackups(fileName: url.lastPathComponent, keepCount: 5)
    return url.path
  }

  private func trimHistoryBackups(fileName: String, keepCount: Int) {
    guard let directory = try? historyDirectory() else {
      return
    }
    let marker = "_历史数据自动备份_"
    let prefix = fileName.components(separatedBy: marker).first ?? ""
    guard !prefix.isEmpty else {
      return
    }
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    let matched = files.filter { url in
      url.lastPathComponent.hasPrefix("\(prefix)\(marker)") && url.pathExtension == "json"
    }.sorted { lhs, rhs in
      let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return leftDate > rightDate
    }
    matched.dropFirst(keepCount).forEach { try? FileManager.default.removeItem(at: $0) }
  }

  private func listHistory() -> [[String: Any]] {
    guard let directory = try? historyDirectory() else {
      return []
    }
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    return files.filter { $0.pathExtension == "json" }.compactMap { url in
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      return [
        "name": url.lastPathComponent,
        "path": url.path,
        "modified": Int64((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000),
        "size": values?.fileSize ?? 0
      ]
    }.sorted { lhs, rhs in
      (lhs["modified"] as? Int64 ?? 0) > (rhs["modified"] as? Int64 ?? 0)
    }
  }

  private func readTextFile(path: String) -> String {
    guard !path.isEmpty else {
      return ""
    }
    return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
  }

  private func deleteFile(path: String) -> Bool {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return false
    }
    do {
      try FileManager.default.removeItem(atPath: path)
      return true
    } catch {
      return false
    }
  }

  private func readBytesBase64(uriString: String) -> String {
    guard !uriString.isEmpty else {
      return ""
    }
    do {
      let url: URL
      if uriString.hasPrefix("file://"), let parsed = URL(string: uriString) {
        url = parsed
      } else {
        url = URL(fileURLWithPath: uriString)
      }
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          url.stopAccessingSecurityScopedResource()
        }
      }
      return try Data(contentsOf: url).base64EncodedString()
    } catch {
      return ""
    }
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

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pendingDocumentPickerResult
    pendingDocumentPickerResult = nil
    guard let url = urls.first else {
      result?("")
      return
    }
    guard isSupportedDeliveryOrderFile(url) else {
      result?(FlutterError(code: "unsupported_file", message: "请选择 Excel 或压缩包文件", details: nil))
      return
    }
    do {
      result?(try copyUrlToCache(url))
    } catch {
      result?(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingDocumentPickerResult
    pendingDocumentPickerResult = nil
    result?("")
  }
}
