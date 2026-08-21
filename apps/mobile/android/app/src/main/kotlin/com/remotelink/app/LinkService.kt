package com.remotelink.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps the process alive and networked while Remote Link is off screen.
 *
 * Android freezes a backgrounded app and takes its sockets with it. On the
 * phone this was reported from, the session died within seconds of the app
 * leaving the screen and every reconnect attempt then failed with ETIMEDOUT —
 * the app had no network at all until it was opened again. A file transfer
 * started in the app therefore could not survive the user switching to
 * anything else, which on a phone is most of the time.
 *
 * A foreground service is the only sanctioned way out of that. It is
 * deliberately hollow: it hosts nothing, owns no connection, and knows nothing
 * about the protocol. `RemoteLinkClient` stays where it is, in the Dart isolate
 * of the activity's engine, and keeps running because the process keeps
 * running. A second, headless engine would mean a second client, a second trust
 * store reader, and two sessions racing for one port.
 *
 * ## What this does not do
 *
 * It does not make the phone's clipboard readable from the background. Android
 * has required window focus for clipboard access since Android 10 and no
 * service type lifts that, so phone-to-computer clipboard stays foreground-only
 * whatever runs here.
 *
 * It does not survive an OEM battery manager that has not been told to leave
 * the app alone. Xiaomi, Huawei, Oppo and Samsung all kill foreground services
 * the user has not exempted, which is why the app ships the guidance rather
 * than assuming the service is enough.
 */
class LinkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                // The notification's own way out. Dart owns the connection, so
                // this asks rather than acts, and the service goes down when
                // Dart comes back and says the link is gone.
                onDisconnectRequested?.invoke()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // Every user-visible string is passed in from Dart. Composing them
        // here would split the app's copy across two languages and leave the
        // Kotlin half out of reach of any later localisation.
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val body = intent?.getStringExtra(EXTRA_BODY).orEmpty()
        val disconnectLabel =
            intent?.getStringExtra(EXTRA_DISCONNECT_LABEL) ?: DEFAULT_DISCONNECT

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(title, body, disconnectLabel),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            } else {
                0
            },
        )

        // Not sticky, and that is the whole point. A restarted service comes
        // back without the activity that hosts the Dart isolate, so there
        // would be no client, no session, and a notification saying
        // "Connected" over nothing at all. A stale claim of connectivity is
        // worse than no notification.
        return START_NOT_STICKY
    }

    private fun buildNotification(
        title: String,
        body: String,
        disconnectLabel: String,
    ): Notification {
        createChannel()

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val disconnect = PendingIntent.getService(
            this,
            1,
            Intent(this, LinkService::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(open)
            .addAction(0, disconnectLabel, disconnect)
            .setOngoing(true)
            // Low, not default: this is a status line, not news. It should sit
            // in the shade without a sound, a peek, or a place at the top.
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setShowWhen(false)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Connection",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while Remote Link is connected to a computer."
                setShowBadge(false)
            },
        )
    }

    companion object {
        private const val CHANNEL_ID = "com.remotelink.app.link"
        private const val NOTIFICATION_ID = 1

        const val ACTION_DISCONNECT = "com.remotelink.app.DISCONNECT"
        const val ACTION_STOP = "com.remotelink.app.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_DISCONNECT_LABEL = "disconnectLabel"

        // Only ever seen if the service is somehow started without its extras,
        // which nothing in this app does.
        private const val DEFAULT_TITLE = "Remote Link"
        private const val DEFAULT_DISCONNECT = "Disconnect"

        /**
         * Invoked when the user presses Disconnect on the notification.
         *
         * Set by [MainActivity] while its engine is alive and cleared when it
         * is not, because the only thing that can honour a disconnect is the
         * Dart isolate that owns the connection.
         */
        var onDisconnectRequested: (() -> Unit)? = null

        fun start(
            context: Context,
            title: String,
            body: String,
            disconnectLabel: String,
        ) {
            val intent = Intent(context, LinkService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
                .putExtra(EXTRA_DISCONNECT_LABEL, disconnectLabel)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }
}
