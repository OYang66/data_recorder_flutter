package com.example.datarecorder

import android.app.Activity
import android.app.Dialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.text.DecimalFormat

class AppUpdateDownloadHandler(private val activity: Activity) {
    private val prefs by lazy {
        activity.getSharedPreferences("app_update_cache", Activity.MODE_PRIVATE)
    }

    private val downloadedVersionCodeKey = "downloaded_version_code"
    private val downloadedApkPathKey = "downloaded_apk_path"

    private var pendingInstallApkFile: File? = null
    private var waitingForUnknownAppPermission = false
    private var downloadDialog: Dialog? = null
    private var progressBar: ProgressBar? = null
    private var percentView: TextView? = null
    private var sizeView: TextView? = null

    fun onHostResume() {
        clearInstalledUpdateCache()
        if (!waitingForUnknownAppPermission || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!activity.packageManager.canRequestPackageInstalls()) return
        waitingForUnknownAppPermission = false
        val apkFile = pendingInstallApkFile
        if (apkFile != null && apkFile.exists() && apkFile.length() > 0L) {
            installApk(apkFile)
        } else {
            pendingInstallApkFile = null
            clearDownloadedApkInfo()
            Toast.makeText(activity, "安装包不存在，请重新更新", Toast.LENGTH_SHORT).show()
        }
    }

    fun downloadAndInstall(url: String, versionCode: Int): String {
        require(url.isNotBlank()) { "下载地址为空" }
        val cachedApk = findReusableDownloadedApk(versionCode)
        if (cachedApk != null) {
            pendingInstallApkFile = cachedApk
            activity.runOnUiThread {
                Toast.makeText(activity, "安装包已下载，正在打开安装界面", Toast.LENGTH_SHORT).show()
                installApk(cachedApk)
            }
            return cachedApk.absolutePath
        }

        activity.runOnUiThread { showDownloadProgressDialog() }
        return try {
            val apkFile = downloadApk(url, versionCode)
            saveDownloadedApkInfo(versionCode, apkFile)
            pendingInstallApkFile = apkFile
            activity.runOnUiThread {
                dismissDownloadProgressDialog()
                installApk(apkFile)
            }
            apkFile.absolutePath
        } catch (error: Exception) {
            activity.runOnUiThread { dismissDownloadProgressDialog() }
            throw error
        }
    }

    private fun findReusableDownloadedApk(versionCode: Int): File? {
        val savedVersionCode = prefs.getInt(downloadedVersionCodeKey, -1)
        val savedPath = prefs.getString(downloadedApkPathKey, null).orEmpty()
        if (savedVersionCode == versionCode && savedPath.isNotBlank()) {
            val savedFile = File(savedPath)
            if (savedFile.exists() && savedFile.length() > 0L) return savedFile
        }
        val fileByVersion = File(getApkDownloadDir(), "update_v${versionCode}.apk")
        if (fileByVersion.exists() && fileByVersion.length() > 0L) {
            saveDownloadedApkInfo(versionCode, fileByVersion)
            return fileByVersion
        }
        clearDownloadedApkInfo()
        return null
    }

    private fun saveDownloadedApkInfo(versionCode: Int, apkFile: File) {
        prefs.edit()
            .putInt(downloadedVersionCodeKey, versionCode)
            .putString(downloadedApkPathKey, apkFile.absolutePath)
            .apply()
    }

    private fun clearDownloadedApkInfo() {
        prefs.edit()
            .remove(downloadedVersionCodeKey)
            .remove(downloadedApkPathKey)
            .apply()
    }

    private fun clearInstalledUpdateCache() {
        val savedVersionCode = prefs.getInt(downloadedVersionCodeKey, -1)
        if (savedVersionCode <= 0 || savedVersionCode > currentVersionCode()) return
        val savedPath = prefs.getString(downloadedApkPathKey, null).orEmpty()
        if (savedPath.isNotBlank()) runCatching { File(savedPath).delete() }
        runCatching { File(getApkDownloadDir(), "update_v${savedVersionCode}.apk").delete() }
        pendingInstallApkFile = null
        clearDownloadedApkInfo()
    }

