package com.example.datarecorder

import android.Manifest
import android.app.Activity
import android.util.Base64
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import com.example.datarecorder.deliveryorder.DeliveryOrderExternalIntentHandler
import com.iflytek.sparkchain.core.SparkChain
import com.iflytek.sparkchain.core.SparkChainConfig
import com.iflytek.sparkchain.core.asr.ASR
import com.iflytek.sparkchain.core.asr.AsrCallbacks
import java.io.File
import java.net.URL
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private data class ExportBytesFile(
        val fileName: String,
        val bytes: ByteArray,
        val mimeType: String
    )

    private var pendingImageResult: MethodChannel.Result? = null
    private var pendingCameraUri: Uri? = null
    private var pendingCameraPermissionResult: MethodChannel.Result? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingFileResult: MethodChannel.Result? = null
    private var deliveryOrderIntakeChannel: MethodChannel? = null
    private var pendingExternalDeliveryOrderFile: Map<String, Any?>? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportFiles: List<ExportBytesFile> = emptyList()
    private val updateDownloadHandler by lazy { AppUpdateDownloadHandler(this) }
    private var fastSparkInitialized = false
    private var fastSparkAsr: ASR? = null
    private var fastSparkSessionIndex = 0
    private var fastSparkTextBuilder = StringBuilder()
    private var fastVoiceRecorder: FastVoiceAudioRecorder? = null
    private var fastVoiceListening = false
    private var fastVoiceWaitingResult = false
    private var fastVoiceBestText = ""
    private var fastVoiceIgnoreResult = false
    private var fastVoiceStopResult: MethodChannel.Result? = null
    private var fastVoicePermissionStartResult: MethodChannel.Result? = null
    private val fastVoiceHandler = Handler(Looper.getMainLooper())
    private val fastVoiceCompleteRunnable = Runnable { completeFastVoiceResult(fastVoiceBestText) }
    private val fastVoiceTimeoutRunnable = Runnable { handleFastVoiceTimeout() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/legacy_storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readPreferences" -> {
                    val name = call.argument<String>("name")
                    if (name.isNullOrBlank()) {
                        result.success(emptyMap<String, Any>())
                        return@setMethodCallHandler
                    }
                    result.success(readPreferences(name))
                }
                "writePreferences" -> {
                    val name = call.argument<String>("name")
                    @Suppress("UNCHECKED_CAST")
                    val values = call.argument<Map<String, Any?>>("values") ?: emptyMap()
                    if (name.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    writePreferences(name, values)
                    result.success(true)
                }
                "removePreferences" -> {
                    val name = call.argument<String>("name")
                    val keys = call.argument<List<String>>("keys") ?: emptyList()
                    if (name.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    removePreferences(name, keys)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/fast_voice"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> startFastVoiceListening(result)
                "stopListening" -> stopFastVoiceListening(result)
                "cancelListening" -> cancelFastVoiceListening(result)
                "recognize" -> startFastVoiceRecognition(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/update"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadAndInstall" -> {
                    val url = call.argument<String>("url") ?: ""
                    val versionCode = call.argument<Number>("versionCode")?.toInt() ?: 0
                    Thread {
                        try {
                            val path = updateDownloadHandler.downloadAndInstall(url, versionCode)
                            runOnUiThread { result.success(path) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("download_failed", error.message, null) }
                        }
                    }.start()
                }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/quality_photo"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePhoto" -> takeQualityPhoto(result)
                "pickPhoto" -> pickQualityPhoto(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/export_share"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareTextFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "export.csv"
                    val content = call.argument<String>("content") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                    val title = call.argument<String>("title") ?: "分享文件"
                    shareFile(fileName, content.toByteArray(Charsets.UTF_8), mimeType, title)
                    result.success(null)
                }
                "shareBytesFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "export.xlsx"
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val title = call.argument<String>("title") ?: "分享文件"
                    shareFile(fileName, bytes, mimeType, title)
                    result.success(null)
                }
                "saveBytesFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "export.xlsx"
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    result.success(saveFile(fileName, bytes))
                }
                "exportBytesFiles" -> exportBytesFiles(call, result)
                "saveHistory" -> {
                    val fileName = call.argument<String>("fileName") ?: "history.json"
                    val content = call.argument<String>("content") ?: "{}"
                    result.success(saveHistory(fileName, content))
                }
                "listHistory" -> result.success(listHistory())
                "readHistory" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(readHistory(path))
                }
                "deleteHistory" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(deleteHistory(path))
                }
                "readBytesBase64" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    result.success(readBytesBase64(uri))
                }
                "pickDeliveryOrderFile" -> pickDeliveryOrderFile(result)
                else -> result.notImplemented()
            }
        }

        deliveryOrderIntakeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/delivery_order_intake"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialDeliveryOrderFile" -> {
                        val file = pendingExternalDeliveryOrderFile
                        pendingExternalDeliveryOrderFile = null
                        result.success(file)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handleExternalDeliveryOrderIntent(intent)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.datarecorder/legacy_database"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllProjects" -> result.success(getAllProjects())
                "getProjectById" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    result.success(if (id == null) null else getProjectById(id))
                }
                "insertProject" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    result.success(insertProject(args))
                }
                "updateProject" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    result.success(updateProject(args))
                }
                "deleteProject" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    result.success(if (id == null) 0 else deleteProject(id))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleExternalDeliveryOrderIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        updateDownloadHandler.onHostResume()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            7011 -> {
                val result = pendingImageResult ?: return
                pendingImageResult = null
                result.success(if (resultCode == Activity.RESULT_OK) pendingCameraUri?.toString().orEmpty() else "")
            }
            7012 -> {
                val result = pendingImageResult ?: return
                pendingImageResult = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                result.success(uri?.toString().orEmpty())
            }
            7021 -> {
                val result = pendingSpeechResult ?: return
                pendingSpeechResult = null
                val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                result.success(if (resultCode == Activity.RESULT_OK) matches?.firstOrNull().orEmpty() else "")
            }
            7031 -> {
                val result = pendingFileResult ?: return
                pendingFileResult = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                result.success(uri?.let { copyContentUriToCache(it) }.orEmpty())
            }
            7042 -> {
                val result = pendingExportResult ?: return
                pendingExportResult = null
                val files = pendingExportFiles
                pendingExportFiles = emptyList()
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                if (uri == null) {
                    result.success(emptyList<Map<String, Any?>>())
                } else {
                    val progressDialog = AppProcessingDialog(this)
                    progressDialog.show("正在导出文件")
                    Thread {
                        try {
                            val exportedFiles = writeExportFilesToTree(uri, files)
                            runOnUiThread {
                                progressDialog.dismiss()
                                result.success(exportedFiles)
                            }
                        } catch (error: Exception) {
                            runOnUiThread {
                                progressDialog.dismiss()
                                result.error("export_failed", error.message, null)
                            }
                        }
                    }.start()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7013) {
            val result = pendingCameraPermissionResult ?: return
            pendingCameraPermissionResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                launchQualityCamera(result)
            } else {
                result.error("permission_denied", "未授予相机权限，无法拍照", null)
            }
            return
        }
        if (requestCode == 7041) {
            val result = fastVoicePermissionStartResult ?: return
            fastVoicePermissionStartResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                beginFastVoiceListening(result)
            } else {
                result.error("permission_denied", "未授予录音权限，无法使用语音识别", null)
            }
        }
    }

    override fun onDestroy() {
        releaseFastVoiceRecognizer()
        super.onDestroy()
    }

    private fun startFastVoiceRecognition(result: MethodChannel.Result) {
        if (pendingSpeechResult != null) {
            result.success("")
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "请说出宽度和长度")
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("unavailable", "当前设备不支持系统语音识别", null)
            return
        }
        pendingSpeechResult = result
        try {
            startActivityForResult(intent, 7021)
        } catch (error: Exception) {
            pendingSpeechResult = null
            result.error("start_failed", error.message, null)
        }
    }

    private fun startFastVoiceListening(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            if (fastVoicePermissionStartResult != null) {
                result.error("permission_pending", "正在请求录音权限", null)
                return
            }
            fastVoicePermissionStartResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7041)
            return
        }
        beginFastVoiceListening(result)
    }

    private fun beginFastVoiceListening(result: MethodChannel.Result) {
        if (fastVoiceListening || fastVoiceWaitingResult) {
            result.success(null)
            return
        }
        if (BuildConfig.SPARK_APP_ID.isBlank() ||
            BuildConfig.SPARK_API_KEY.isBlank() ||
            BuildConfig.SPARK_API_SECRET.isBlank()
        ) {
            result.error("unavailable", "未配置讯飞星火语音参数，无法使用语音识别", null)
            return
        }
        if (!ensureFastSparkInitialized()) {
            result.error("start_failed", "初始化讯飞星火语音失败", null)
            return
        }
        val asr = ensureFastSparkAsr() ?: run {
            result.error("start_failed", "创建讯飞星火识别器失败", null)
            return
        }
        try {
            fastVoiceHandler.removeCallbacks(fastVoiceCompleteRunnable)
            fastVoiceHandler.removeCallbacks(fastVoiceTimeoutRunnable)
            fastSparkTextBuilder.setLength(0)
            fastVoiceBestText = ""
            fastVoiceIgnoreResult = false
            fastVoiceStopResult = null
            fastVoiceWaitingResult = false
            asr.language("zh_cn")
            asr.domain("iat")
            asr.accent("mandarin")
            runCatching { asr.ptt(false) }
            runCatching { asr.vadEos(3000) }
            runCatching { asr.vinfo(true) }
            runCatching { asr.dwa("wpgs") }
            fastSparkSessionIndex += 1
            val startRet = asr.start(fastSparkSessionIndex.toString())
            if (startRet != 0) {
                result.error("start_failed", "语音识别启动失败：错误码$startRet", null)
                return
            }
            val recorder = FastVoiceAudioRecorder()
            fastVoiceRecorder = recorder
            fastVoiceListening = true
            scheduleFastVoiceTimeout()
            recorder.start(
                onPcmData = { data ->
                    if (!fastVoiceListening && !fastVoiceWaitingResult) return@start
                    runCatching { asr.write(data) }.onFailure { error ->
                        runOnUiThread { handleFastVoiceRecorderFailure(error) }
                    }
                },
                onError = { error ->
                    runOnUiThread { handleFastVoiceRecorderFailure(error) }
                }
            )
            result.success(null)
        } catch (error: Exception) {
            clearFastVoiceSession()
            result.error("start_failed", error.message ?: "语音识别启动失败", null)
        }
    }

    private fun stopFastVoiceListening(result: MethodChannel.Result) {
        if (fastVoiceStopResult != null) {
            result.success("")
            return
        }
        fastVoiceStopResult = result
        if (!fastVoiceListening && !fastVoiceWaitingResult) {
            completeFastVoiceResult(fastVoiceBestText)
            return
        }
        fastVoiceListening = false
        fastVoiceWaitingResult = true
        stopFastVoiceRecorder()
        try {
            fastSparkAsr?.stop(false)
        } catch (error: Exception) {
            clearFastVoiceSession()
            fastVoiceStopResult = null
            result.error("recognition_failed", "语音识别失败：${error.message ?: "无法结束语音识别"}", null)
        }
    }

    private fun cancelFastVoiceListening(result: MethodChannel.Result) {
        fastVoiceIgnoreResult = true
        fastVoicePermissionStartResult?.error("cancelled", "语音识别已取消", null)
        fastVoicePermissionStartResult = null
        fastVoiceStopResult?.success("")
        fastVoiceStopResult = null
        stopFastVoiceRecorder()
        fastVoiceHandler.removeCallbacks(fastVoiceCompleteRunnable)
        fastVoiceHandler.removeCallbacks(fastVoiceTimeoutRunnable)
        runCatching { fastSparkAsr?.stop(true) }
        clearFastVoiceSession()
        result.success(null)
    }

    private fun ensureFastSparkInitialized(): Boolean {
        if (fastSparkInitialized) return true
        val workDir = File(filesDir, "sparkchain").apply { mkdirs() }
        val config = SparkChainConfig.builder()
            .appID(BuildConfig.SPARK_APP_ID)
            .apiKey(BuildConfig.SPARK_API_KEY)
            .apiSecret(BuildConfig.SPARK_API_SECRET)
            .workDir(workDir.absolutePath)
        val ret = runCatching { SparkChain.getInst().init(applicationContext, config) }.getOrElse {
            return false
        }
        fastSparkInitialized = ret == 0
        return fastSparkInitialized
    }

    private fun ensureFastSparkAsr(): ASR? {
        fastSparkAsr?.let { return it }
        return runCatching {
            ASR().also { asr ->
                asr.registerCallbacks(createFastSparkCallbacks())
                fastSparkAsr = asr
            }
        }.getOrNull()
    }

    private fun createFastSparkCallbacks(): AsrCallbacks {
        return object : AsrCallbacks {
            override fun onResult(asrResult: ASR.ASRResult, usrTag: Any?) {
                handleFastSparkResult(asrResult)
            }

            override fun onError(asrError: ASR.ASRError, usrTag: Any?) {
                handleFastSparkError(asrError)
            }

            override fun onBeginOfSpeech() = Unit
            override fun onEndOfSpeech() = Unit
        }
    }

    private fun handleFastSparkResult(asrResult: ASR.ASRResult) {
        val text = asrResult.getBestMatchText().orEmpty().trim()
        if (text.isNotBlank()) {
            fastSparkTextBuilder.setLength(0)
            fastSparkTextBuilder.append(text)
            fastVoiceBestText = text
        }
        if (asrResult.getStatus() != 2) return
        val finalText = text.ifBlank { fastSparkTextBuilder.toString().trim() }
        runOnUiThread {
            val shouldIgnore = fastVoiceIgnoreResult
            if (shouldIgnore) {
                clearFastVoiceSession()
                return@runOnUiThread
            }
            completeFastVoiceResult(finalText)
            clearFastVoiceSession()
        }
    }

    private fun handleFastSparkError(asrError: ASR.ASRError) {
        runOnUiThread {
            if (!fastVoiceListening && !fastVoiceWaitingResult) return@runOnUiThread
            val shouldIgnore = fastVoiceIgnoreResult
            val message = asrError.getErrMsg()?.takeIf { it.isNotBlank() } ?: "错误码${asrError.getCode()}"
            val result = fastVoiceStopResult
            clearFastVoiceSession()
            if (!shouldIgnore && result != null) {
                fastVoiceStopResult = null
                result.error("recognition_failed", "语音识别失败：$message", null)
            }
        }
    }

    private fun handleFastVoiceRecorderFailure(error: Throwable) {
        if (!fastVoiceListening && !fastVoiceWaitingResult) return
        val shouldIgnore = fastVoiceIgnoreResult
        val result = fastVoiceStopResult
        clearFastVoiceSession()
        if (!shouldIgnore && result != null) {
            fastVoiceStopResult = null
            result.error("record_failed", "录音失败：${error.message ?: "无法读取麦克风数据"}", null)
        }
    }

    private fun scheduleFastVoiceTimeout() {
        fastVoiceHandler.removeCallbacks(fastVoiceTimeoutRunnable)
        fastVoiceHandler.postDelayed(fastVoiceTimeoutRunnable, 12_000L)
    }

    private fun handleFastVoiceTimeout() {
        if (!fastVoiceListening && !fastVoiceWaitingResult) return
        fastVoiceIgnoreResult = true
        stopFastVoiceRecorder()
        runCatching { fastSparkAsr?.stop(true) }
        completeFastVoiceResult(fastVoiceBestText)
        clearFastVoiceSession()
    }

    private fun completeFastVoiceResult(text: String) {
        fastVoiceHandler.removeCallbacks(fastVoiceCompleteRunnable)
        fastVoiceHandler.removeCallbacks(fastVoiceTimeoutRunnable)
        fastVoiceListening = false
        fastVoiceWaitingResult = false
        val result = fastVoiceStopResult ?: return
        fastVoiceStopResult = null
        result.success(text.trim())
    }

    private fun clearFastVoiceSession() {
        fastVoiceHandler.removeCallbacks(fastVoiceCompleteRunnable)
        fastVoiceHandler.removeCallbacks(fastVoiceTimeoutRunnable)
        stopFastVoiceRecorder()
        fastVoiceListening = false
        fastVoiceWaitingResult = false
        fastVoiceBestText = ""
        fastSparkTextBuilder.setLength(0)
        fastVoiceIgnoreResult = false
    }

    private fun stopFastVoiceRecorder() {
        fastVoiceRecorder?.release()
        fastVoiceRecorder = null
    }

    private fun releaseFastVoiceRecognizer() {
        fastVoiceStopResult?.success("")
        fastVoiceStopResult = null
        fastVoicePermissionStartResult?.error("cancelled", "语音识别已取消", null)
        fastVoicePermissionStartResult = null
        fastVoiceIgnoreResult = true
        stopFastVoiceRecorder()
        fastVoiceHandler.removeCallbacks(fastVoiceCompleteRunnable)
        fastVoiceHandler.removeCallbacks(fastVoiceTimeoutRunnable)
        runCatching { fastSparkAsr?.stop(true) }
        fastSparkAsr = null
        if (fastSparkInitialized) {
            runCatching { SparkChain.getInst().unInit() }
            fastSparkInitialized = false
        }
        clearFastVoiceSession()
    }

    private fun downloadApk(url: String, versionCode: Int): String {
        require(url.isNotBlank()) { "下载地址为空" }
        val file = java.io.File(getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS), "update_v${versionCode}.apk")
        URL(url).openStream().use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        }
        return file.absolutePath
    }

    private fun installApk(path: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return
        }
        val file = java.io.File(path)
        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun takeQualityPhoto(result: MethodChannel.Result) {
        if (pendingImageResult != null || pendingCameraPermissionResult != null) {
            result.success("")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingCameraPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 7013)
            return
        }
        launchQualityCamera(result)
    }

    private fun launchQualityCamera(result: MethodChannel.Result) {
        val file = java.io.File(cacheDir, "quality_${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        pendingCameraUri = uri
        pendingImageResult = result
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, 7011)
        } catch (error: Exception) {
            pendingCameraUri = null
            pendingImageResult = null
            result.error("camera_failed", error.message, null)
        }
    }

    private fun pickQualityPhoto(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.success("")
            return
        }
        pendingImageResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, 7012)
    }

    private fun bytesArgument(value: Any?): ByteArray? {
        return when (value) {
            is ByteArray -> value
            is List<*> -> {
                val bytes = ByteArray(value.size)
                value.forEachIndexed { index, item ->
                    val intValue = (item as? Number)?.toInt() ?: return null
                    if (intValue !in 0..255) return null
                    bytes[index] = intValue.toByte()
                }
                bytes
            }
            else -> null
        }
    }

    private fun exportBytesFiles(call: MethodCall, result: MethodChannel.Result) {
        if (pendingExportResult != null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        @Suppress("UNCHECKED_CAST")
        val rawFiles = call.argument<List<Map<String, Any?>>>("files") ?: emptyList()
        val files = rawFiles.mapNotNull { raw ->
            val fileName = raw["fileName"]?.toString()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val bytes = bytesArgument(raw["bytes"]) ?: return@mapNotNull null
            val mimeType = raw["mimeType"]?.toString()?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
            ExportBytesFile(fileName, bytes, mimeType)
        }
        if (files.isEmpty()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        pendingExportResult = result
        pendingExportFiles = files
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
            val lastUri = getSharedPreferences("export_share", MODE_PRIVATE).getString("last_export_tree_uri", "")
            if (!lastUri.isNullOrBlank() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(lastUri))
            }
        }
        startActivityForResult(intent, 7042)
    }

    private fun writeExportFilesToTree(
        treeUri: Uri,
        files: List<ExportBytesFile>
    ): List<Map<String, Any?>> {
        runCatching {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        getSharedPreferences("export_share", MODE_PRIVATE)
            .edit()
            .putString("last_export_tree_uri", treeUri.toString())
            .apply()
        val treeDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val directoryUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocumentId)
        return files.mapNotNull { file ->
            val safeName = file.fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val documentUri = DocumentsContract.createDocument(
                contentResolver,
                directoryUri,
                file.mimeType,
                safeName
            ) ?: return@mapNotNull null
            contentResolver.openOutputStream(documentUri)?.use { output ->
                output.write(file.bytes)
            }
            mapOf(
                "fileName" to safeName,
                "uri" to documentUri.toString(),
                "success" to true
            )
        }
    }

    private fun handleExternalDeliveryOrderIntent(intent: Intent?): Boolean {
        return try {
            val file = DeliveryOrderExternalIntentHandler(this).handle(intent) ?: return false
            val payload = file.toChannelMap()
            pendingExternalDeliveryOrderFile = payload
            deliveryOrderIntakeChannel?.invokeMethod("onDeliveryOrderFile", payload)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun pickDeliveryOrderFile(result: MethodChannel.Result) {
        if (pendingFileResult != null) {
            result.success("")
            return
        }
        pendingFileResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/zip",
                "application/x-zip-compressed"
            ))
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivityForResult(intent, 7031)
    }

    private fun copyContentUriToCache(uri: Uri): String {
        val fallbackName = uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "delivery_order_${System.currentTimeMillis()}.xlsx"
        val name = queryDisplayName(uri).ifBlank { fallbackName }
        val safeName = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val file = java.io.File(cacheDir, safeName)
        if (uri.scheme == "file") {
            java.io.File(uri.path.orEmpty()).inputStream().use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
        } else {
            contentResolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
        }
        return file.absolutePath
    }

    private fun queryDisplayName(uri: Uri): String {
        return contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index).orEmpty() else ""
        }.orEmpty()
    }

    private fun readPreferences(name: String): Map<String, Any?> {
        val preferences = getSharedPreferences(name, MODE_PRIVATE)
        return preferences.all.mapValues { entry ->
            when (val value = entry.value) {
                is String, is Boolean, is Int, is Long, is Float -> value
                else -> value?.toString()
            }
        }
    }

    private fun writePreferences(name: String, values: Map<String, Any?>) {
        val editor = getSharedPreferences(name, MODE_PRIVATE).edit()
        values.forEach { (key, value) ->
            when (value) {
                null -> editor.remove(key)
                is Boolean -> editor.putBoolean(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Float -> editor.putFloat(key, value)
                is Number -> editor.putLong(key, value.toLong())
                else -> editor.putString(key, value.toString())
            }
        }
        editor.apply()
    }

    private fun removePreferences(name: String, keys: List<String>) {
        val editor = getSharedPreferences(name, MODE_PRIVATE).edit()
        keys.forEach { editor.remove(it) }
        editor.apply()
    }

    private fun saveFile(fileName: String, bytes: ByteArray): String {
        val safeFileName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val file = java.io.File(cacheDir, safeFileName)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun historyDir(): java.io.File {
        return java.io.File(filesDir, "history").apply { mkdirs() }
    }

    private fun saveHistory(fileName: String, content: String): String {
        val safeFileName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val file = java.io.File(historyDir(), safeFileName)
        file.writeText(content, Charsets.UTF_8)
        trimHistoryBackups(5)
        return file.absolutePath
    }

    private fun trimHistoryBackups(keepCount: Int) {
        val marker = "_历史数据自动备份_"
        val groupedFiles = historyDir().listFiles()
            ?.filter { it.isFile && it.name.endsWith(".json") && it.name.contains(marker) }
            ?.groupBy { it.name.substringBefore(marker) }
            ?: return
        groupedFiles.values.forEach { files ->
            files.sortedByDescending { it.lastModified() }
                .drop(keepCount)
                .forEach { it.delete() }
        }
    }

    private fun listHistory(): List<Map<String, Any?>> {
        trimHistoryBackups(5)
        return historyDir().listFiles()
            ?.filter { it.isFile && it.name.endsWith(".json") }
            ?.sortedByDescending { it.lastModified() }
            ?.map {
                mapOf(
                    "name" to it.name,
                    "path" to it.absolutePath,
                    "modified" to it.lastModified(),
                    "size" to it.length()
                )
            }
            ?: emptyList()
    }

    private fun readHistory(path: String): String {
        val file = java.io.File(path)
        return if (file.exists() && file.isFile) file.readText(Charsets.UTF_8) else ""
    }

    private fun deleteHistory(path: String): Boolean {
        val file = java.io.File(path)
        return file.exists() && file.isFile && file.delete()
    }

    private fun readBytesBase64(uriString: String): String {
        if (uriString.isBlank()) return ""
        return try {
            val bytes = if (uriString.startsWith("content://")) {
                contentResolver.openInputStream(Uri.parse(uriString))?.use { it.readBytes() } ?: ByteArray(0)
            } else {
                val path = uriString.removePrefix("file://")
                java.io.File(path).takeIf { it.exists() && it.isFile }?.readBytes() ?: ByteArray(0)
            }
            Base64.encodeToString(bytes, Base64.NO_WRAP)
        } catch (_: Exception) {
            ""
        }
    }

    private fun shareFile(fileName: String, bytes: ByteArray, mimeType: String, title: String) {
        val file = java.io.File(saveFile(fileName, bytes))
        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, title))
    }

    private fun openDatabase(): SQLiteDatabase {
        return openOrCreateDatabase("data_recorder.db", MODE_PRIVATE, null).also { database ->
            database.execSQL(
                """
                CREATE TABLE IF NOT EXISTS projects (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    name TEXT NOT NULL,
                    buildingName TEXT NOT NULL DEFAULT '',
                    standardContent TEXT NOT NULL DEFAULT '[]',
                    fastContent TEXT NOT NULL DEFAULT '[]',
                    loadingContent TEXT NOT NULL DEFAULT '',
                    qualityContent TEXT NOT NULL DEFAULT ''
                )
                """.trimIndent()
            )
            ensureProjectColumns(database)
        }
    }

    private fun ensureProjectColumns(database: SQLiteDatabase) {
        val existingColumns = mutableSetOf<String>()
        database.rawQuery("PRAGMA table_info(projects)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                existingColumns.add(cursor.getString(nameIndex))
            }
        }
        val migrations = mapOf(
            "buildingName" to "ALTER TABLE projects ADD COLUMN buildingName TEXT NOT NULL DEFAULT ''",
            "standardContent" to "ALTER TABLE projects ADD COLUMN standardContent TEXT NOT NULL DEFAULT '[]'",
            "fastContent" to "ALTER TABLE projects ADD COLUMN fastContent TEXT NOT NULL DEFAULT '[]'",
            "loadingContent" to "ALTER TABLE projects ADD COLUMN loadingContent TEXT NOT NULL DEFAULT ''",
            "qualityContent" to "ALTER TABLE projects ADD COLUMN qualityContent TEXT NOT NULL DEFAULT ''"
        )
        migrations.forEach { (column, sql) ->
            if (!existingColumns.contains(column)) {
                database.execSQL(sql)
            }
        }
    }

    private val projectColumns = arrayOf("id", "name", "buildingName", "standardContent", "fastContent", "loadingContent", "qualityContent")

    private fun getAllProjects(): List<Map<String, Any?>> {
        val database = openDatabase()
        val cursor = database.query(
            "projects",
            projectColumns,
            null,
            null,
            null,
            null,
            "id DESC"
        )
        val projects = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                projects.add(projectFromCursor(it))
            }
        }
        database.close()
        return projects
    }

    private fun getProjectById(id: Long): Map<String, Any?>? {
        val database = openDatabase()
        val cursor = database.query(
            "projects",
            projectColumns,
            "id = ?",
            arrayOf(id.toString()),
            null,
            null,
            null,
            "1"
        )
        val project = cursor.use {
            if (it.moveToFirst()) projectFromCursor(it) else null
        }
        database.close()
        return project
    }

    private fun insertProject(project: Map<String, Any?>): Long {
        val database = openDatabase()
        val id = database.insert("projects", null, projectValues(project))
        database.close()
        return id
    }

    private fun updateProject(project: Map<String, Any?>): Int {
        val id = (project["id"] as? Number)?.toLong() ?: return 0
        val database = openDatabase()
        val count = database.update(
            "projects",
            projectValues(project),
            "id = ?",
            arrayOf(id.toString())
        )
        database.close()
        return count
    }

    private fun deleteProject(id: Long): Int {
        val database = openDatabase()
        val count = database.delete("projects", "id = ?", arrayOf(id.toString()))
        database.close()
        return count
    }

    private fun projectValues(project: Map<String, Any?>): ContentValues {
        return ContentValues().apply {
            put("name", project["name"]?.toString() ?: "默认项目")
            put("buildingName", project["buildingName"]?.toString() ?: "")
            put("standardContent", project["standardContent"]?.toString() ?: "[]")
            put("fastContent", project["fastContent"]?.toString() ?: "[]")
            put("loadingContent", project["loadingContent"]?.toString() ?: "")
            put("qualityContent", project["qualityContent"]?.toString() ?: "")
        }
    }

    private fun projectFromCursor(cursor: android.database.Cursor): Map<String, Any?> {
        return mapOf(
            "id" to cursor.getLong(0),
            "name" to cursor.getString(1),
            "buildingName" to cursor.getString(2),
            "standardContent" to cursor.getString(3),
            "fastContent" to cursor.getString(4),
            "loadingContent" to cursor.getString(5),
            "qualityContent" to cursor.getString(6)
        )
    }
}
