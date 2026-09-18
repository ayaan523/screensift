package com.screensift.screensift

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream

/**
 * A single row from `MediaStore.Images`.
 *
 * ScreenSift never keeps a handle to the original: [materialize] copies the
 * bytes into the app cache so Dart gets a plain file to hand to Dio, and
 * [delete] removes the original when Auto-Trash is on.
 */
data class MediaStoreImage(
    val id: Long,
    val uri: Uri,
    val displayName: String,
    val relativePath: String,
    val absolutePath: String?,
    val dateAddedMillis: Long,
    val sizeBytes: Long,
) {
    /**
     * OEMs disagree on where screenshots land and what they are called, so we
     * match the folder *and* the filename against the tokens actually shipped
     * by Pixel, Samsung, Xiaomi, OnePlus and Motorola.
     */
    val isScreenshot: Boolean
        get() = SCREENSHOT_TOKENS.any { token ->
            displayName.lowercase().contains(token) ||
                relativePath.lowercase().contains(token) ||
                absolutePath?.lowercase()?.contains(token) == true
        }

    fun toMap(cachedPath: String?): Map<String, Any?> = mapOf(
        "id" to id,
        "uri" to uri.toString(),
        "name" to displayName,
        "relative_path" to relativePath,
        "source_path" to absolutePath,
        "cached_path" to cachedPath,
        "date_added" to dateAddedMillis,
        "size" to sizeBytes,
        "is_screenshot" to isScreenshot,
    )

    companion object {
        private val SCREENSHOT_TOKENS = listOf(
            "screenshot",
            "screencap",
            "screen_shot",
            "screen-shot",
            "screengrab",
        )
    }
}

/** MediaStore queries: read recent images, copy one out, delete an original. */
object MediaStoreScreenshotReader {

    private const val ID = MediaStore.Images.Media._ID
    private const val NAME = MediaStore.Images.Media.DISPLAY_NAME
    private const val DATA = MediaStore.Images.Media.DATA
    private const val ADDED = MediaStore.Images.Media.DATE_ADDED
    private const val SIZE = MediaStore.Images.Media.SIZE
    private const val FOLDER = MediaStore.Images.Media.RELATIVE_PATH

    private val projection = buildList {
        add(ID); add(NAME); add(DATA); add(ADDED); add(SIZE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) add(FOLDER)
    }.toTypedArray()

    private val collection: Uri
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    /**
     * Newest images with an `_ID` greater than [sinceId].
     *
     * Ordering by `_ID` (not `DATE_ADDED`) keeps the observer incremental: a
     * single pass tells us exactly which rows are new since the last capture.
     */
    fun queryNewerThan(
        resolver: ContentResolver,
        sinceId: Long,
        limit: Int = 8,
    ): List<MediaStoreImage> {
        val selection = if (sinceId > 0) "$ID > ?" else null
        val args = if (sinceId > 0) arrayOf(sinceId.toString()) else null
        val results = mutableListOf<MediaStoreImage>()

        resolver.query(
            collection,
            projection,
            selection,
            args,
            "$ID DESC LIMIT $limit",
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(ID)
            val nameIdx = cursor.getColumnIndexOrThrow(NAME)
            val dataIdx = cursor.getColumnIndex(DATA)
            val addedIdx = cursor.getColumnIndexOrThrow(ADDED)
            val sizeIdx = cursor.getColumnIndexOrThrow(SIZE)
            val folderIdx = cursor.getColumnIndex(FOLDER)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIdx)
                results += MediaStoreImage(
                    id = id,
                    uri = ContentUris.withAppendedId(collection, id),
                    displayName = cursor.getString(nameIdx) ?: "screenshot_$id",
                    relativePath =
                        if (folderIdx >= 0) cursor.getString(folderIdx).orEmpty() else "",
                    absolutePath =
                        if (dataIdx >= 0) cursor.getString(dataIdx) else null,
                    dateAddedMillis = cursor.getLong(addedIdx) * 1000L,
                    sizeBytes = cursor.getLong(sizeIdx),
                )
            }
        }
        return results
    }

    /** Largest `_ID` currently visible, used to prime the observer cursor. */
    fun currentMaxId(resolver: ContentResolver): Long =
        resolver.query(collection, arrayOf(ID), null, null, "$ID DESC LIMIT 1")
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else 0L }
            ?: 0L

    /** A single row by `_ID`, or null when the user already deleted it. */
    fun queryById(resolver: ContentResolver, id: Long): MediaStoreImage? {
        resolver.query(
            collection,
            projection,
            "$ID = ?",
            arrayOf(id.toString()),
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val idIdx = cursor.getColumnIndexOrThrow(ID)
            val nameIdx = cursor.getColumnIndexOrThrow(NAME)
            val dataIdx = cursor.getColumnIndex(DATA)
            val addedIdx = cursor.getColumnIndexOrThrow(ADDED)
            val sizeIdx = cursor.getColumnIndexOrThrow(SIZE)
            val folderIdx = cursor.getColumnIndex(FOLDER)
            val rowId = cursor.getLong(idIdx)
            return MediaStoreImage(
                id = rowId,
                uri = ContentUris.withAppendedId(collection, rowId),
                displayName = cursor.getString(nameIdx) ?: "screenshot_$rowId",
                relativePath =
                    if (folderIdx >= 0) cursor.getString(folderIdx).orEmpty() else "",
                absolutePath = if (dataIdx >= 0) cursor.getString(dataIdx) else null,
                dateAddedMillis = cursor.getLong(addedIdx) * 1000L,
                sizeBytes = cursor.getLong(sizeIdx),
            )
        }
        return null
    }

    /**
     * Copies the image behind [image] into the app cache and returns the file.
     *
     * Going through the resolver (rather than reading `DATA` directly) is what
     * makes this work on scoped-storage devices where the real path is not
     * accessible to us at all.
     */
    fun materialize(context: Context, image: MediaStoreImage): File? {
        val dir = File(context.cacheDir, CACHE_DIR).apply { mkdirs() }
        val target = File(dir, "${image.dateAddedMillis}_${image.displayName}")
        if (target.exists() && target.length() > 0L) return target

        return runCatching {
            context.contentResolver.openInputStream(image.uri)?.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            if (target.length() > 0L) target else null
        }.getOrNull()
    }

    /** Removes the original from the gallery. Returns true when a row went away. */
    fun delete(context: Context, image: MediaStoreImage): Boolean = runCatching {
        context.contentResolver.delete(image.uri, null, null) > 0
    }.getOrDefault(false)

    /** Drops cache copies once the pipeline is done with them. */
    fun purgeCache(context: Context) {
        runCatching { File(context.cacheDir, CACHE_DIR).deleteRecursively() }
    }

    private const val CACHE_DIR = "screensift_incoming"
}
