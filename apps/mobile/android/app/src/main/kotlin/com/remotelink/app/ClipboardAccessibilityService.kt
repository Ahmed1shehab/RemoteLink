package com.remotelink.app

import android.accessibilityservice.AccessibilityService
import android.content.ClipboardManager
import android.content.Context
import android.view.accessibility.AccessibilityEvent

/**
 * Reads the clipboard when Remote Link is not the app on screen.
 *
 * This exists for one requirement that nothing else in the app can meet: copy
 * something in a browser, paste it on the computer, without touching Remote
 * Link at all.
 *
 * ## Why it takes an accessibility service
 *
 * Since Android 10, `getPrimaryClip` returns null unless the calling app has
 * window focus or is the device's default keyboard. Remote Link is neither
 * while the user is in Chrome, and no permission, foreground service or
 * service type changes that — the foreground service added for the connection
 * keeps the process alive and networked, and the clipboard rule is enforced
 * separately.
 *
 * An accessibility service is the remaining route, and it is the one clipboard
 * managers on this platform use. It is a heavy thing to ask for: the user has
 * to enable it themselves on a settings screen that warns the app can observe
 * what they do. So it is off unless they turn it on, the app works without it,
 * and it reads exactly one thing — the clipboard, on the event that says the
 * clipboard changed. It inspects no windows, which is why
 * `canRetrieveWindowContent` is false in its configuration: a service that
 * cannot read the screen cannot quietly grow into something that does.
 *
 * ## What is still unknown
 *
 * Whether the read actually succeeds from here varies by manufacturer, and
 * HyperOS is stricter than stock Android. [onPrimaryClipChanged] reports what
 * happened either way, so the log says plainly whether this device allows it
 * rather than leaving a silent no-op.
 */
class ClipboardAccessibilityService : AccessibilityService() {
    private var listener: ClipboardManager.OnPrimaryClipChangedListener? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        val manager = clipboardManager() ?: return

        val registered = ClipboardManager.OnPrimaryClipChangedListener {
            onPrimaryClipChanged()
        }
        manager.addPrimaryClipChangedListener(registered)
        listener = registered
        isRunning = true
    }

    /**
     * Reads the new clipboard content and hands it to the app.
     *
     * A null clip is the platform refusing the read rather than an empty
     * clipboard, and the two are worth distinguishing in the log: the first
     * says this device does not allow what this service exists for.
     */
    private fun onPrimaryClipChanged() {
        val manager = clipboardManager() ?: return
        val clip = manager.primaryClip
        if (clip == null || clip.itemCount == 0) {
            onRefused?.invoke()
            return
        }

        val text = clip.getItemAt(0).coerceToText(this)?.toString()
        if (text.isNullOrEmpty()) {
            onRefused?.invoke()
            return
        }
        onCopied?.invoke(text)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Nothing. The clipboard listener above is the whole of this service;
        // the events exist only because a service must declare some to be
        // bindable at all.
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        listener?.let { clipboardManager()?.removePrimaryClipChangedListener(it) }
        listener = null
        isRunning = false
        super.onDestroy()
    }

    private fun clipboardManager(): ClipboardManager? =
        getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    companion object {
        /** Whether the user has this service enabled and bound right now. */
        @Volatile
        var isRunning: Boolean = false
            private set

        /**
         * Called with clipboard text copied while Remote Link was not on
         * screen. Set by [MainActivity] while its engine is alive.
         */
        var onCopied: ((String) -> Unit)? = null

        /**
         * Called when the platform refused the read.
         *
         * Reported rather than swallowed: on a device that refuses, this
         * feature does not work at all, and the user is entitled to be told
         * that rather than left wondering why nothing arrives.
         */
        var onRefused: (() -> Unit)? = null
    }
}
