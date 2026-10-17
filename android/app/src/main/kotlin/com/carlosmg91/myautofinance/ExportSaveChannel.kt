package com.carlosmg91.myautofinance

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors

/** SAF crea un documento nuevo; ningún permiso persistente ni ruta simulada. */
class ExportSaveChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "autofinance/export_save")
    private val writer = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("busy", "Guardado en curso.", null)
            } else {
                val path = call.argument<String>("sourcePath")
                val name = call.argument<String>("suggestedName")
                val mime = call.argument<String>("mimeType")
                val file = path?.let { File(it) }
                if (file == null || !file.isAbsolute || !file.isFile ||
                    name == null || !NAME.matches(name) || mime != "application/zip") {
                    result.error("invalidSource", "ZIP temporal no disponible.", null)
                } else {
                    pending = result
                    source = file
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                            putExtra(Intent.EXTRA_TITLE, name)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }, REQUEST)
                    } catch (_: SecurityException) { finishError("accessDenied")
                    } catch (_: ActivityNotFoundException) { finishError("unavailable")
                    } catch (_: Exception) { finishError("writeFailed") }
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
            source = null
            return true
        }
        val uri = data?.data
        val input = source
        if (resultCode != Activity.RESULT_OK || uri?.scheme != "content" || input == null) {
            finishError("unavailable")
            return true
        }
        writer.execute { copy(input, uri) }
        return true
    }

    private fun copy(input: File, uri: Uri) {
        var ownsDocument = true // documento nuevo según ACTION_CREATE_DOCUMENT
        try {
            val resolver = activity.contentResolver
            // Protección adicional frente a proveedores que incumplan CREATE_DOCUMENT.
            val size = try {
                resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
                    if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
                }
            } catch (_: Exception) {
                // Metadatos opcionales: hay proveedores que solo conceden
                // escritura. La apertura/copia determina el resultado real.
                null
            }
            if (size != null && size > 0) {
                ownsDocument = false
                activity.runOnUiThread { finishError("conflict") }
                return
            }
            input.inputStream().use { from ->
                val descriptor = resolver.openFileDescriptor(uri, "w")
                    ?: throw FileNotFoundException()
                ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { to ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        if (disposed || Thread.currentThread().isInterrupted) throw IOException()
                        val count = from.read(buffer)
                        if (count < 0) break
                        to.write(buffer, 0, count)
                    }
                    to.flush()
                    // Para pipes/proveedores remotos no existe fsync/readback universal.
                    descriptor.checkError()
                } // también propaga errores de cierre antes del éxito
            }
            activity.runOnUiThread {
                pending?.success(mapOf("status" to "saved", "location" to uri.toString()))
                pending = null
                source = null
            }
        } catch (error: Exception) {
            var incomplete = ownsDocument
            if (ownsDocument) {
                try { incomplete = !DocumentsContract.deleteDocument(activity.contentResolver, uri)
                } catch (_: Exception) { /* Se informa del posible archivo incompleto. */ }
            }
            val code = when {
                error is SecurityException -> "accessDenied"
                generateSequence<Throwable>(error) { it.cause }.any {
                    it is ErrnoException && it.errno == OsConstants.ENOSPC
                } -> "noSpace"
                error is FileNotFoundException -> "unavailable"
                else -> "writeFailed"
            }
            activity.runOnUiThread { finishError(code, incomplete) }
        }
    }

    private fun finishError(code: String, incomplete: Boolean = false) {
        pending?.error(code, "No se pudo guardar el ZIP.", mapOf("incompleteMayRemain" to incomplete))
        pending = null
        source = null
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        finishError("unavailable", pending != null)
        writer.shutdownNow()
    }

    companion object {
        const val REQUEST = 11702
        private val NAME = Regex("^autofinance-(datos|copia|prueba)(-[0-9TZ_-]+)?\\.zip$")
    }
}
