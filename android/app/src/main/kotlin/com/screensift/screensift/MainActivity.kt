package com.screensift.screensift

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), PermissionHost {

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var attachedSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Hackathon trick: Auto-request "Draw over other apps" permission on startup
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, NativeBridge.METHOD_CHANNEL)
            .setMethodCallHandler { call, result -> NativeBridge.handle(this, call, result) }

        EventChannel(messenger, NativeBridge.EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        if (events == null) return
                        attachedSink = events
                        ScreenshotBus.attach(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        ScreenshotBus.detach(attachedSink)
                        attachedSink = null
                    }
                },
            )
    }

    // --- PermissionHost ------------------------------------------------------
    override fun hostActivity(): Activity = this

    override fun hasPermission(kind: String): Boolean = when (kind) {
        NativeBridge.PERMISSION_NOTIFICATIONS -> hasNotificationPermission()
        else -> hasMediaPermission()
    }

    override fun requestPermission(kind: String, result: MethodChannel.Result) {
        val permission = when (kind) {
            NativeBridge.PERMISSION_NOTIFICATIONS -> Manifest.permission.POST_NOTIFICATIONS
            else -> mediaPermission()
        }

        if (permission == null ||
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(permission), REQUEST_PERMISSION)
    }

    override fun requestScreenshotDelete(id: Long, result: MethodChannel.Result) {
        if (id < 0L) {
            result.success(false)
            return
        }
        val image = runCatching {
            MediaStoreScreenshotReader.queryById(contentResolver, id)
        }.getOrNull()
        if (image == null) {
            result.success(false)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val pending = runCatching {
                MediaStore.createDeleteRequest(contentResolver, listOf(image.uri))
            }.getOrNull()
            if (pending != null) {
                pendingDeleteResult?.success(false)
                pendingDeleteResult = result
                val launched = runCatching {
                    startIntentSenderForResult(pending.intentSender, REQUEST_DELETE, null, 0, 0, 0)
                }.isSuccess
                if (launched) return
                pendingDeleteResult = null
            }
        }
        result.success(MediaStoreScreenshotReader.delete(this, image))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSION) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_DELETE) return
        pendingDeleteResult?.success(resultCode == Activity.RESULT_OK)
        pendingDeleteResult = null
    }

    override fun onDestroy() {
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
        pendingDeleteResult?.success(false)
        pendingDeleteResult = null
        ScreenshotBus.detach(attachedSink)
        attachedSink = null
        super.onDestroy()
    }

    private fun mediaPermission(): String? = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> Manifest.permission.READ_MEDIA_IMAGES
        else -> Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasMediaPermission(): Boolean {
        val permission = mediaPermission() ?: return true
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private companion object {
        const val REQUEST_PERMISSION = 7301
        const val REQUEST_DELETE = 7302
    }
}