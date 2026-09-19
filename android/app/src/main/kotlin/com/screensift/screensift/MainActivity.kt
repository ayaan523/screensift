package com.screensift.screensift

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine and is the only place that owns an Activity, so it
 * is also the [PermissionHost] the bridge talks to.
 *
 * Before this existed the two channels were never registered at all, which made
 * every native call fail with `MissingPluginException` and left the whole
 * Kotlin screenshot watcher unreachable from Dart.
 */
class MainActivity : FlutterActivity(), PermissionHost {

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var attachedSink: EventChannel.EventSink? = null

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

        // Android < 13 has no notification permission, and pre-Q grants media at
        // install time — report success instead of opening a phantom dialog.
        if (permission == null ||
            ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        // One OS dialog can be in flight at a time; resolve the stale request.
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

        // Android 10+ refuses to delete media the app does not own, so hand the
        // OS a signed delete request and let the user confirm it.
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

        // Owned media (or API < 30) can be deleted straight away.
        result.success(MediaStoreScreenshotReader.delete(this, image))
    }

    // --- Activity callbacks --------------------------------------------------

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSION) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
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
        // Never leave Dart awaiting a reply that can no longer arrive.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
        pendingDeleteResult?.success(false)
        pendingDeleteResult = null
        ScreenshotBus.detach(attachedSink)
        attachedSink = null
        super.onDestroy()
    }

    // --- helpers -------------------------------------------------------------

    private fun mediaPermission(): String? = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            Manifest.permission.READ_MEDIA_IMAGES

        else -> Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasMediaPermission(): Boolean {
        val permission = mediaPermission() ?: return true
        return ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private companion object {
        const val REQUEST_PERMISSION = 7301
        const val REQUEST_DELETE = 7302
    }
}