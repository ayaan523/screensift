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
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.ImageView
import androidx.core.app.NotificationCompat

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

    private fun registerObserver() {
        if (observer != null) return

        val thread = HandlerThread("screensift-observer").also { it.start() }
        observerThread = thread
        val handler = Handler(thread.looper)
        observerHandler = handler

        val contentObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) = scheduleScan()
        }
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            contentObserver,
        )
        observer = contentObserver
    }

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

        // STRICT FILTER RESTORED: Only process actual screenshots, ignore random OS images
        val screenshots = fresh.filter { it.isScreenshot }

        for (image in screenshots.sortedBy { it.id }) {
            val cacheFile = MediaStoreScreenshotReader.materialize(this, image)
            ScreenshotBus.publish(image.toMap(cacheFile?.absolutePath))
            
            // Try to draw the overlay button safely
            Handler(Looper.getMainLooper()).post {
                runCatching { showFloatingButton() }
            }
        }
    }

    // --- Overlay Button Logic ---
    private fun showFloatingButton() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            return
        }

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            160, 160,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER_VERTICAL or Gravity.END
            x = 20
            y = 0
        }

        val button = ImageView(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF4500")) // Red Button
            }
            setImageResource(android.R.drawable.ic_menu_search)
            setColorFilter(Color.WHITE)
            setPadding(35, 35, 35, 35)
            elevation = 16f

            setOnClickListener {
                runCatching { windowManager.removeView(this) }
                val intent = Intent(this@ScreenshotWatchService, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(intent)
            }
        }

        windowManager.addView(button, params)
        
        // Auto-remove after 5 seconds
        Handler(Looper.getMainLooper()).postDelayed({
            runCatching { windowManager.removeView(button) }
        }, 5000)
    }

    private fun promoteToForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            runCatching {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            }.onFailure { stopSelf() }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            }.onFailure { stopSelf() }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
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
            NotificationChannel(CHANNEL_ID, "Screenshot listener", NotificationManager.IMPORTANCE_MIN).apply {
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
            val intent = Intent(context, ScreenshotWatchService::class.java).setAction(ACTION_START)
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