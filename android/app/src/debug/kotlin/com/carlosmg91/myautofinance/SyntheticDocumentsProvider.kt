package com.carlosmg91.myautofinance

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Solo variante debug; protegido por MANAGE_DOCUMENTS. No es un lector XLS. */
class SyntheticDocumentsProvider : DocumentsProvider() {
    private var gate = CountDownLatch(1)
    @Volatile private var started = false
    override fun onCreate() = true
    override fun queryRoots(projection: Array<out String>?): Cursor = MatrixCursor(
        projection ?: arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_FLAGS)
    ).apply {
        val row = newRow()
        columnNames.forEach { row.add(it, when (it) {
            Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID -> "root"
            Root.COLUMN_TITLE -> "Pruebas sintéticas MA-TSK-242"
            Root.COLUMN_FLAGS -> Root.FLAG_SUPPORTS_IS_CHILD
            else -> null
        }) }
    }
    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor =
        document("fixture.csv", projection)
    override fun isChildDocument(parentDocumentId: String, documentId: String) =
        parentDocumentId == "root" && documentId == "fixture.csv"
    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        when (documentId) {
            "denied" -> throw SecurityException()
            "gone" -> throw FileNotFoundException()
            "slow" -> { started = true; check(gate.await(10, TimeUnit.SECONDS)) }
            "release" -> gate.countDown()
            "reset" -> { started = false; gate = CountDownLatch(1) }
        }
        return document(if (documentId == "status") started.toString() else documentId, projection)
    }
    private fun document(id: String, projection: Array<out String>?): Cursor = MatrixCursor(
        projection ?: arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS)
    ).apply {
        val row = newRow()
        columnNames.forEach { row.add(it, when (it) {
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME -> id
            Document.COLUMN_MIME_TYPE -> if (id == "root") Document.MIME_TYPE_DIR else "application/octet-stream"
            Document.COLUMN_FLAGS -> 0
            else -> null
        }) }
    }
    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        check(mode == "r")
        if (documentId == "broken") {
            val pipe = ParcelFileDescriptor.createReliablePipe()
            Thread {
                val output = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
                output.write(PAYLOAD)
                pipe[1].closeWithError("Fallo sintético tras bytes parciales")
                output.close()
            }.start()
            return pipe[0]
        }
        val file = File(requireNotNull(context).cacheDir, "storage-audit-fixture")
        file.writeBytes(PAYLOAD)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
    companion object {
        const val AUTHORITY = "com.carlosmg91.myautofinance.storageaudit.documents"
        val PAYLOAD = byteArrayOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte(), 65, 59, 66, 13, 10, 0, 10)
    }
}
