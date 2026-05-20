package com.example.datarecorder

import android.app.Activity
import android.util.Base64
import android.content.ContentValues
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import java.net.URL
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingImageResult: MethodChannel.Result? = null
    private var pendingCameraUri: Uri? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingFileResult: MethodChannel.Result? = null

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
                            val path = downloadApk(url, versionCode)
                            runOnUiThread {
                                installApk(path)
                                result.success(path)
                            }
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
        }
    }

    private fun startFastVoiceRecognition(result: MethodChannel.Result) {
        if (pendingSpeechResult != null) {
            result.success("")
            return
        }
        pendingSpeechResult = result
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "请说出宽度和长度")
        }
        startActivityForResult(intent, 7021)
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
        if (pendingImageResult != null) {
            result.success("")
            return
        }
        val file = java.io.File(cacheDir, "quality_${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        pendingCameraUri = uri
        pendingImageResult = result
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivityForResult(intent, 7011)
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
        val name = queryDisplayName(uri).ifBlank { "delivery_order_${System.currentTimeMillis()}.xlsx" }
        val safeName = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val file = java.io.File(cacheDir, safeName)
        contentResolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
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
        trimHistoryBackups(safeFileName, 5)
        return file.absolutePath
    }

    private fun trimHistoryBackups(fileName: String, keepCount: Int) {
        val marker = "_历史数据自动备份_"
        val prefix = fileName.substringBefore(marker, missingDelimiterValue = "")
        if (prefix.isBlank()) return
        historyDir().listFiles()
            ?.filter {
                it.isFile &&
                    it.name.startsWith("${prefix}${marker}") &&
                    it.name.endsWith(".json")
            }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(keepCount)
            ?.forEach { it.delete() }
    }

    private fun listHistory(): List<Map<String, Any?>> {
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
