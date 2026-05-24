package com.heavenection.app

import android.Manifest
import android.app.DownloadManager
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingDownloadId: Long? = null
    private var pendingInstallFilePath: String? = null
    private var pendingDownloadedVersionCode: Int? = null
    private var pendingDownloadErrorMessage: String? = null
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
                "getBackgroundAccessStatus" -> result.success(buildBackgroundAccessPayload())
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(true)
                }
                "openAutoStartSettings" -> result.success(openAutoStartSettings())
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

        try {
            val parsedUrl = Uri.parse(url)
            if (parsedUrl.scheme.isNullOrBlank()) {
                result.success(
                    mapOf(
                        "status" to "error",
                        "message" to "The update link is not valid.",
                    ),
                )
                return
            }

            val downloadManager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
            pendingDownloadId?.let { existingDownloadId ->
                downloadManager.remove(existingDownloadId)
            }

            val request = DownloadManager.Request(parsedUrl).apply {
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
            pendingDownloadErrorMessage = null
            persistPendingUpdate()
            result.success(
                mapOf(
                    "status" to "started",
                    "message" to "Update download started. Android will ask to install it when the APK is ready.",
                    "downloadId" to downloadId,
                ),
            )
        } catch (_: IllegalArgumentException) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "The update link is invalid.",
                ),
            )
        } catch (_: SecurityException) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "Android blocked this download. Check app permissions and try again.",
                ),
            )
        }
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
        val snapshot = readDownloadSnapshot(downloadId)
        if (snapshot == null) {
            pendingDownloadId = null
            persistPendingUpdate()
            return
        }
        if (snapshot.status != DownloadManager.STATUS_SUCCESSFUL) {
            pendingDownloadId = null
            pendingInstallFilePath = null
            pendingDownloadErrorMessage = downloadFailureMessage(snapshot.reason)
            persistPendingUpdate()
            return
        }

        val uriPath = snapshot.localUri?.let { localUri ->
            val parsedUri = Uri.parse(localUri)
            if (parsedUri.scheme == "file") parsedUri.path else null
        }
        if (!uriPath.isNullOrBlank()) {
            pendingInstallFilePath = uriPath
        }
        pendingDownloadId = null
        pendingDownloadErrorMessage = null
        persistPendingUpdate()

        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            attemptInstallDownloadedApk()
        }
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
        try {
            startActivity(launchIntent)
        } catch (_: ActivityNotFoundException) {
            // Install page is unavailable on this device right now.
        } catch (_: SecurityException) {
            // Android blocked this launch. Flutter side can ask user to retry from foreground.
        }
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

    private fun buildBackgroundAccessPayload(): Map<String, Any> {
        val manufacturer = Build.MANUFACTURER.orEmpty()
        val brand = Build.BRAND.orEmpty()
        val model = Build.MODEL.orEmpty()
        val batteryUnrestricted = isBatteryOptimizationIgnored()
        return mapOf(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "model" to model,
            "batteryUnrestricted" to batteryUnrestricted,
            // Android does not expose a reliable public API to read OEM autostart toggle state.
            "autoStartStatusKnown" to false,
        )
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val powerManager = getSystemService(POWER_SERVICE) as? PowerManager
        return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
    }

    private fun openBatteryOptimizationSettings() {
        val intents = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            intents += Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            )
            intents += Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
        intents += Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        launchFirstAvailableIntent(intents)
    }

    private fun openAutoStartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.orEmpty().lowercase()
        val intents = mutableListOf<Intent>()

        when {
            manufacturer.contains("oneplus") ||
                manufacturer.contains("oppo") ||
                manufacturer.contains("realme") -> {
                intents += componentIntent(
                    "com.oplus.safecenter",
                    "com.oplus.startupapp.view.StartupAppListActivity",
                )
                intents += componentIntent(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                )
                intents += componentIntent(
                    "com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                )
                intents += componentIntent(
                    "com.oneplus.security",
                    "com.oneplus.security.auto.launch.view.AutoLaunchAppListActivity",
                )
            }
            manufacturer.contains("xiaomi") ||
                manufacturer.contains("redmi") ||
                manufacturer.contains("poco") -> {
                intents += componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            }
            manufacturer.contains("vivo") ||
                manufacturer.contains("iqoo") -> {
                intents += componentIntent(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                )
                intents += componentIntent(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
                )
            }
            manufacturer.contains("huawei") ||
                manufacturer.contains("honor") -> {
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                )
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                )
            }
            manufacturer.contains("samsung") -> {
                intents += Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            }
        }

        intents += Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        return launchFirstAvailableIntent(intents)
    }

    private fun componentIntent(packageName: String, className: String): Intent {
        return Intent().apply {
            component = ComponentName(packageName, className)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun launchFirstAvailableIntent(intents: List<Intent>): Boolean {
        intents.forEach { intent ->
            val safeIntent = intent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            if (safeIntent.resolveActivity(packageManager) != null) {
                try {
                    startActivity(safeIntent)
                    return true
                } catch (_: ActivityNotFoundException) {
                    // Continue to next available intent.
                } catch (_: SecurityException) {
                    // Continue to next available intent.
                }
            }
        }
        return false
    }

    private fun startInstallForDownloadedUpdate(): Map<String, Any> {
        val status = buildDownloadedUpdateStatus(null)
        if (status["isDownloaded"] != true) {
            if (status["hasFailed"] == true) {
                return mapOf(
                    "status" to "error",
                    "message" to (status["message"] ?: "Update download failed."),
                )
            }
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
            return mapOf(
                "isDownloaded" to false,
                "isDownloading" to false,
                "hasFailed" to false,
                "versionCode" to 0,
            )
        }

        val matchesRequestedVersion =
            requestedVersionCode == null || requestedVersionCode <= 0 || requestedVersionCode == storedVersionCode
        if (!matchesRequestedVersion) {
            return mapOf(
                "isDownloaded" to false,
                "isDownloading" to false,
                "hasFailed" to false,
                "versionCode" to storedVersionCode,
            )
        }

        if (!pendingDownloadErrorMessage.isNullOrBlank()) {
            return mapOf(
                "isDownloaded" to false,
                "isDownloading" to false,
                "hasFailed" to true,
                "message" to (pendingDownloadErrorMessage ?: "Update download failed."),
                "versionCode" to storedVersionCode,
            )
        }

        pendingDownloadId?.let { activeDownloadId ->
            val snapshot = readDownloadSnapshot(activeDownloadId)
            if (snapshot == null) {
                pendingDownloadId = null
                persistPendingUpdate()
            } else {
                when (snapshot.status) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        val uriPath = snapshot.localUri?.let { localUri ->
                            val parsedUri = Uri.parse(localUri)
                            if (parsedUri.scheme == "file") parsedUri.path else null
                        }
                        if (!uriPath.isNullOrBlank()) {
                            pendingInstallFilePath = uriPath
                        }
                        pendingDownloadId = null
                        pendingDownloadErrorMessage = null
                        persistPendingUpdate()
                    }
                    DownloadManager.STATUS_FAILED -> {
                        pendingDownloadId = null
                        pendingInstallFilePath = null
                        pendingDownloadErrorMessage = downloadFailureMessage(snapshot.reason)
                        persistPendingUpdate()
                        return mapOf(
                            "isDownloaded" to false,
                            "isDownloading" to false,
                            "hasFailed" to true,
                            "message" to (pendingDownloadErrorMessage ?: "Update download failed."),
                            "versionCode" to storedVersionCode,
                            "downloadStatus" to snapshot.status,
                            "downloadReason" to snapshot.reason,
                        )
                    }
                    DownloadManager.STATUS_PENDING,
                    DownloadManager.STATUS_RUNNING,
                    DownloadManager.STATUS_PAUSED -> {
                        return mapOf(
                            "isDownloaded" to false,
                            "isDownloading" to true,
                            "hasFailed" to false,
                            "message" to downloadProgressMessage(snapshot.status, snapshot.reason),
                            "versionCode" to storedVersionCode,
                            "downloadStatus" to snapshot.status,
                            "downloadReason" to snapshot.reason,
                        )
                    }
                    else -> {
                        return mapOf(
                            "isDownloaded" to false,
                            "isDownloading" to false,
                            "hasFailed" to false,
                            "versionCode" to storedVersionCode,
                            "downloadStatus" to snapshot.status,
                            "downloadReason" to snapshot.reason,
                        )
                    }
                }
            }
        }

        val fileExists = !pendingInstallFilePath.isNullOrBlank() && File(pendingInstallFilePath!!).exists()
        if (!fileExists) {
            if (pendingDownloadId == null) {
                clearPersistedPendingUpdate()
            }
            return mapOf(
                "isDownloaded" to false,
                "isDownloading" to false,
                "hasFailed" to false,
                "versionCode" to storedVersionCode,
            )
        }

        return mapOf(
            "isDownloaded" to true,
            "isDownloading" to false,
            "hasFailed" to false,
            "versionCode" to storedVersionCode,
            "filePath" to (pendingInstallFilePath ?: ""),
        )
    }

    private fun readDownloadSnapshot(downloadId: Long): DownloadSnapshot? {
        val downloadManager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId))
        cursor.use {
            if (!it.moveToFirst()) {
                return null
            }
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val localUriIndex = it.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
            val localUri = if (localUriIndex != -1) it.getString(localUriIndex) else null
            return DownloadSnapshot(status = status, reason = reason, localUri = localUri)
        }
    }

    private fun downloadProgressMessage(status: Int, reason: Int): String {
        return when (status) {
            DownloadManager.STATUS_PENDING -> "Waiting to start update download."
            DownloadManager.STATUS_RUNNING -> "Update download is in progress."
            DownloadManager.STATUS_PAUSED -> when (reason) {
                DownloadManager.PAUSED_WAITING_FOR_NETWORK -> "Waiting for internet to continue update download."
                DownloadManager.PAUSED_WAITING_TO_RETRY -> "Retrying update download."
                DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "Waiting for Wi-Fi to continue update download."
                else -> "Update download is temporarily paused."
            }
            else -> "Preparing update download."
        }
    }

    private fun downloadFailureMessage(reason: Int): String {
        return when (reason) {
            DownloadManager.ERROR_CANNOT_RESUME -> "Update download failed because Android cannot resume this file."
            DownloadManager.ERROR_DEVICE_NOT_FOUND -> "Update download failed because storage is not available."
            DownloadManager.ERROR_FILE_ALREADY_EXISTS -> "Update file already exists. Please retry the update."
            DownloadManager.ERROR_FILE_ERROR -> "Update download failed due to a file storage error."
            DownloadManager.ERROR_HTTP_DATA_ERROR -> "Update download failed because of a server response error."
            DownloadManager.ERROR_INSUFFICIENT_SPACE -> "Update download failed because storage space is low."
            DownloadManager.ERROR_TOO_MANY_REDIRECTS -> "Update download failed due to too many redirects."
            DownloadManager.ERROR_UNHANDLED_HTTP_CODE -> "Update download failed because the server rejected the request."
            DownloadManager.ERROR_UNKNOWN -> "Update download failed due to an unknown Android error."
            else -> if (reason in 100..599) {
                "Update download failed with server error $reason."
            } else {
                "Update download failed. Please check internet and retry."
            }
        }
    }

    private fun persistPendingUpdate() {
        updaterPreferences()
            .edit()
            .putLong(KEY_PENDING_DOWNLOAD_ID, pendingDownloadId ?: -1L)
            .putString(KEY_PENDING_FILE_PATH, pendingInstallFilePath)
            .putInt(KEY_PENDING_VERSION_CODE, pendingDownloadedVersionCode ?: 0)
            .putString(KEY_PENDING_ERROR_MESSAGE, pendingDownloadErrorMessage)
            .apply()
    }

    private fun loadPersistedPendingUpdate() {
        val preferences = updaterPreferences()
        pendingDownloadId = preferences.getLong(KEY_PENDING_DOWNLOAD_ID, -1L).takeIf { it > 0L }
        pendingInstallFilePath = preferences.getString(KEY_PENDING_FILE_PATH, null)
        pendingDownloadedVersionCode = preferences.getInt(KEY_PENDING_VERSION_CODE, 0).takeIf { it > 0 }
        pendingDownloadErrorMessage = preferences.getString(KEY_PENDING_ERROR_MESSAGE, null)
    }

    private fun clearPersistedPendingUpdate() {
        pendingDownloadId = null
        pendingInstallFilePath = null
        pendingDownloadedVersionCode = null
        pendingDownloadErrorMessage = null
        updaterPreferences()
            .edit()
            .remove(KEY_PENDING_DOWNLOAD_ID)
            .remove(KEY_PENDING_FILE_PATH)
            .remove(KEY_PENDING_VERSION_CODE)
            .remove(KEY_PENDING_ERROR_MESSAGE)
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

    private data class DownloadSnapshot(
        val status: Int,
        val reason: Int,
        val localUri: String?,
    )

    companion object {
        private const val CHANNEL_NAME = "heavenection/updater"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val PREFS_NAME = "heavenection_updater"
        private const val KEY_PENDING_DOWNLOAD_ID = "pending_download_id"
        private const val KEY_PENDING_FILE_PATH = "pending_file_path"
        private const val KEY_PENDING_VERSION_CODE = "pending_version_code"
        private const val KEY_PENDING_ERROR_MESSAGE = "pending_error_message"
        private const val REQUEST_READ_PHONE_STATE_PERMISSION = 4201
        private const val REQUEST_REQUIRED_PERMISSIONS = 4202
    }
}
