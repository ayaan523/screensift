package com.screensift.screensift

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the observer after a reboot or an app update.
 *
 * `BOOT_COMPLETED` is one of the few exemptions that still allows starting a
 * foreground service from the background on Android 12+, so this is the
 * supported way to keep the listener alive without the user opening the app.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        if (!NativePrefs.isWatchEnabled(context)) return
        runCatching { ScreenshotWatchService.start(context) }
    }
}
