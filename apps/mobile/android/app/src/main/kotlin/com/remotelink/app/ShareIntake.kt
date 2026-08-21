package com.remotelink.app

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import java.io.File
import java.util.concurrent.Executors

/**
 * Turns an Android share into something Dart can send.
 *
 * The app has advertised itself as a share target since the manifest was
 * written, and nothing read the intent: sharing to Remote Link opened the app
 * and dropped what was shared. This is the missing half.
 *
 * It matters more than a convenience. Android refuses clipboard reads to an app
 * that does not have focus, so "copy in another app, have it appear on the
 * computer" cannot work from the background however the app is built. Sharing
 * is the route the platform *does* offer: the user picks Remote Link, the
 * system hands the content over, and no focus rule applies to a gift.
 *
 * Files arrive as `content://` URIs, which `dart:io` cannot open — a URI is a
 * handle into another app's provider, not a path. Each one is copied into this
 * app's cache here, and Dart is handed a real file it can read.
 */
object ShareIntake {
    /** Text, or files already staged on disk. */
    sealed interface Payload {
        fun toMap(): Map<String, Any?>
    }

    data class SharedText(val text: String) : Payload {
        override fun toMap(): Map<String, Any?> =
            mapOf("type" to "text", "text" to text)
    }

    data class SharedFiles(val files: List<StagedFile>) : Payload {
        override fun toMap(): Map<String, Any?> = mapOf(
            "type" to "files",
            "files" to files.map { mapOf("path" to it.path, "name" to it.name) },
        )
    }

    data class StagedFile(val path: String, val name: String)

    private val executor = Executors.newSingleThreadExecutor()

    /** Whether [intent] is a share this app should act on. */
    fun isShare(intent: Intent?): Boolean = when (intent?.action) {
        Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> true
        else -> false
    }

    /**
     * Reads [intent] and calls [onReady] on the main thread.
     *
     * Off the main thread because the copy is the expensive part: a shared
     * video is hundreds of megabytes, and staging it inline would freeze the
     * app it was shared into for as long as the copy took.
     */
    fun read(
        context: Context,
        intent: Intent,
        onReady: (Payload?) -> Unit,
    ) {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val uris = streams(intent)

        // Text first when both are present. A share carrying an EXTRA_TEXT
        // alongside a stream is usually a link with a preview image attached,
        // and the link is the part the user meant to send.
        if (!text.isNullOrBlank()) {
            onReady(SharedText(text))
            return
        }
        if (uris.isEmpty()) {
            onReady(null)
            return
        }

        executor.execute {
            val staged = uris.mapNotNull { stage(context, it) }
            val payload = if (staged.isEmpty()) null else SharedFiles(staged)
            // `Handler`, not `Context.mainExecutor`, which is API 28.
            Handler(Looper.getMainLooper()).post { onReady(payload) }
        }
    }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            listOfNotNull(uri)
        }
        Intent.ACTION_SEND_MULTIPLE -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }.orEmpty()
        }
        else -> emptyList()
    }

    /**
     * Copies one shared URI into the cache and returns where it landed.
     *
     * Returns null rather than throwing on anything unreadable: a share of five
     * files where one has been deleted underneath the picker should send the
     * other four, not fail entirely.
     */
    private fun stage(context: Context, uri: Uri): StagedFile? {
        return try {
            val name = displayName(context.contentResolver, uri)
            val directory =
                File(context.cacheDir, SHARE_DIRECTORY).apply { mkdirs() }
            val destination = collisionFreeFile(directory, name)

            val copied = context.contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use(input::copyTo)
                true
            } ?: false

            if (copied) StagedFile(destination.absolutePath, name) else null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * The name the sending app gave this content.
     *
     * Providers are not obliged to answer, and a URI's last path segment is
     * frequently a row id rather than a name, so there is a fallback — an
     * unnamed file is better sent as `shared-file` than as `1043`.
     */
    private fun displayName(resolver: ContentResolver, uri: Uri): String {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) {
                    val name = cursor.getString(column)
                    if (!name.isNullOrBlank()) return sanitise(name)
                }
            }
        val segment = uri.lastPathSegment
        return if (segment.isNullOrBlank() || segment.toLongOrNull() != null) {
            "shared-file"
        } else {
            sanitise(segment)
        }
    }

    /**
     * Strips anything that could make this name a path.
     *
     * The name comes from another application, so it is untrusted input that
     * this app is about to use to create a file and then put on the wire.
     */
    private fun sanitise(name: String): String {
        val flattened = name.replace('/', '_').replace('\\', '_').trim()
        return when {
            flattened.isEmpty() || flattened == "." || flattened == ".." ->
                "shared-file"
            else -> flattened.take(MAX_NAME_LENGTH)
        }
    }

    private fun collisionFreeFile(directory: File, name: String): File {
        val candidate = File(directory, name)
        if (!candidate.exists()) return candidate

        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var suffix = 2
        while (true) {
            val next = File(directory, "$stem ($suffix)$extension")
            if (!next.exists()) return next
            suffix++
        }
    }

    /**
     * Empties the staging directory.
     *
     * These are copies of files the user already has, kept only long enough to
     * put them on the wire, so they are cleared on launch rather than
     * accumulating in a directory nobody can see.
     *
     * Called only on a launch that is *not* itself a share — otherwise this
     * races the staging it was meant to tidy up after, and deletes the file the
     * user is in the middle of sending.
     */
    fun clearStaging(context: Context) {
        executor.execute {
            File(context.cacheDir, SHARE_DIRECTORY).listFiles()?.forEach(File::delete)
        }
    }

    private const val SHARE_DIRECTORY = "shared"
    private const val MAX_NAME_LENGTH = 120
}
