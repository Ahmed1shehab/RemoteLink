package com.remotelink.app

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine, and gives Dart the two things it cannot reach.
 *
 * **Clipboard change notifications.** Flutter exposes reading the clipboard and
 * nothing else, so noticing a copy from Dart alone would mean reading on a
 * timer — and since Android 12 every read of another app's clip shows the user
 * a toast naming this app. `OnPrimaryClipChangedListener` reports the change for
 * free and hands over no content, so the single read happens once per copy, when
 * there is something new to send. The listener is registered when Dart
 * subscribes and removed when it unsubscribes, which is how the app avoids
 * watching from the background — where Android would refuse the follow-up read
 * anyway, because since Android 10 clipboard access requires focus.
 *
 * **The foreground service.** [LinkService] keeps the process unfrozen and
 * networked while the app is off screen. Dart drives it from the connection
 * state, because the connection is the only thing that justifies it running.
 *
 * **Shares.** The manifest has advertised this app as a share target since it
 * was written, and nothing read the intent. [ShareIntake] does, and it is the
 * one route past the clipboard restriction above: no focus rule applies to
 * content another app hands over deliberately.
 */
class MainActivity : FlutterActivity() {
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var linkChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null

    /**
     * A share that arrived before Dart was listening.
     *
     * A cold start delivers the intent long before the isolate exists, so the
     * payload waits here and Dart collects it with `takePending` once it is up.
     * A warm start has somewhere to push it and does.
     */
    private var pendingShare: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        if (events == null) return
                        val manager = clipboardManager() ?: return

                        stopWatchingClipboard()
                        // Null payload on purpose: this says "something changed",
                        // not what it changed to. Handing the content over here
                        // would be a read, which is the thing being avoided.
                        val listener = ClipboardManager.OnPrimaryClipChangedListener {
                            events.success(null)
                        }
                        manager.addPrimaryClipChangedListener(listener)
                        clipboardListener = listener
                    }

                    override fun onCancel(arguments: Any?) = stopWatchingClipboard()
                },
            )

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINK_CHANNEL)
        linkChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    requestNotificationPermission()
                    LinkService.start(
                        this,
                        title = call.argument<String>("title").orEmpty(),
                        body = call.argument<String>("body").orEmpty(),
                        disconnectLabel = call.argument<String>("disconnectLabel").orEmpty(),
                    )
                    result.success(null)
                }
                "stop" -> {
                    LinkService.stop(this)
                    result.success(null)
                }
                "openBatterySettings" -> result.success(openBatterySettings())
                "backgroundClipboardEnabled" ->
                    result.success(ClipboardAccessibilityService.isRunning)
                "openAccessibilitySettings" ->
                    result.success(openAccessibilitySettings())
                else -> result.notImplemented()
            }
        }

        // The accessibility service reads the clipboard; sending it is this
        // isolate's job, and it is the only thing here that knows where to
        // send it.
        ClipboardAccessibilityService.onCopied = { text ->
            runOnUiThread { channel.invokeMethod("clipboardCopied", text) }
        }
        ClipboardAccessibilityService.onRefused = {
            runOnUiThread { channel.invokeMethod("clipboardRefused", null) }
        }

        // Only the Dart isolate can honour a disconnect, so the notification
        // asks it rather than tearing anything down itself.
        LinkService.onDisconnectRequested = {
            runOnUiThread { linkChannel?.invokeMethod("disconnectRequested", null) }
        }

        val shares = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel = shares
        shares.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }

        // The intent that launched this activity, which for a share is the
        // whole point of the launch.
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // `singleTop`, so a share into an app that is already open arrives here
        // rather than through a second `onCreate`.
        setIntent(intent)
        handleShare(intent)
    }

    /**
     * Reads a share and hands it to Dart, or holds it until Dart asks.
     *
     * Staging happens off the main thread, so this returns immediately and the
     * payload lands later — which is also why a share can arrive before the
     * isolate is listening even on a warm start.
     */
    private fun handleShare(intent: Intent?) {
        if (!ShareIntake.isShare(intent) || intent == null) {
            // Only tidy up on a launch that is not itself a share: the two run
            // concurrently, and clearing during a staging deletes the file the
            // user is in the middle of sending.
            ShareIntake.clearStaging(this)
            return
        }

        ShareIntake.read(this, intent) { payload ->
            val map = payload?.toMap() ?: return@read
            val channel = shareChannel
            if (channel == null) {
                pendingShare = map
                return@read
            }
            channel.invokeMethod("shared", map, object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                // Dart is not listening yet — the engine is up but the app has
                // not reached the point of subscribing. Held rather than
                // dropped, for `takePending` to collect.
                override fun error(code: String, message: String?, details: Any?) {
                    pendingShare = map
                }

                override fun notImplemented() {
                    pendingShare = map
                }
            })
        }
    }

    override fun onDestroy() {
        // Both of these outlive this activity if left set: the clipboard
        // listener holds an event sink, and the callback holds a channel, and
        // each of those holds the engine this activity is about to destroy.
        stopWatchingClipboard()
        LinkService.onDisconnectRequested = null
        ClipboardAccessibilityService.onCopied = null
        ClipboardAccessibilityService.onRefused = null
        linkChannel = null
        shareChannel = null
        // The engine goes with the activity, so nothing is left that could
        // honour the notification the service is showing. `stopWithTask` covers
        // the swipe-away; this covers every other way the activity ends.
        LinkService.stop(this)
        super.onDestroy()
    }

    /**
     * Asks for notification permission, which Android 13 introduced and which
     * the service does not depend on.
     *
     * A denied permission hides the notification and changes nothing else — the
     * service still runs, and the link still survives. So this asks once, at
     * the moment a connection makes it meaningful, and never blocks on the
     * answer.
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    /**
     * Opens the battery-optimisation list, which is as far as this can go.
     *
     * Asking for the exemption directly needs `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
     * a permission the Play Store restricts to apps whose core function is
     * unarguably broken without it. The manufacturer screens that actually
     * matter — Xiaomi's Autostart, Huawei's protected apps — have no public
     * intent at all, so the app names them and lets the user find them.
     */
    private fun openBatterySettings(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        // Not every device ships the screen, and a settings activity that does
        // not exist should leave the user where they were rather than crash the
        // app they were using.
        false
    }

    /**
     * Opens the system's Accessibility screen.
     *
     * As far as this can go: enabling a service is the user's decision to make
     * on a screen the app cannot reach into, which is the point of it being
     * there rather than behind a permission dialog.
     */
    private fun openAccessibilitySettings(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        false
    }

    private fun stopWatchingClipboard() {
        val listener = clipboardListener ?: return
        clipboardListener = null
        clipboardManager()?.removePrimaryClipChangedListener(listener)
    }

    private fun clipboardManager(): ClipboardManager? =
        getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    private companion object {
        const val CLIPBOARD_CHANNEL = "com.remotelink.app/clipboard_changes"
        const val LINK_CHANNEL = "com.remotelink.app/link_service"
        const val SHARE_CHANNEL = "com.remotelink.app/share"
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
    }
}
