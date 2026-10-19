package com.carlosmg91.myautofinance

import android.app.Activity
import android.app.Instrumentation
import android.accessibilityservice.AccessibilityService
import android.content.ContentResolver
import android.content.ContentValues
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Ejecutar solo sobre una instalación de prueba APP_ENV=test dedicada.
 * No autoriza Google, importa lotes ni prueba un APK production/teléfono real.
 * Combina resultados inyectados con el selector SAF oficial del sistema.
 */
class StorageAuditInstrumentation : Instrumentation() {
    private var count = 0
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        check(arguments?.getString("syntheticOnly") == "true")
        start()
    }
    override fun onStart() {
        try {
            policy()
            selection()
            officialPicker()
            session()
            finish(Activity.RESULT_OK, Bundle().apply { putString("stream", "MA-TSK-242: $count native checks passed\n") })
        } catch (error: Throwable) {
            // Solo tipo y línea de la prueba; nunca valores/rutas/sesiones.
            finish(Activity.RESULT_CANCELED, Bundle().apply {
                putString("stream", "MA-TSK-242: FAILED ${error.javaClass.simpleName} at ${error.stackTrace.firstOrNull { it.className.startsWith(this@StorageAuditInstrumentation.javaClass.name) }?.lineNumber}\n")
            })
        }
    }
    private fun verify(condition: Boolean) { check(condition); count++ }
    private fun main(block: () -> Unit) = runOnMainSync(block)
    private fun document(id: String) = DocumentsContract.buildDocumentUri(SyntheticDocumentsProvider.AUTHORITY, id)
    private fun command(id: String): String? = targetContext.contentResolver.query(
        document(id), arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
    )?.use { if (it.moveToFirst()) it.getString(0) else null }

    private fun policy() {
        val info = targetContext.applicationInfo
        verify(info.flags and ApplicationInfo.FLAG_ALLOW_BACKUP == 0)
        val permissions = targetContext.packageManager.getPackageInfo(targetContext.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions.orEmpty().toSet()
        verify(permissions.none { it in setOf(
            "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.MANAGE_EXTERNAL_STORAGE", "android.permission.REQUEST_INSTALL_PACKAGES",
            "android.permission.READ_MEDIA_IMAGES", "android.permission.READ_MEDIA_VIDEO", "android.permission.READ_MEDIA_AUDIO"
        ) })
        val expected = setOf("root", "file", "database", "sharedpref", "external", "device_root", "device_file", "device_database", "device_sharedpref")
        for ((resource, sections) in mapOf("backup_rules" to setOf("full-backup-content"), "data_extraction_rules" to setOf("cloud-backup", "device-transfer"))) {
            val id = targetContext.resources.getIdentifier(resource, "xml", targetContext.packageName)
            verify(id != 0)
            val domains = mutableMapOf<String, MutableSet<String>>()
            var section = ""
            targetContext.resources.getXml(id).use { xml ->
                while (xml.eventType != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
                    if (xml.eventType == org.xmlpull.v1.XmlPullParser.START_TAG) {
                        if (xml.name in sections) { section = xml.name; domains[section] = mutableSetOf() }
                        verify(xml.name != "include")
                        if (xml.name == "exclude") {
                            verify(xml.getAttributeValue(null, "path") == ".")
                            domains.getValue(section).add(xml.getAttributeValue(null, "domain"))
                        }
                    }
                    xml.next()
                }
            }
            verify(domains.keys == sections && domains.values.all { it == expected })
        }
    }

    private class Host(private val resolver: ContentResolver) : Activity() {
        var request = -1
        var launched: Intent? = null
        override fun getContentResolver() = resolver
        override fun startActivityForResult(intent: Intent, requestCode: Int) { launched = intent; request = requestCode }
    }
    private class Reply {
        val latch = CountDownLatch(1)
        var value: Any? = null
        var error: String? = null
        var completions = 0
        fun await() { check(latch.await(10, TimeUnit.SECONDS)); check(completions == 1) }
    }
    private class Messenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) { this.handler = handler }
        fun select(xls: Boolean = false): Reply {
            val reply = Reply()
            val codec = StandardMethodCodec.INSTANCE
            val message = codec.encodeMethodCall(MethodCall("select", if (xls) mapOf("extension" to "xls") else null))
            message.flip()
            requireNotNull(handler).onMessage(message) { result ->
                try { result!!.flip(); reply.value = codec.decodeEnvelope(result) }
                catch (error: FlutterException) { reply.error = error.code }
                reply.completions++
                reply.latch.countDown()
            }
            return reply
        }
    }
    private fun selection() {
        lateinit var host: Host
        lateinit var messenger: Messenger
        lateinit var channel: LocalCsvChannel
        fun attach() = main {
            host = Host(targetContext.contentResolver)
            messenger = Messenger()
            channel = LocalCsvChannel(host, messenger)
        }
        fun select(xls: Boolean = false): Reply {
            lateinit var result: Reply
            main { result = messenger.select(xls) }
            return result
        }
        fun deliver(uri: Uri?, result: Int = Activity.RESULT_OK) = main {
            verify(channel.onActivityResult(host.request, result, Intent().apply { data = uri }))
        }
        attach()
        try {
            var reply = select()
            main {
                verify(host.launched!!.action == Intent.ACTION_OPEN_DOCUMENT)
                verify(host.launched!!.hasCategory(Intent.CATEGORY_OPENABLE))
                verify(host.launched!!.flags == Intent.FLAG_GRANT_READ_URI_PERMISSION)
                val busy = messenger.select(); verify(busy.error == "busy")
            }
            deliver(null, Activity.RESULT_CANCELED); reply.await(); verify(reply.value == null && reply.error == null)
            for ((id, code) in mapOf("denied" to "accessDenied", "gone" to "unavailable", "broken" to "readFailed")) {
                reply = select(); deliver(document(id)); reply.await(); verify(reply.error == code && reply.value == null)
            }
            reply = select(); deliver(Uri.parse("file:///does-not-exist.csv")); reply.await(); verify(reply.error == "unavailable")
            for (xls in listOf(false, true)) {
                reply = select(xls); deliver(document(if (xls) "fixture.xls" else "fixture.csv")); reply.await()
                val data = reply.value as Map<*, *>
                verify(reply.error == null && (data["bytes"] as ByteArray).contentEquals(SyntheticDocumentsProvider.PAYLOAD))
            }
            // Proveedor local real, documento propiedad exclusiva de esta prueba.
            if (Build.VERSION.SDK_INT >= 29) {
                val resolver = targetContext.contentResolver
                val uri = requireNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, "autofinance-synthetic-242-${System.nanoTime()}.csv")
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                }))
                try {
                    resolver.openOutputStream(uri)!!.use { it.write(SyntheticDocumentsProvider.PAYLOAD) }
                    reply = select(); deliver(uri); reply.await()
                    verify(((reply.value as Map<*, *>)["bytes"] as ByteArray).contentEquals(SyntheticDocumentsProvider.PAYLOAD))
                } finally { resolver.delete(uri, null, null) }
            }
            // Una entrega diferida conserva la petición; un resultado duplicado
            // durante la lectura no inicia una segunda lectura. Detach cancela.
            command("reset")
            val old = select()
            val oldCode = host.request
            deliver(document("slow"))
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (command("status") != "true" && System.nanoTime() < deadline) Thread.sleep(10)
            verify(command("status") == "true")
            deliver(document("fixture.csv"))
            main { channel.dispose() }
            old.await(); verify(old.error == "unavailable")
            attach()
            val fresh = select()
            main { verify(!channel.onActivityResult(oldCode, Activity.RESULT_CANCELED, null)) }
            command("release")
            deliver(document("fixture.csv")); fresh.await()
            waitForIdleSync()
            verify(old.completions == 1 && fresh.completions == 1 && fresh.error == null)
            verify((fresh.value as Map<*, *>)["name"] == "fixture.csv")
            main { channel.dispose(); channel.dispose() }
        } finally { command("release"); main { channel.dispose() } }
    }

    private fun session() {
        // Registro de prueba aislado. No leer/escribir la sesión habitual.
        val directory = File(targetContext.noBackupFilesDir, "synthetic-audit-${System.nanoTime()}")
        check(directory.mkdir())
        val isolated = object : ContextWrapper(targetContext) { override fun getNoBackupFilesDir() = directory }
        try {
            val store = DriveSessionStore(isolated)
            verify(store.read() == null)
            store.write("metadatos-sinteticos")
            val file = File(directory, "drive-session-v1")
            val encrypted = file.readBytes()
            verify(DriveSessionStore(isolated).read() == "metadatos-sinteticos")
            verify(file.readBytes().contentEquals(encrypted))
            encrypted[encrypted.lastIndex] = (encrypted.last().toInt() xor 1).toByte()
            file.writeBytes(encrypted)
            var failed = false
            try { DriveSessionStore(isolated).read() } catch (_: Exception) { failed = true }
            verify(failed && file.readBytes().contentEquals(encrypted))
            store.clear(); verify(store.read() == null)
        } finally {
            // Solo el directorio exacto creado por esta prueba.
            directory.listFiles().orEmpty().forEach { check(it.delete()) }
            check(directory.delete())
        }
    }

    private fun officialPicker() {
        val activity = startActivitySync(Intent(targetContext, StorageAuditActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as StorageAuditActivity
        val messenger = Messenger()
        fun node(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
            fun find(root: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
                if (root == null) return null
                if (predicate(root)) return root
                for (i in 0 until root.childCount) find(root.getChild(i))?.let { return it }
                return null
            }
            return find(uiAutomation.rootInActiveWindow)
        }
        fun awaitNode(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            while (System.nanoTime() < deadline) {
                node(predicate)?.let { return it }
                Thread.sleep(100)
            }
            error("Selector sintético no visible")
        }
        fun click(initial: AccessibilityNodeInfo) {
            var current: AccessibilityNodeInfo? = initial
            while (current != null && !current.isClickable) current = current.parent
            check(current?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true)
        }
        try {
            lateinit var selected: Reply
            main { activity.attach(messenger); selected = messenger.select() }
            awaitNode { it.packageName?.toString()?.contains("documentsui") == true }
            val title = "Pruebas sintéticas MA-TSK-242"
            if (node { it.text?.toString() == title } == null) {
                click(awaitNode { it.contentDescription?.toString() in setOf("Show roots", "Mostrar raíces", "Mostrar ubicaciones") })
            }
            click(awaitNode { it.text?.toString() == title })
            click(awaitNode { it.text?.toString() == "fixture.csv" })
            // Algunos selectores requieren un botón Abrir/Open adicional.
            if (!selected.latch.await(1, TimeUnit.SECONDS)) {
                node { it.text?.toString()?.uppercase() in setOf("OPEN", "ABRIR", "SELECT", "SELECCIONAR") }?.let { click(it) }
            }
            selected.await()
            waitForIdleSync()
            verify(selected.error == null && ((selected.value as Map<*, *>)["bytes"] as ByteArray).contentEquals(SyntheticDocumentsProvider.PAYLOAD))
            main { verify(activity.pauses > 0 && activity.resumes >= 2) }

            lateinit var cancelled: Reply
            main { cancelled = messenger.select(true) }
            awaitNode { it.packageName?.toString()?.contains("documentsui") == true }
            check(uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK))
            cancelled.await()
            verify(cancelled.value == null && cancelled.error == null)
            main { verify(activity.resumes >= 3) }
        } finally { main { activity.finish() }; waitForIdleSync() }
    }
}
