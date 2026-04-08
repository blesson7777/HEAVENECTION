package com.heavenection.app

import android.Manifest
import android.app.DownloadManager
import android.content.pm.PackageManager.PERMISSION_GRANTED
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
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingDownloadId: Long? = null
    private var pendingInstallFilePath: String? = null
    private var pendingDownloadedVersionCode: Int? = null
    private var isDownloadReceiverRegistered = false
    private var resumeInstallAfterSettings = false
    private var pendingPhoneStatePermissionResult: MethodChannel.Result? = null
    private var pendingRequiredPermissionsResult: MethodChannel.Result? = null

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
        loadPersistedPendingUpdate()
        registerDownloadReceiverIfNeeded()
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterDownloadReceiverIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        if (resumeInstallAfterSettings && canInstallPackages() && !pendingInstallFilePath.isNullOrBlank()) {
            resumeInstallAfterSettings = false
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
                "isCallInProgress" -> result.success(buildCallStatePayload())
                "requestPhoneStatePermission" -> handlePhoneStatePermissionRequest(result)
                "getRequiredPermissionStatus" -> result.success(buildRequiredPermissionPayload())
                "requestRequiredPermissions" -> handleRequiredPermissionsRequest(result)
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "getDownloadedUpdateStatus" -> result.success(
                    buildDownloadedUpdateStatus(call.argument<Int>("versionCode")),
                )
                "downloadAppUpdate" -> handleDownloadRequest(call, result)
                "installDownloadedUpdate" -> result.success(startInstallForDownloadedUpdate())
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_READ_PHONE_STATE_PERMISSION -> {
                val granted = grantResults.firstOrNull() == PERMISSION_GRANTED
                pendingPhoneStatePermissionResult?.success(
                    mapOf(
                        "granted" to granted,
                    ),
                )
                pendingPhoneStatePermissionResult = null
            }
            REQUEST_REQUIRED_PERMISSIONS -> {
                pendingRequiredPermissionsResult?.success(buildRequiredPermissionPayload())
                pendingRequiredPermissionsResult = null
            }
            else -> return
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
        val versionCode = (call.argument<Int>("versionCode") ?: 0).takeIf { it > 0 }
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
        pendingDownloadedVersionCode = versionCode
        persistPendingUpdate()
        result.success(
            mapOf(
                "status" to "started",
                "message" to "Update download started. Android will ask to install it when the APK is ready.",
                "downloadId" to downloadId,
            ),
        )
    }

    private fun handlePhoneStatePermissionRequest(result: MethodChannel.Result) {
        if (hasReadPhoneStatePermission()) {
            result.success(mapOf("granted" to true))
            return
        }
        if (pendingPhoneStatePermissionResult != null) {
            result.success(mapOf("granted" to false))
            return
        }
        pendingPhoneStatePermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_PHONE_STATE),
            REQUEST_READ_PHONE_STATE_PERMISSION,
        )
    }

    private fun handleRequiredPermissionsRequest(result: MethodChannel.Result) {
        if (hasAllRequiredPermissions()) {
            result.success(buildRequiredPermissionPayload())
            return
        }
        if (pendingRequiredPermissionsResult != null) {
            result.success(buildRequiredPermissionPayload())
            return
        }
        val missingPermissions = requiredPermissions().filterNot { hasPermission(it) }
        if (missingPermissions.isEmpty()) {
            result.success(buildRequiredPermissionPayload())
            return
        }
        pendingRequiredPermissionsResult = result
        ActivityCompat.requestPermissions(
            this,
            missingPermissions.toTypedArray(),
            REQUEST_REQUIRED_PERMISSIONS,
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
                persistPendingUpdate()
                return
            }
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (status != DownloadManager.STATUS_SUCCESSFUL) {
                clearPersistedPendingUpdate()
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
        persistPendingUpdate()
        attemptInstallDownloadedApk()
    }

    private fun attemptInstallDownloadedApk() {
        val filePath = pendingInstallFilePath ?: return
        val storedVersionCode = pendingDownloadedVersionCode ?: 0
        if (storedVersionCode > 0 && readInstalledVersionCode() >= storedVersionCode) {
            clearPersistedPendingUpdate()
            return
        }
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            clearPersistedPendingUpdate()
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
    }

    private fun openUnknownAppSourcesSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        resumeInstallAfterSettings = true
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun startInstallForDownloadedUpdate(): Map<String, Any> {
        val status = buildDownloadedUpdateStatus(null)
        if (status["isDownloaded"] != true) {
            return mapOf(
                "status" to "missing",
                "message" to "The downloaded update file is no longer available on this device.",
            )
        }
        attemptInstallDownloadedApk()
        return mapOf(
            "status" to "started",
            "message" to "Android is opening the installer for the downloaded update.",
        )
    }

    private fun buildDownloadedUpdateStatus(requestedVersionCode: Int?): Map<String, Any> {
        loadPersistedPendingUpdate()
        val storedVersionCode = pendingDownloadedVersionCode ?: 0
        if (storedVersionCode > 0 && readInstalledVersionCode() >= storedVersionCode) {
            clearPersistedPendingUpdate()
            return mapOf("isDownloaded" to false, "versionCode" to 0)
        }

        val matchesRequestedVersion =
            requestedVersionCode == null || requestedVersionCode <= 0 || requestedVersionCode == storedVersionCode
        if (!matchesRequestedVersion) {
            return mapOf("isDownloaded" to false, "versionCode" to storedVersionCode)
        }

        if (pendingDownloadId != null && !isDownloadSuccessful(pendingDownloadId!!)) {
            return mapOf("isDownloaded" to false, "versionCode" to storedVersionCode)
        }

        val fileExists = !pendingInstallFilePath.isNullOrBlank() && File(pendingInstallFilePath!!).exists()
        if (!fileExists) {
            if (pendingDownloadId == null) {
                clearPersistedPendingUpdate()
            }
            return mapOf("isDownloaded" to false, "versionCode" to storedVersionCode)
        }

        if (pendingDownloadId != null) {
            pendingDownloadId = null
            persistPendingUpdate()
        }
        return mapOf(
            "isDownloaded" to true,
            "versionCode" to storedVersionCode,
            "filePath" to (pendingInstallFilePath ?: ""),
        )
    }

    private fun isDownloadSuccessful(downloadId: Long): Boolean {
        val downloadManager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId))
        cursor.use {
            if (!it.moveToFirst()) {
                return false
            }
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            return status == DownloadManager.STATUS_SUCCESSFUL
        }
    }

    private fun persistPendingUpdate() {
        updaterPreferences()
            .edit()
            .putLong(KEY_PENDING_DOWNLOAD_ID, pendingDownloadId ?: -1L)
            .putString(KEY_PENDING_FILE_PATH, pendingInstallFilePath)
            .putInt(KEY_PENDING_VERSION_CODE, pendingDownloadedVersionCode ?: 0)
            .apply()
    }

    private fun loadPersistedPendingUpdate() {
        val preferences = updaterPreferences()
        pendingDownloadId = preferences.getLong(KEY_PENDING_DOWNLOAD_ID, -1L).takeIf { it > 0L }
        pendingInstallFilePath = preferences.getString(KEY_PENDING_FILE_PATH, null)
        pendingDownloadedVersionCode = preferences.getInt(KEY_PENDING_VERSION_CODE, 0).takeIf { it > 0 }
    }

    private fun clearPersistedPendingUpdate() {
        pendingDownloadId = null
        pendingInstallFilePath = null
        pendingDownloadedVersionCode = null
        updaterPreferences()
            .edit()
            .remove(KEY_PENDING_DOWNLOAD_ID)
            .remove(KEY_PENDING_FILE_PATH)
            .remove(KEY_PENDING_VERSION_CODE)
            .apply()
    }

    private fun updaterPreferences() = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun canInstallPackages(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
    }

    private fun buildVersionInfoPayload(): Map<String, Any> {
        val packageInfo = readPackageInfo()
        return mapOf(
            "versionName" to (packageInfo.versionName ?: ""),
            "versionCode" to readInstalledVersionCode(packageInfo),
            "packageName" to packageName,
            "canInstallPackages" to canInstallPackages(),
        )
    }

    private fun buildRequiredPermissionPayload(): Map<String, Any> {
        val canCallPhone = hasPermission(Manifest.permission.CALL_PHONE)
        val canReadCallLog = hasPermission(Manifest.permission.READ_CALL_LOG)
        val canReadPhoneState = hasReadPhoneStatePermission()
        return mapOf(
            "callPhoneGranted" to canCallPhone,
            "callLogGranted" to canReadCallLog,
            "phoneStateGranted" to canReadPhoneState,
            "allGranted" to (canCallPhone && canReadCallLog && canReadPhoneState),
        )
    }

    private fun buildCallStatePayload(): Map<String, Any> {
        if (!hasReadPhoneStatePermission()) {
            return mapOf(
                "permissionGranted" to false,
                "isInCall" to false,
            )
        }

        val telecomManager = getSystemService(TELECOM_SERVICE) as? TelecomManager
        val telephonyManager = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
        val isInCall = try {
            telecomManager?.isInCall == true ||
                telephonyManager?.callState == TelephonyManager.CALL_STATE_OFFHOOK ||
                telephonyManager?.callState == TelephonyManager.CALL_STATE_RINGING
        } catch (_: SecurityException) {
            false
        }

        return mapOf(
            "permissionGranted" to true,
            "isInCall" to isInCall,
        )
    }

    private fun hasReadPhoneStatePermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_PHONE_STATE,
        ) == PERMISSION_GRANTED
    }

    private fun requiredPermissions(): List<String> {
        return listOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE,
        )
    }

    private fun hasAllRequiredPermissions(): Boolean {
        return requiredPermissions().all { hasPermission(it) }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(this, permission) == PERMISSION_GRANTED
    }

    private fun readInstalledVersionCode(packageInfo: PackageInfo = readPackageInfo()): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode
        }
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
        private const val PREFS_NAME = "heavenection_updater"
        private const val KEY_PENDING_DOWNLOAD_ID = "pending_download_id"
        private const val KEY_PENDING_FILE_PATH = "pending_file_path"
        private const val KEY_PENDING_VERSION_CODE = "pending_version_code"
        private const val REQUEST_READ_PHONE_STATE_PERMISSION = 4201
        private const val REQUEST_REQUIRED_PERMISSIONS = 4202
    }
}
