package com.screensift.screensift

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.NotificationCompat

/**
 * Keeps a MediaStore observer alive after the user leaves ScreenSift.
 *
 * This is the piece that makes the capture "invisible": the OS tells us the
 * moment a screenshot row appears, we copy it out of MediaStore, and we push
 * it onto [ScreenshotBus] for Dart to pick up — with no share sheet and no
 * user action.
 */
class ScreenshotWatchService : Service() {

    private var observerThread: HandlerThread? = null
    private var observerHandler: Handler? = null
    private var observer: ContentObserver? = null
    private var lastSeenId: Long = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        lastSeenId = MediaStoreScreenshotReader.currentMaxId(contentResolver)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        promoteToForeground()
        registerObserver()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        observer?.let { contentResolver.unregisterContentObserver(it) }
        observer = null
        observerThread?.quitSafely()
        observerThread = null
        observerHandler = null
        super.onDestroy()
    }

    // --- observer -----------------------------------------------------------

    private fun registerObserver() {
        if (observer != null) return

        val thread = HandlerThread("screensift-observer").also { it.start() }
        observerThread = thread
        val handler = Handler(thread.looper)
        observerHandler = handler

        val contentObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) = scheduleScan()
        }
        // notifyForDescendants: some OEMs notify on the bucket, not the row.
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            contentObserver,
        )
        observer = contentObserver
    }

    /**
     * MediaStore fires `onChange` several times for one capture (thumbnails,
     * bucket, row). Coalescing into a single scan avoids uploading the same
     * screenshot three times.
     */
    private fun scheduleScan() {
        val handler = observerHandler ?: return
        handler.removeCallbacksAndMessages(SCAN_TOKEN)
        handler.postAtTime({ scan() }, SCAN_TOKEN, System.currentTimeMillis() + SCAN_DEBOUNCE_MS)
    }

    private fun scan() {
        val candidates = runCatching {
            MediaStoreScreenshotReader.queryNewerThan(contentResolver, lastSeenId)
        }.getOrDefault(emptyList())

        if (candidates.isEmpty()) return

        val highestId = candidates.maxOf { it.id }
        val fresh = candidates.filter { it.id > lastSeenId }
        lastSeenId = maxOf(lastSeenId, highestId)

        for (image in fresh.sortedBy { it.id }) {
            // Ambiguous rows (no screenshot token anywhere) are surfaced too,
            // flagged so the Dart side can decide whether to act on them.
            val cacheFile = MediaStoreScreenshotReader.materialize(this, image)
            ScreenshotBus.publish(image.toMap(cacheFile?.absolutePath))
        }
    }

    // --- foreground bookkeeping --------------------------------------------

    private fun promoteToForeground() {
        val notification = buildNotification()
        // `dataSync` cannot be started from BOOT_COMPLETED on Android 15 and is
        // capped at a few hours a day, which is exactly the wrong shape for an
        // always-on observer. `specialUse` is the correct, unrestricted type.
        if (Build.VERSION.SDK_INT >= 34) {
            runCatching {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            }.onFailure { stopSelf() }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            }.onFailure { stopSelf() }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ScreenSift is watching")
            .setContentText("Screenshots are analysed automatically.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Screenshot listener",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "Keeps ScreenSift listening for new screenshots."
                setShowBadge(false)
            },
        )
    }

    companion object {
        const val ACTION_START = "com.screensift.action.START_WATCH"
        const val ACTION_STOP = "com.screensift.action.STOP_WATCH"

        private const val CHANNEL_ID = "screensift.watcher"
        private const val NOTIFICATION_ID = 8101
        private const val SCAN_DEBOUNCE_MS = 700L
        private val SCAN_TOKEN = Any()

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, ScreenshotWatchService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenshotWatchService::class.java))
            isRunning = false
        }
    }
}