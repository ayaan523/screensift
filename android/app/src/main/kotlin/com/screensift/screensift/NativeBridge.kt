package com.screensift.screensift

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Capabilities the bridge needs from the hosting Activity.
 *
 * Permission dialogs and the system settings page are Activity-scoped, so the
 * bridge stays testable by depending on this seam instead of on an Activity
 * concrete class.
 */
interface PermissionHost {
    fun hostActivity(): Activity
    fun hasPermission(kind: String): Boolean
    fun requestPermission(kind: String, result: MethodChannel.Result)

    /**
     * Deletes a capture, confirming with the user first when the OS requires
     * it. Android 10+ will not let an app delete media it does not own without
     * an explicit `MediaStore.createDeleteRequest` approval.
     */
    fun requestScreenshotDelete(id: Long, result: MethodChannel.Result)
}

/**
 * The single MethodChannel the Dart layer talks to.
 *
 * Everything that touches MediaStore, the foreground service or the OS
 * permission model is funnelled through here so the Dart side only ever sees
 * plain maps and booleans.
 */
object NativeBridge {

    const val METHOD_CHANNEL = "com.screensift/native"
    const val EVENT_CHANNEL = "com.screensift/screenshots"

    const val PERMISSION_MEDIA = "media"
    const val PERMISSION_NOTIFICATIONS = "notifications"

    private const val DEFAULT_RECENT_LIMIT = 20

    fun handle(host: PermissionHost, call: MethodCall, result: MethodChannel.Result) {
        val context: Context = host.hostActivity().applicationContext
        when (call.method) {
            "hasPermission" ->
                result.success(host.hasPermission(call.stringArg("kind", PERMISSION_MEDIA)))

            "requestPermission" ->
                host.requestPermission(call.stringArg("kind", PERMISSION_MEDIA), result)

            "startWatching" -> {
                NativePrefs.setWatchEnabled(context, true)
                // From Android 12 the OS throws
                // ForegroundServiceStartNotAllowedException when a background
                // app tries to promote a service. It is recoverable: the flag is
                // persisted and BootCompletedReceiver retries on next launch, so
                // report failure instead of taking the app down.
                val started = runCatching {
                    ScreenshotWatchService.start(context)
                }.isSuccess
                result.success(started)
            }

            "stopWatching" -> {
                NativePrefs.setWatchEnabled(context, false)
                ScreenshotWatchService.stop(context)
                result.success(true)
            }

            "isWatching" -> result.success(ScreenshotWatchService.isRunning)

            "drainBufferedCaptures" -> result.success(ScreenshotBus.drain())

            "peekBufferedCaptures" -> result.success(ScreenshotBus.buffered())

            "clearCaptureBuffer" -> {
                ScreenshotBus.clearBuffer()
                result.success(true)
            }

            "recentScreenshots" -> {
                val limit = call.argument<Number>("limit")?.toInt() ?: DEFAULT_RECENT_LIMIT
                result.success(recentScreenshots(context, limit))
            }

            "materializeCapture" -> {
                val id = call.argument<Number>("id")?.toLong() ?: -1L
                result.success(materializeCapture(context, id))
            }

            "deleteCapture" -> {
                val id = call.argument<Number>("id")?.toLong() ?: -1L
                result.success(deleteCapture(context, id))
            }

            // Auto-Trash path: goes through the host so the OS confirmation
            // dialog can be shown when MediaStore demands one.
            "requestDeleteCapture" -> {
                val id = call.argument<Number>("id")?.toLong() ?: -1L
                host.requestScreenshotDelete(id, result)
            }

            "purgeCache" -> {
                MediaStoreScreenshotReader.purgeCache(context)
                result.success(true)
            }

            "openAppSettings" -> {
                openAppSettings(host.hostActivity())
                result.success(true)
            }

            "platformInfo" -> result.success(platformInfo(context))

            else -> result.notImplemented()
        }
    }

    // --- handlers -----------------------------------------------------------

    private fun recentScreenshots(context: Context, limit: Int): List<Map<String, Any?>> {
        val rows = runCatching {
            MediaStoreScreenshotReader.queryNewerThan(
                context.contentResolver,
                sinceId = 0L,
                limit = limit * 3,
            )
        }.getOrDefault(emptyList())

        // Over-fetch, then narrow to genuine screenshots so the list the user
        // sees is only captures ScreenSift would actually process.
        return rows.filter { it.isScreenshot }
            .take(limit)
            .map { it.toMap(cachedPath = null) }
    }

    private fun materializeCapture(context: Context, id: Long): String? {
        if (id < 0L) return null
        val image = runCatching {
            MediaStoreScreenshotReader.queryById(context.contentResolver, id)
        }.getOrNull() ?: return null
        return MediaStoreScreenshotReader.materialize(context, image)?.absolutePath
    }

    private fun deleteCapture(context: Context, id: Long): Boolean {
        if (id < 0L) return false
        val image = runCatching {
            MediaStoreScreenshotReader.queryById(context.contentResolver, id)
        }.getOrNull() ?: return false
        return MediaStoreScreenshotReader.delete(context, image)
    }

    private fun openAppSettings(activity: Activity) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { activity.startActivity(intent) }
    }

    private fun platformInfo(context: Context): Map<String, Any?> = mapOf(
        "sdk" to Build.VERSION.SDK_INT,
        "android" to Build.VERSION.RELEASE,
        "device" to "${Build.MANUFACTURER}${Build.MODEL}".trim(),
        "package" to context.packageName,
        "watcherRunning" to ScreenshotWatchService.isRunning,
        "watchEnabled" to NativePrefs.isWatchEnabled(context),
    )

    private fun MethodCall.stringArg(key: String, fallback: String): String =
        argument<String>(key) ?: fallback
}