    @Suppress("DEPRECATION")
    private fun currentVersionCode(): Long {
        val packageInfo = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            packageInfo.versionCode.toLong()
        }
    }

    private fun getApkDownloadDir(): File {
        val dir = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: activity.filesDir
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun deleteOldCachedApks(keepFileName: String) {
        getApkDownloadDir().listFiles()?.forEach { file ->
            if (file.isFile && file.name.endsWith(".apk") && file.name != keepFileName) {
                runCatching { file.delete() }
            }
        }
    }

    private fun downloadApk(url: String, versionCode: Int): File {
        val dir = getApkDownloadDir()
        val finalFile = File(dir, "update_v${versionCode}.apk")
        val tempFile = File(dir, "${finalFile.name}.download")
        if (tempFile.exists()) tempFile.delete()

        val connection = URL(url).openConnection()
        val totalBytes = connection.contentLengthLong
        connection.getInputStream().use { input ->
            FileOutputStream(tempFile).use { output ->
                val buffer = ByteArray(8 * 1024)
                var downloadedBytes = 0L
                while (true) {
                    val length = input.read(buffer)
                    if (length == -1) break
                    output.write(buffer, 0, length)
                    downloadedBytes += length
                    updateProgress(downloadedBytes, totalBytes)
                }
                output.flush()
            }
        }

        if (finalFile.exists()) finalFile.delete()
        if (!tempFile.renameTo(finalFile)) {
            tempFile.copyTo(finalFile, overwrite = true)
            tempFile.delete()
        }
        deleteOldCachedApks(keepFileName = finalFile.name)
        updateProgress(totalBytes.takeIf { it > 0 } ?: finalFile.length(), totalBytes)
        return finalFile
    }

    private fun installApk(file: File) {
        pendingInstallApkFile = file
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            waitingForUnknownAppPermission = true
            Toast.makeText(activity, "请先允许安装未知来源应用", Toast.LENGTH_LONG).show()
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${activity.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            return
        }
        waitingForUnknownAppPermission = false
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            activity.startActivity(intent)
        } catch (error: ActivityNotFoundException) {
            throw IllegalStateException("无法打开安装界面", error)
        }
    }

    private fun showDownloadProgressDialog() {
        dismissDownloadProgressDialog()
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(Color.WHITE)
                cornerRadius = dpF(18f)
            }
        }
        val topRow = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        topRow.addView(TextView(activity).apply {
            text = "正在下载更新"
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(0xFF222222.toInt())
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        percentView = TextView(activity).apply {
            text = "0%"
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(0xFF4E3D91.toInt())
            gravity = Gravity.END
        }
        topRow.addView(percentView)
        progressBar = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progress = 0
            progressDrawable?.setTint(0xFF6C56B3.toInt())
        }
        sizeView = TextView(activity).apply {
            text = "0MB / 0MB"
            textSize = 13f
            setTextColor(0xFF666666.toInt())
            gravity = Gravity.CENTER_HORIZONTAL
        }
        root.addView(topRow)
        root.addView(progressBar, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(14)
        ).apply { topMargin = dp(16) })
        root.addView(sizeView, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(12) })
        downloadDialog = Dialog(activity).apply {
            setCancelable(false)
            setContentView(root)
            window?.setBackgroundDrawableResource(android.R.color.transparent)
            show()
            window?.setLayout((activity.resources.displayMetrics.widthPixels * 0.86f).toInt(), ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun dismissDownloadProgressDialog() {
        downloadDialog?.dismiss()
        downloadDialog = null
        progressBar = null
        percentView = null
        sizeView = null
    }

    private fun updateProgress(downloadedBytes: Long, totalBytes: Long) {
        activity.runOnUiThread {
            val progress = if (totalBytes > 0) {
                ((downloadedBytes * 100) / totalBytes).toInt().coerceIn(0, 100)
            } else {
                0
            }
            progressBar?.progress = progress
            percentView?.text = "$progress%"
            val totalText = if (totalBytes > 0) formatFileSize(totalBytes) else "未知大小"
            sizeView?.text = "${formatFileSize(downloadedBytes)} / $totalText"
        }
    }

    private fun formatFileSize(bytes: Long): String {
        if (bytes <= 0) return "0MB"
        return "${DecimalFormat("0.00").format(bytes / 1024.0 / 1024.0)}MB"
    }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).toInt()

    private fun dpF(value: Float): Float = value * activity.resources.displayMetrics.density
}
