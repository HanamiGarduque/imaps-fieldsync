
package com.example.imaps_fieldsync

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {
    private var pickerResult: MethodChannel.Result? = null
    private var destination: Uri? = null
    private var copying = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "imaps_fieldsync/photo_export")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createDocument" -> {
                        if (pickerResult != null || destination != null || copying) {
                            result.error("busy", "Another copy is in progress", null)
                        } else {
                            pickerResult = result
                            try {
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "image/jpeg"
                                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "inspection-photo.jpg")
                                    putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                                }
                                startActivityForResult(intent, 7404)
                            } catch (_: Exception) {
                                pickerResult = null
                                result.error("picker_unavailable", "Save As could not open", null)
                            }
                        }
                    }
                    "copyPhoto" -> {
                        val uri = destination
                        val path = call.argument<String>("path")
                        if (uri == null || path == null || copying) {
                            result.error("invalid_copy", "Choose a new destination", null)
                        } else {
                            copying = true
                            thread(name = "inspection-photo-copy") {
                                try {
                                    // Never read arbitrary/shared files through this native bridge.
                                    val root = File(applicationInfo.dataDir, "app_flutter").canonicalFile
                                    val source = File(path).canonicalFile
                                    require(source.path.startsWith(root.path + File.separator) && source.isFile)
                                    val expected = source.length()
                                    require(expected > 0)
                                    source.inputStream().use { input ->
                                        val output = contentResolver.openOutputStream(uri, "w")
                                            ?: error("Destination inaccessible")
                                        output.use {
                                            check(input.copyTo(it, 32 * 1024) == expected)
                                            it.flush()
                                        }
                                    }
                                    runOnUiThread {
                                        destination = null
                                        copying = false
                                        result.success(null)
                                    }
                                } catch (_: Exception) {
                                    runOnUiThread {
                                        copying = false
                                        result.error("copy_failed", "Check storage and destination access", null)
                                    }
                                }
                            }
                        }
                    }
                    "discardDocument" -> {
                        // Only the fresh ACTION_CREATE_DOCUMENT result, never any source file.
                        if (!copying) {
                            destination?.let { uri ->
                                try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { }
                            }
                            destination = null
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7404) {
            destination = if (resultCode == Activity.RESULT_OK) data?.data else null
            pickerResult?.success(destination != null)
            pickerResult = null
        }
    }
}
