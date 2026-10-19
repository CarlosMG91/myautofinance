package com.carlosmg91.myautofinance

import android.content.Context
import android.os.Build
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest

// Fixture overlay only. Not compiled into the application's normal APK.
object UpgradeProbeChannel {
    fun attach(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "autofinance/upgrade_probe")
            .setMethodCallHandler { call, result ->
                if (call.method != "inspect") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    val info = context.packageManager.getPackageInfo(context.packageName, 0)
                    val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    val alias = "autofinance.drive.session.v1"
                    check(keys.containsAlias(alias))
                    val encrypted = File(context.noBackupFilesDir, "drive-session-v1").readBytes()
                    val hash = MessageDigest.getInstance("SHA-256").digest(encrypted)
                        .joinToString("") { "%02x".format(it) }
                    @Suppress("DEPRECATION")
                    result.success(mapOf("package" to context.packageName,
                        "versionName" to info.versionName, "versionCode" to info.versionCode,
                        "api" to Build.VERSION.SDK_INT, "abis" to Build.SUPPORTED_ABIS.toList(),
                        "pageSize" to Os.sysconf(OsConstants._SC_PAGESIZE),
                        "keyAlias" to alias, "keyCreated" to keys.getCreationDate(alias).time,
                        "ciphertextSha256" to hash))
                } catch (_: Exception) { result.error("probeFailed", "Native fixture probe failed", null) }
            }
    }
}
