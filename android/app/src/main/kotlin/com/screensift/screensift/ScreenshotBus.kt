package com.screensift.screensift

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Fan-out point between the native observer and the Dart isolate.
 *
 * The foreground service and the Flutter engine have independent lifecycles:
 * a screenshot can land while the engine is detached (app swiped away, or
 * engine still warming up). A bounded replay buffer means the Dart side can
 * recover anything it missed instead of silently dropping the capture.
 */
object ScreenshotBus {

    private const val REPLAY_LIMIT = 40

    private val sinks = CopyOnWriteArrayList<EventChannel.EventSink>()
    private val replay = ArrayDeque<Map<String, Any?>>()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Synchronized
    fun attach(sink: EventChannel.EventSink) {
        sinks.addIfAbsent(sink)
    }

    @Synchronized
    fun detach(sink: EventChannel.EventSink?) {
        sinks.remove(sink)
    }

    /** Broadcasts a capture to every live sink and records it for replay. */
    fun publish(event: Map<String, Any?>) {
        synchronized(this) {
            replay.addLast(event)
            while (replay.size > REPLAY_LIMIT) replay.removeFirst()
        }
        for (sink in sinks) {
            mainHandler.post {
                runCatching { sink.success(event) }
            }
        }
    }

    /** Captures seen by the service but not yet consumed by Dart. */
    @Synchronized
    fun buffered(limit: Int = REPLAY_LIMIT): List<Map<String, Any?>> =
        replay.toList().takeLast(limit)

    @Synchronized
    fun clearBuffer() = replay.clear()

    @Synchronized
    fun hasSink(): Boolean = sinks.isNotEmpty()
}
