package com.example.datarecorder.deliveryorder

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.util.Locale
import java.util.zip.ZipInputStream

class DeliveryOrderExternalIntentHandler(private val context: Context) {
    private enum class FileKind(
        val extension: String,
        val mimeType: String,
        val defaultFileName: String
    ) {
        Xlsx(
            ".xlsx",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "微信分享的发货清单.xlsx"
        ),
        Xls(
            ".xls",
            "application/vnd.ms-excel",
            "微信分享的发货清单.xls"
        ),
        Zip(
            ".zip",
            "application/zip",
            "微信分享的发货清单压缩包.zip"
        )
    }

    fun handle(intent: Intent?): DeliveryOrderExternalFile? {
        val uri = extractUri(intent) ?: return null
        val intentType = intent?.type.orEmpty().lowercase(Locale.ROOT)
        val resolverType = context.contentResolver.getType(uri).orEmpty().lowercase(Locale.ROOT)
        val rawName = queryDisplayName(uri).ifBlank { fallbackFileName(uri) }
        val kind = detectKind(uri, rawName, intentType, resolverType) ?: return null
        val uploadName = resolveUploadFileName(rawName, kind, intentType, resolverType)
        val cacheFile = copyToCache(uri, uploadName)
        return DeliveryOrderExternalFile(
            path = cacheFile.absolutePath,
            fileName = uploadName,
            mimeType = resolverType.ifBlank { intentType.ifBlank { kind.mimeType } }
        )
    }

    private fun extractUri(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri ?: intent.data
            }
            Intent.ACTION_VIEW -> intent.data
            else -> {
                @Suppress("DEPRECATION")
                intent.data ?: intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
        }
    }

    private fun resolveUploadFileName(
        rawName: String,
        kind: FileKind,
        intentType: String,
        resolverType: String
    ): String {
        val name = rawName.ifBlank { kind.defaultFileName }
        val compactLower = name.lowercase(Locale.ROOT).replace(Regex("\\s+"), "")
        val hasSupportedExtension = FileKind.entries.any { compactLower.endsWith(it.extension) }
        val randomCacheName = name.length > 40 && name.count { it == '_' || it == '-' || it == ' ' } >= 3
        val genericType = intentType.isGenericMimeType() || resolverType.isGenericMimeType()
        val resolved = if (!randomCacheName && hasSupportedExtension && !genericType) {
            name
        } else if (!randomCacheName && hasSupportedExtension) {
            name
        } else {
            kind.defaultFileName
        }
        return sanitizeFileName(resolved)
    }

    private fun detectKind(
        uri: Uri,
        name: String,
        intentType: String,
        resolverType: String
    ): FileKind? {
        val compactLower = name.lowercase(Locale.ROOT).replace(Regex("\\s+"), "")
        return when {
            compactLower.endsWith(".xlsx") -> FileKind.Xlsx
            compactLower.endsWith(".xls") -> FileKind.Xls
            compactLower.endsWith(".zip") -> FileKind.Zip
            intentType.contains("spreadsheetml") || resolverType.contains("spreadsheetml") -> FileKind.Xlsx
            intentType.contains("excel") || resolverType.contains("excel") -> FileKind.Xls
            intentType.contains("zip") || resolverType.contains("zip") -> detectZipKind(uri) ?: FileKind.Zip
            else -> detectByContent(uri)
        }
    }

    private fun detectByContent(uri: Uri): FileKind? {
        val header = ByteArray(8)
        val read = openInput(uri)?.use { input -> input.read(header) } ?: return null
        if (read >= 8 &&
            header[0] == 0xD0.toByte() &&
            header[1] == 0xCF.toByte() &&
            header[2] == 0x11.toByte() &&
            header[3] == 0xE0.toByte() &&
            header[4] == 0xA1.toByte() &&
            header[5] == 0xB1.toByte() &&
            header[6] == 0x1A.toByte() &&
            header[7] == 0xE1.toByte()
        ) {
            return FileKind.Xls
        }
        if (read >= 2 && header[0] == 'P'.code.toByte() && header[1] == 'K'.code.toByte()) {
            return detectZipKind(uri) ?: FileKind.Zip
        }
        return null
    }

    private fun detectZipKind(uri: Uri): FileKind? {
        return runCatching {
            ZipInputStream(openInput(uri) ?: return null).use { zip ->
                repeat(80) {
                    val entry = zip.nextEntry ?: return@use FileKind.Zip
                    val entryName = entry.name.lowercase(Locale.ROOT)
                    if (entryName == "xl/workbook.xml" ||
                        entryName == "[content_types].xml" ||
                        entryName.startsWith("xl/worksheets/")
                    ) {
                        return@use FileKind.Xlsx
                    }
                }
                FileKind.Zip
            }
        }.getOrNull()
    }

    private fun copyToCache(uri: Uri, uploadName: String): File {
        val cacheName = uniqueCacheName(uploadName)
        val file = File(context.cacheDir, cacheName)
        openInput(uri)?.use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        } ?: error("无法读取文件")
        return file
    }

    private fun openInput(uri: Uri) = if (uri.scheme == "file") {
        File(uri.path.orEmpty()).inputStream()
    } else {
        context.contentResolver.openInputStream(uri)
    }

    private fun queryDisplayName(uri: Uri): String {
        return context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index).orEmpty() else ""
        }.orEmpty()
    }

    private fun fallbackFileName(uri: Uri): String {
        return uri.lastPathSegment.orEmpty().substringAfterLast('/').ifBlank { "delivery_order.xlsx" }
    }

    private fun uniqueCacheName(uploadName: String): String {
        val safeName = sanitizeFileName(uploadName)
        val dot = safeName.lastIndexOf('.')
        val prefix = if (dot > 0) safeName.substring(0, dot) else safeName
        val suffix = if (dot > 0) safeName.substring(dot) else ""
        var candidate = safeName
        var index = 1
        while (File(context.cacheDir, candidate).exists()) {
            candidate = "${prefix}_${System.currentTimeMillis()}_${index}${suffix}"
            index += 1
        }
        return candidate
    }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifBlank { "delivery_order.xlsx" }
    }

    private fun String.isGenericMimeType(): Boolean {
        return isBlank() || this == "*/*" || this == "application/octet-stream" || this == "binary/octet-stream"
    }
}
