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
    private const val SEEN_LIMIT = 400

    private val sinks = CopyOnWriteArrayList<EventChannel.EventSink>()
    private val replay = ArrayDeque<Map<String, Any?>>()

    /**
     * MediaStore fires the observer several times per capture and OEMs re-issue
     * rows on retry, so the same `_ID` can arrive repeatedly. Remembering what
     * we already broadcast is what keeps one screenshot from becoming five
     * uploads. Bounded so a long-running service cannot leak.
     */
    private val seenIds = LinkedHashSet<Long>()
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
        val id = (event["id"] as? Number)?.toLong() ?: return
        synchronized(this) {
            if (!seenIds.add(id)) return
            while (seenIds.size > SEEN_LIMIT) {
                val oldest = seenIds.iterator()
                if (!oldest.hasNext()) break
                oldest.next()
                oldest.remove()
            }
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

    /**
     * Hands over the replay buffer and forgets it.
     *
     * Without this the buffer survived process death and every cold start
     * re-announced up to 40 old screenshots as if they had just been taken.
     */
    @Synchronized
    fun drain(limit: Int = REPLAY_LIMIT): List<Map<String, Any?>> {
        val drained = replay.toList().takeLast(limit)
        replay.clear()
        return drained
    }

    @Synchronized
    fun clearBuffer() {
        replay.clear()
        seenIds.clear()
    }

    @Synchronized
    fun hasSink(): Boolean = sinks.isNotEmpty()
}