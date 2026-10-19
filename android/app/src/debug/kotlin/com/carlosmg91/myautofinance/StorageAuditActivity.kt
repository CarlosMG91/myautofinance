package com.carlosmg91.myautofinance

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger

/** Host de instrumentación sin Flutter/SQLite, solo en debug y no exportado. */
class StorageAuditActivity : Activity() {
    private var selector: LocalCsvChannel? = null
    var pauses = 0
        private set
    var resumes = 0
        private set

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setContentView(TextView(this).apply { text = "Prueba sintética SAF · MA-TSK-242" })
    }
    fun attach(messenger: BinaryMessenger) { selector = LocalCsvChannel(this, messenger) }
    override fun onPause() { pauses++; super.onPause() }
    override fun onResume() { super.onResume(); resumes++ }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (selector?.onActivityResult(requestCode, resultCode, data) != true) super.onActivityResult(requestCode, resultCode, data)
    }
    override fun onDestroy() { selector?.dispose(); selector = null; super.onDestroy() }
}
