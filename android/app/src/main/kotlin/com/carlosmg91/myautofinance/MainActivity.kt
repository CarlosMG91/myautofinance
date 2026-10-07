package com.carlosmg91.myautofinance

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var localCsv: LocalCsvChannel? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (localCsv?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        localCsv?.dispose()
        localCsv = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localCsv = LocalCsvChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        val store = DriveSessionStore(this)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "autofinance/drive_session",
            StandardMethodCodec.INSTANCE,
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        )
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(store.read())
                    "write" -> {
                        store.write(call.arguments as String)
                        result.success(null)
                    }
                    "clear" -> {
                        store.clear()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // Nunca devolver excepciones, rutas, contenido ni credenciales.
                result.error("secureStorageFailure", "Almacén seguro no disponible.", null)
            }
        }
    }
}
