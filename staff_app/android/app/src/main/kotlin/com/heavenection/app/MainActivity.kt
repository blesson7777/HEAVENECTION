package com.heavenection.app

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingDownloadId: Long? = null
    private var pendingInstallFilePath: String? = null
    private var isDownloadReceiverRegistered = false

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
                return
            }
            val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
            if (downloadId <= 0L || pendingDownloadId != downloadId) {
                return
            }
            handleCompletedDownload(downloadId)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerDownloadReceiverIfNeeded()
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterDownloadReceiverIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        if (canInstallPackages() && !pendingInstallFilePath.isNullOrBlank()) {
            attemptInstallDownloadedApk()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersionInfo" -> result.success(buildVersionInfoPayload())
                "downloadAppUpdate" -> handleDownloadRequest(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleDownloadRequest(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url").orEmpty().trim()
        if (url.isBlank()) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "The update link is missing for this release.",
                ),
            )
            return
        }

        val fileName = sanitizeFileName(call.argument<String>("fileName"))
        val title = call.argument<String>("title").orEmpty().ifBlank {
            "HEAVENECTION Update"
        }
        val description = call.argument<String>("description").orEmpty().ifBlank {
            "Downloading the latest HEAVENECTION APK."
        }
        val downloadsDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        if (downloadsDir == null) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "Download storage is not available on this device.",
                ),
            )
            return
        }

        val targetFile = File(downloadsDir, fileName)
        if (targetFile.exists()) {
            targetFile.delete()
        }

        val downloadManager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        pendingDownloadId?.let { existingDownloadId ->
            downloadManager.remove(existingDownloadId)
        }

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(title)
            setDescription(description)
            setMimeType(APK_MIME_TYPE)
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationInExternalFilesDir(
                this@MainActivity,
                Environment.DIRECTORY_DOWNLOADS,
                fileName,
            )
        }

        val downloadId = downloadManager.enqueue(request)
        pendingDownloadId = downloadId
        pendingInstallFilePath = targetFile.absolutePath
        result.success(
            mapOf(
                "status" to "started",
                "message" to "Update download started. Android will ask to install it when the APK is ready.",
                "downloadId" to downloadId,
            ),
        )
    }

    private fun registerDownloadReceiverIfNeeded() {
        if (isDownloadReceiverRegistered) {
            return
        }
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(downloadReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(downloadReceiver, filter)
        }
        isDownloadReceiverRegistered = true
    }

    private fun unregisterDownloadReceiverIfNeeded() {
        if (!isDownloadReceiverRegistered) {
            return
        }
        unregisterReceiver(downloadReceiver)
        isDownloadReceiverRegistered = false
    }

    private fun handleCompletedDownload(downloadId: Long) {
        val downloadManager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId))
        cursor.use {
            if (!it.moveToFirst()) {
                pendingDownloadId = null
                return
            }
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (status != DownloadManager.STATUS_SUCCESSFUL) {
                pendingDownloadId = null
                pendingInstallFilePath = null
                return
            }
            val localUriIndex = it.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
            if (localUriIndex != -1) {
                val localUriValue = it.getString(localUriIndex)
                if (!localUriValue.isNullOrBlank()) {
                    val parsedUri = Uri.parse(localUriValue)
                    if (parsedUri.scheme == "file" && !parsedUri.path.isNullOrBlank()) {
                        pendingInstallFilePath = parsedUri.path
                    }
                }
            }
        }
        pendingDownloadId = null
        attemptInstallDownloadedApk()
    }

    private fun attemptInstallDownloadedApk() {
        val filePath = pendingInstallFilePath ?: return
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            pendingInstallFilePath = null
            return
        }
        if (!canInstallPackages()) {
            openUnknownAppSourcesSettings()
            return
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile,
        )
        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = apkUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }

        val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        val launchIntent = if (installIntent.resolveActivity(packageManager) != null) {
            installIntent
        } else {
            fallbackIntent
        }
        startActivity(launchIntent)
        pendingInstallFilePath = null
    }

    private fun openUnknownAppSourcesSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun canInstallPackages(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
    }

    private fun buildVersionInfoPayload(): Map<String, Any> {
        val packageInfo = readPackageInfo()
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode
        }
        return mapOf(
            "versionName" to (packageInfo.versionName ?: ""),
            "versionCode" to versionCode,
            "packageName" to packageName,
            "canInstallPackages" to canInstallPackages(),
        )
    }

    private fun readPackageInfo(): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
    }

    private fun sanitizeFileName(fileName: String?): String {
        val sanitized = fileName
            .orEmpty()
            .trim()
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "heavenection-update.apk" }
        return if (sanitized.endsWith(".apk", ignoreCase = true)) sanitized else "$sanitized.apk"
    }

    companion object {
        private const val CHANNEL_NAME = "heavenection/updater"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }
}
