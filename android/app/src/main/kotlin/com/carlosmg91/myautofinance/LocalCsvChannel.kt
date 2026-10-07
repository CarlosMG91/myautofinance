package com.carlosmg91.myautofinance

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.Executors

/** Solo URI temporal y bytes en memoria. No copia ni permiso persistente. */
class LocalCsvChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "autofinance/local_csv")
    private val reader = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "select") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("busy", "Selección en curso.", null)
            } else {
                pending = result
                try {
                    // El proveedor puede etiquetar CSV como texto u octet-stream.
                    // Todos los documentos son elegibles: valida el lector CSV.
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                        putExtra(Intent.EXTRA_TITLE, "Seleccionar CSV")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivityForResult(intent, REQUEST)
                } catch (_: SecurityException) {
                    finishError("accessDenied")
                } catch (_: ActivityNotFoundException) {
                    finishError("unavailable")
                } catch (_: Exception) {
                    finishError("readFailed")
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        if (pending == null) return true
        if (resultCode == Activity.RESULT_CANCELED) {
            pending?.success(null)
            pending = null
            return true
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null ||
            (data?.clipData?.itemCount ?: 0) > 1) {
            finishError("unavailable")
            return true
        }
        reader.execute {
            try {
                val resolver = activity.contentResolver
                val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                    null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                } ?: throw FileNotFoundException()
                val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw FileNotFoundException()
                activity.runOnUiThread {
                    pending?.success(mapOf("name" to name, "bytes" to bytes))
                    pending = null
                }
            } catch (_: SecurityException) {
                activity.runOnUiThread { finishError("accessDenied") }
            } catch (_: FileNotFoundException) {
                activity.runOnUiThread { finishError("unavailable") }
            } catch (_: Exception) {
                activity.runOnUiThread { finishError("readFailed") }
            } catch (_: OutOfMemoryError) {
                activity.runOnUiThread { finishError("readFailed") }
            }
        }
        return true
    }

    private fun finishError(code: String) {
        pending?.error(code, "No se pudo leer el archivo seleccionado.", null)
        pending = null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        finishError("unavailable")
        reader.shutdownNow()
    }

    companion object { const val REQUEST = 11701 }
}
