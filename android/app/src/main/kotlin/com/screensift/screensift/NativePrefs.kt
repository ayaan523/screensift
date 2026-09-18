package com.screensift.screensift

import android.content.Context

/**
 * Native-side flags that must survive process death.
 *
 * The Dart-side settings store is only readable once the Flutter engine is up,
 * but [BootCompletedReceiver] has to decide whether to restart the observer
 * before that happens — so this tiny store exists.
 */
object NativePrefs {

    private const val FILE = "screensift_native"
    private const val KEY_WATCH_ENABLED = "watch_enabled"

    fun setWatchEnabled(context: Context, enabled: Boolean) {
        context.applicationContext
            .getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_WATCH_ENABLED, enabled)
            .apply()
    }

    fun isWatchEnabled(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_WATCH_ENABLED, false)
}
