package io.github.mfozmen.camwatch

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var lock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.mfozmen.camwatch/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (lock == null) {
                            // Null on Ethernet-only boxes: then there is nothing to hold.
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            lock = wifi?.createMulticastLock("camwatch")?.also { it.setReferenceCounted(false) }
                        }
                        lock?.acquire()
                        result.success(null)
                    }
                    "release" -> {
                        lock?.takeIf { it.isHeld }?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.mfozmen.camwatch/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> result.success(install(File(call.arguments as String)))
                    else -> result.notImplemented()
                }
            }
    }

    /// Hands a downloaded APK to the system installer. "blocked" when the user
    /// has not yet allowed camwatch to install apps: the settings page for
    /// that opens instead, and the Dart side says what to do.
    private fun install(apk: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return "blocked"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.update", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        )
        return "started"
    }

    override fun onDestroy() {
        lock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
