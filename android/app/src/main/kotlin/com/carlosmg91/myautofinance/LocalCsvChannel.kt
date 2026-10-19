package com.carlosmg91.myautofinance

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.CancellationSignal
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.io.ByteArrayOutputStream
import java.io.InterruptedIOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Solo URI temporal y bytes en memoria. No copia ni permiso persistente. */
class LocalCsvChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "autofinance/local_csv")
    private val reader = Executors.newSingleThreadExecutor()
    private class Selection(val code: Int, val result: MethodChannel.Result) {
        val cancellation = CancellationSignal()
        var reading = false // Solo se consulta en el hilo de UI.
    }
    private var pending: Selection? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "select") {
                result.notImplemented()
            } else if (disposed) {
                result.error("unavailable", "Selector no disponible.", null)
            } else if (pending != null) {
                result.error("busy", "Selección en curso.", null)
            } else if (call.arguments != null &&
                (call.arguments !is Map<*, *> ||
                 (call.arguments as Map<*, *>)["extension"] != "xls")) {
                result.error("readFailed", "Orientación no reconocida.", null)
            } else {
                val xls = call.arguments != null
                // Un resultado tardío de una selección/actividad anterior no
                // puede resolver la petición nueva. No reutilizar códigos.
                val code = nextRequest.getAndIncrement()
                if (code > 65535) {
                    result.error("unavailable", "Reabrir la aplicación para seleccionar.", null)
                    return@setMethodCallHandler
                }
                val selection = Selection(code, result)
                pending = selection
                try {
                    // XLS no prueba formato ni garantiza el MIME del proveedor.
                    // Todos los documentos son elegibles: valida el lector.
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                        putExtra(Intent.EXTRA_TITLE, if (xls)
                            "Seleccionar extracto Openbank (*.xls)" else "Seleccionar CSV")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivityForResult(intent, selection.code)
                } catch (_: SecurityException) {
                    finishError(selection, "accessDenied")
                } catch (_: ActivityNotFoundException) {
                    finishError(selection, "unavailable")
                } catch (_: Exception) {
                    finishError(selection, "readFailed")
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val selection = pending ?: return false
        if (requestCode != selection.code || disposed) return false
        if (selection.reading) return true // Duplicado mientras se lee.
        if (resultCode == Activity.RESULT_CANCELED) {
            pending = null
            selection.result.success(null)
            return true
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri?.scheme != "content" ||
            (data.clipData?.itemCount ?: 0) > 1) {
            finishError(selection, "unavailable")
            return true
        }
        selection.reading = true
        reader.execute {
            try {
                val resolver = activity.contentResolver
                val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                    null, null, null, selection.cancellation)?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
                } ?: throw FileNotFoundException()
                val bytes = resolver.openAssetFileDescriptor(uri, "r", selection.cancellation)?.use { asset ->
                    asset.createInputStream().use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(65536)
                        while (true) {
                            if (disposed || selection.cancellation.isCanceled ||
                                Thread.currentThread().isInterrupted) throw InterruptedIOException()
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                } ?: throw FileNotFoundException()
                activity.runOnUiThread {
                    if (!disposed && pending === selection) {
                        pending = null
                        selection.result.success(mapOf("name" to name, "bytes" to bytes))
                    }
                }
            } catch (_: SecurityException) {
                activity.runOnUiThread { finishError(selection, "accessDenied") }
            } catch (_: FileNotFoundException) {
                activity.runOnUiThread { finishError(selection, "unavailable") }
            } catch (_: Exception) {
                activity.runOnUiThread { finishError(selection, "readFailed") }
            } catch (_: OutOfMemoryError) {
                activity.runOnUiThread { finishError(selection, "readFailed") }
            }
        }
        return true
    }

    private fun finishError(selection: Selection, code: String) {
        if (pending !== selection) return
        pending = null
        selection.result.error(code, "No se pudo leer el archivo seleccionado.", null)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.let {
            it.cancellation.cancel()
            finishError(it, "unavailable")
        }
        reader.shutdownNow()
    }

    companion object { private val nextRequest = AtomicInteger(12000) }
}
