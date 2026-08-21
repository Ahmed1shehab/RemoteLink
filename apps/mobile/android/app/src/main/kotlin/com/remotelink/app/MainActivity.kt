package com.remotelink.app

import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Hosts the Flutter engine, and tells it when this phone's clipboard changes.
 *
 * The change notification is the whole point, and it is why this is here rather
 * than in Dart. Flutter exposes reading the clipboard and nothing else, so
 * noticing a copy from Dart alone would mean reading on a timer — and since
 * Android 12 every read of another app's clip shows the user a toast naming
 * this app. `OnPrimaryClipChangedListener` reports the change for free and
 * hands over no content at all, so the single read happens once per copy, when
 * there is something new to send.
 *
 * The listener is registered when Dart subscribes and removed when it
 * unsubscribes, which is how the app avoids watching from the background —
 * where Android would refuse the follow-up read anyway, because since Android
 * 10 clipboard access requires focus.
 */
class MainActivity : FlutterActivity() {
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        if (events == null) return
                        val manager = clipboardManager() ?: return

                        stopWatching()
                        // Null payload on purpose: this says "something changed",
                        // not what it changed to. Handing the content over here
                        // would be a read, which is the thing being avoided.
                        val listener = ClipboardManager.OnPrimaryClipChangedListener {
                            events.success(null)
                        }
                        manager.addPrimaryClipChangedListener(listener)
                        clipboardListener = listener
                    }

                    override fun onCancel(arguments: Any?) = stopWatching()
                },
            )
    }

    override fun onDestroy() {
        // The listener holds an event sink that outlives this activity if it is
        // left registered, and the sink holds the engine.
        stopWatching()
        super.onDestroy()
    }

    private fun stopWatching() {
        val listener = clipboardListener ?: return
        clipboardListener = null
        clipboardManager()?.removePrimaryClipChangedListener(listener)
    }

    private fun clipboardManager(): ClipboardManager? =
        getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    private companion object {
        const val CLIPBOARD_CHANNEL = "com.remotelink.app/clipboard_changes"
    }
}
