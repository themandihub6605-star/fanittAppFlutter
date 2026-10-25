// File: android/app/src/main/kotlin/fanitt/comapp/fanittapp/MainActivity.kt
package fanitt.comapp.fanittapp

import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Security for the Flutter side (channel "fanitt/device_security"):
 *  - status: developer options / USB debugging / wireless debugging / rooted
 *  - openDeveloperSettings: opens Developer options (or Settings) so the user can switch them off
 *  - integrityToken: Google Play Integrity token (backend checks it)
 *  - setSecure: blocks screenshots / screen recording (FLAG_SECURE) on or off
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fanitt/device_security").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "developerOptions" to globalFlag(Settings.Global.DEVELOPMENT_SETTINGS_ENABLED),
                        "usbDebugging" to globalFlag(Settings.Global.ADB_ENABLED),
                        "wirelessDebugging" to globalFlag("adb_wifi_enabled"),
                        "rooted" to isRooted(),
                    )
                )
                "openDeveloperSettings" -> {
                    openSettings()
                    result.success(null)
                }
                "integrityToken" -> {
                    val nonce = call.argument<String>("nonce")
                    val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
                    if (nonce.isNullOrEmpty() || project == null) {
                        result.error("bad_args", "nonce and cloudProjectNumber are required", null)
                    } else {
                        IntegrityManagerFactory.create(applicationContext)
                            .requestIntegrityToken(
                                IntegrityTokenRequest.builder().setNonce(nonce).setCloudProjectNumber(project).build()
                            )
                            .addOnSuccessListener { response -> result.success(response.token()) }
                            .addOnFailureListener { e -> result.error("integrity_failed", e.message, null) }
                    }
                }
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") == true
                    runOnUiThread {
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun globalFlag(name: String): Boolean =
        try {
            Settings.Global.getInt(contentResolver, name, 0) == 1
        } catch (e: Exception) {
            false
        }

    private fun isRooted(): Boolean {
        val tags = Build.TAGS
        if (tags != null && tags.contains("test-keys")) return true
        val paths = listOf(
            "/system/app/Superuser.apk", "/sbin/su", "/system/bin/su", "/system/xbin/su",
            "/data/local/xbin/su", "/data/local/bin/su", "/system/sd/xbin/su",
            "/system/bin/failsafe/su", "/data/local/su", "/su/bin/su", "/system/xbin/daemonsu",
            "/sbin/.magisk", "/data/adb/magisk",
        )
        return paths.any { path ->
            try {
                File(path).exists()
            } catch (e: Exception) {
                false
            }
        }
    }

    private fun openSettings() {
        try {
            startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) {
            }
        }
    }
}