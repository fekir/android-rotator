package info.fekir.rotator

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.database.ContentObserver
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.widget.RemoteViews
import android.widget.Toast
import info.fekir.rotator.R;
import android.content.pm.ServiceInfo

class RotationService : Service() {

    companion object {
        private const val CHANNEL_ID = "rotation_control"
        private const val NOTIFICATION_ID = 1

        const val ACTION_ROTATE = "info.fekir.rotator.action.ROTATE"
        const val ACTION_AUTO = "info.fekir.rotator.action.AUTO"
        const val ACTION_STOP = "info.fekir.rotator.action.STOP"
        const val EXTRA_ROTATION = "rotation"

        private val ROTATION_BUTTON_IDS =
            intArrayOf(R.id.btn_portrait, R.id.btn_landscape, R.id.btn_portrait_r, R.id.btn_landscape_r)
        private const val SELECTED_COLOR = 0xFF2196F3.toInt()
        private const val DEFAULT_COLOR = Color.BLACK
    }

    // Non-null when a specific rotation is locked, so it can be re-applied
    // Some devices reverts the orientation when accessing launcher/changing apps (observed on Samsung device).
    private var lockedRotation: Int? = null
    private var settingsObserver: ContentObserver? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        registerSettingsObserver()
        applyPersistedRotation()
    }

    private fun applyPersistedRotation() {
        val rotation = RotationPrefs.loadRotation(this)
        lockedRotation = rotation
        if (!Settings.System.canWrite(this)) return

        if (rotation != null) {
            applyLockedRotation(rotation)
        } else {
            Settings.System.putInt(contentResolver, Settings.System.ACCELEROMETER_ROTATION, 1)
        }
    }

    override fun onDestroy() {
        settingsObserver?.let { contentResolver.unregisterContentObserver(it) }
        settingsObserver = null
        super.onDestroy()
    }

    private fun registerSettingsObserver() {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                reapplyLockedRotationIfNeeded()
            }
        }
        contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.ACCELEROMETER_ROTATION),
            false,
            observer
        )
        contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.USER_ROTATION),
            false,
            observer
        )
        settingsObserver = observer
    }

    private fun reapplyLockedRotationIfNeeded() {
        val rotation = lockedRotation ?: return
        if (!Settings.System.canWrite(this)) return

        val currentAccel =
            Settings.System.getInt(contentResolver, Settings.System.ACCELEROMETER_ROTATION, 1)
        val currentUserRotation =
            Settings.System.getInt(contentResolver, Settings.System.USER_ROTATION, 0)

        if (currentAccel != 0 || currentUserRotation != rotation) {
            applyLockedRotation(rotation)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_ROTATE -> setRotation(intent.getIntExtra(EXTRA_ROTATION, 0))
            ACTION_AUTO -> setAutoRotation()
            ACTION_STOP -> {
                // stopForeground(int) requires API 24; use the boolean overload below that.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // android:foregroundServiceType="specialUse" and ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            // are required on Android 14+
            // See https://developer.android.com/about/versions/14/behavior-changes-14#fgs-types
            startForeground(NOTIFICATION_ID,buildNotification(),ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID,buildNotification())
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Rotation control",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val views = RemoteViews(packageName, R.layout.notification_rotation)
        views.setOnClickPendingIntent(R.id.btn_portrait, rotatePendingIntent(0))
        views.setOnClickPendingIntent(R.id.btn_landscape, rotatePendingIntent(1))
        views.setOnClickPendingIntent(R.id.btn_portrait_r, rotatePendingIntent(2))
        views.setOnClickPendingIntent(R.id.btn_landscape_r, rotatePendingIntent(3))
        views.setOnClickPendingIntent(R.id.btn_auto, autoPendingIntent())
        views.setOnClickPendingIntent(R.id.btn_stop, stopPendingIntent())
        highlightSelected(views)

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

        builder.setSmallIcon(android.R.drawable.ic_menu_always_landscape_portrait)
            .setContentTitle(this.getString(R.string.app_name))
            .setOngoing(true)
            .setShowWhen(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12 defers notifications unless told otherwise.
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setCustomContentView(views)
            builder.setCustomBigContentView(views)
            builder.style = Notification.DecoratedCustomViewStyle()
        } else {
            @Suppress("DEPRECATION")
            builder.setContent(views)
        }

        val notification = builder.build()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            @Suppress("DEPRECATION")
            notification.bigContentView = views
        }
        return notification
    }

    private fun highlightSelected(views: RemoteViews) {
        val selectedRotation = lockedRotation
        ROTATION_BUTTON_IDS.forEachIndexed { rotation, id ->
            views.setTextColor(id, if (rotation == selectedRotation) SELECTED_COLOR else DEFAULT_COLOR)
        }
        views.setTextColor(R.id.btn_auto, if (selectedRotation == null) SELECTED_COLOR else DEFAULT_COLOR)
    }

    private fun rotatePendingIntent(rotation: Int): PendingIntent {
        val intent = Intent(this, RotationService::class.java)
            .setAction(ACTION_ROTATE)
            .putExtra(EXTRA_ROTATION, rotation)

        return servicePendingIntent(rotation, intent)
    }

    private fun autoPendingIntent(): PendingIntent {
        val intent = Intent(this, RotationService::class.java).setAction(ACTION_AUTO)
        return servicePendingIntent(100, intent)
    }

    private fun stopPendingIntent(): PendingIntent {
        val intent = Intent(this, RotationService::class.java).setAction(ACTION_STOP)
        return servicePendingIntent(101, intent)
    }

    private fun servicePendingIntent(requestCode: Int, intent: Intent): PendingIntent {
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

        return PendingIntent.getService(this, requestCode, intent, flags)
    }

    private fun setRotation(rotation: Int) {

        if (!Settings.System.canWrite(this)) {
            Toast.makeText(
                this,
                "WRITE_SETTINGS permission required",
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        try {
            lockedRotation = rotation
            applyLockedRotation(rotation)
            RotationPrefs.saveRotation(this, rotation)
        } catch (e: Exception) {
            Toast.makeText(
                this,
                "Cannot change rotation: ${e.message}",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private fun applyLockedRotation(rotation: Int) {
        // Turn automatic rotation off.
        Settings.System.putInt(
            contentResolver,
            Settings.System.ACCELEROMETER_ROTATION,
            0
        )

        // 0 = portrait
        // 1 = landscape
        // 2 = reverse portrait
        // 3 = reverse landscape
        Settings.System.putInt(
            contentResolver,
            Settings.System.USER_ROTATION,
            rotation
        )
    }

    private fun setAutoRotation() {

        if (!Settings.System.canWrite(this)) {
            Toast.makeText(
                this,
                "WRITE_SETTINGS permission required",
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        lockedRotation = null
        Settings.System.putInt(
            contentResolver,
            Settings.System.ACCELEROMETER_ROTATION,
            1
        )
        RotationPrefs.saveRotation(this, null)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
