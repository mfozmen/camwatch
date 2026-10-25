package io.github.mfozmen.camwatch

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }

    override fun onDestroy() {
        lock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
