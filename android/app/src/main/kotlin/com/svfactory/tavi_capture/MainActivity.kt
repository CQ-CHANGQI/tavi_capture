package com.svfactory.tavi_capture

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicast: WifiManager.MulticastLock? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "tavi/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (multicast == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicast = wifi.createMulticastLock("tavi-preview").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    }
                    "release" -> { releaseMulticast(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
    private fun releaseMulticast() { multicast?.release(); multicast = null }
    override fun onDestroy() { releaseMulticast(); super.onDestroy() }
}
