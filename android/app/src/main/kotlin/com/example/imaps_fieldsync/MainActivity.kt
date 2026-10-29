
package com.example.imaps_fieldsync

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Looper
import android.provider.DocumentsContract
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {
    private var pickerResult: MethodChannel.Result? = null
    private var destination: Uri? = null
    private var copying = false
    private var protectionChannel: MethodChannel? = null
    private var protectionAttached = false
    private var protectionSession = 0L
    private var lastProtectionRequest = 0L
    private var protectionCover: View? = null

    private companion object {
        // UI-thread owned, and never reused across replacement Activities.
        var nextProtectionSession = 0L
    }

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
        configureScreenProtection(flutterEngine)
    }

    private fun positiveProtectionId(value: Any?): Long {
        require(value is Int || value is Long)
        return (value as Number).toLong().also { require(it > 0) }
    }

    private fun configureScreenProtection(flutterEngine: FlutterEngine) {
        protectionAttached = true
        protectionSession = 0L
        coverProtectionWindow()
        try {
            check(Looper.myLooper() == Looper.getMainLooper())
            check(!isFinishing && !isDestroyed)
            val activeWindow = window ?: error("No attached window")
            activeWindow.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            check((activeWindow.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        } catch (_: Exception) {
            // Keep the native cover. A real request must confirm this window
            // before the cover can be removed; attachment itself is not an ACK.
        }
        protectionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "imaps_fieldsync/screen_protection_ack",
        ).also { channel ->
            // The default platform queue is the UI thread. Never defer a flag
            // write to a worker: mutation and readback must be one ordered turn.
            channel.setMethodCallHandler { call, result ->
                if (call.method != "beginSession" && call.method != "setSecure") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    check(Looper.myLooper() == Looper.getMainLooper())
                    if (!protectionAttached || isFinishing || isDestroyed) {
                        result.error("activity_unavailable", "No attached Activity", null)
                        return@setMethodCallHandler
                    }
                    val activeWindow = window
                    if (activeWindow == null) {
                        result.error("window_unavailable", "No attached window", null)
                        return@setMethodCallHandler
                    }
                    val requestId = positiveProtectionId(call.argument<Any>("requestId"))
                    val secure: Boolean
                    if (call.method == "beginSession") {
                        // A restarted Dart isolate or retry cannot revive an
                        // older OFF. Every new session first restores ON.
                        check(nextProtectionSession < Long.MAX_VALUE)
                        protectionSession = ++nextProtectionSession
                        lastProtectionRequest = 0L
                        secure = true
                    } else {
                        val session = positiveProtectionId(call.argument<Any>("sessionId"))
                        if (session != protectionSession || requestId <= lastProtectionRequest) {
                            result.error("stale_request", "Superseded protection request", null)
                            return@setMethodCallHandler
                        }
                        secure = call.argument<Boolean>("secure")
                            ?: throw IllegalArgumentException("Missing protection state")
                        lastProtectionRequest = requestId
                    }
                    if (secure) {
                        activeWindow.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        activeWindow.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    val observed = (activeWindow.attributes.flags and
                        WindowManager.LayoutParams.FLAG_SECURE) != 0
                    if (observed != secure) {
                        result.error("state_mismatch", "Window protection not confirmed", null)
                        return@setMethodCallHandler
                    }
                    if (secure) {
                        protectionCover?.let { cover ->
                            (cover.parent as? ViewGroup)?.removeView(cover)
                        }
                        protectionCover = null
                    }
                    result.success(mapOf(
                        "success" to true,
                        "sessionId" to protectionSession,
                        "requestId" to requestId,
                        "secure" to observed,
                    ))
                } catch (_: Exception) {
                    result.error("protection_failed", "Window protection not confirmed", null)
                }
            }
        }
        protectionChannel?.invokeMethod("windowChanged", null)
    }

    private fun coverProtectionWindow() {
        if (protectionCover != null) return
        val root = window?.decorView as? ViewGroup ?: return
        val cover = FrameLayout(this).apply {
            setBackgroundColor(0xFFF4F6FB.toInt())
            isClickable = true
            // If initial ON fails, do not hide the only way to request a retry
            // behind the native curtain. This can only invalidate/re-attest.
            addView(Button(this@MainActivity).apply {
                text = "Retry screen protection"
                setOnClickListener { protectionChannel?.invokeMethod("windowChanged", null) }
            }, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ))
        }
        root.addView(cover, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ))
        protectionCover = cover
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        coverProtectionWindow()
        protectionAttached = false
        protectionSession = 0L
        protectionChannel?.invokeMethod("windowChanged", null)
        protectionChannel?.setMethodCallHandler(null)
        protectionChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
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
