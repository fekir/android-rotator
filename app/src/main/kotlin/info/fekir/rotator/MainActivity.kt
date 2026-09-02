package info.fekir.rotator

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.MotionEvent
import android.view.WindowInsets
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.Toast
import info.fekir.rotator.R

private data class Insets(
  val left: Int,
  val top: Int,
  val right: Int,
  val bottom: Int
)

private fun systemInsets(insets: WindowInsets): Insets =
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
    val result = insets.getInsets(WindowInsets.Type.systemBars())

    Insets(
      left = result.left,
      top = result.top,
      right = result.right,
      bottom = result.bottom
    )
  } else {
    @Suppress("DEPRECATION")
    Insets(
      left = insets.systemWindowInsetLeft,
      top = insets.systemWindowInsetTop,
      right = insets.systemWindowInsetRight,
      bottom = insets.systemWindowInsetBottom
    )
  }

private const val NOTIFICATION_CHANNEL_ID = "general_notifications"
private const val NOTIFICATION_PERMISSION_REQUEST = 1
private const val PADDING = 40

private fun areNotificationsEnabled(context: Context): Boolean {
  assert(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)

  val notificationManager =
    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

  if (!notificationManager.areNotificationsEnabled()) {
    return false
  }

  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    val channel =
      notificationManager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)

    if (channel != null &&
      channel.importance == NotificationManager.IMPORTANCE_NONE
    ) {
      return false
    }
  }

  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
    context.checkSelfPermission(
      Manifest.permission.POST_NOTIFICATIONS
    ) != PackageManager.PERMISSION_GRANTED
  ) {
    return false
  }

  return true
}

private fun configureNotificationCheckbox(
  checkbox: CheckBox,
  activity: Activity
) {
  assert(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
  checkbox.isChecked = areNotificationsEnabled(activity)

  checkbox.setOnTouchListener { _, event ->
    if (event.action == MotionEvent.ACTION_DOWN && !checkbox.isChecked) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        activity.requestPermissions(
          arrayOf(Manifest.permission.POST_NOTIFICATIONS),
          NOTIFICATION_PERMISSION_REQUEST
        )
      } else {
        val intent =
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
              putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
              putExtra(
                Settings.EXTRA_CHANNEL_ID,
                NOTIFICATION_CHANNEL_ID
              )
            }
          } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
              putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            }
          }

        activity.startActivity(intent)
      }
    }
    true
  }
}

class MainActivity : Activity() {
  // https://developer.android.com/guide/components/activities/activity-lifecycle
  //
  //              +--------------------------------------------------+
  //              |                                                  |
  //              +                           +----------------------+
  //              |                           |                      |
  //              v                           v                      |
  // start -> onCreate() -> onStart() -> onResume() -> running -> onPause() -> onStop() -> onDestroy()
  //              ^            ^                                                  |
  //              |            |                                                  |
  //              |            +-------------------- onRestart() -----------------+
  //              |                                                               |
  //              +--------------------------- killed ----------------------------+

  private lateinit var changeSettingsCheckbox: CheckBox
  private lateinit var notificationSettingsCheckbox: CheckBox

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    val layout =
      LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(PADDING, PADDING, PADDING, PADDING)
      }

    // See https://developer.android.com/about/versions/15/behavior-changes-15#edge-to-edge
    layout.setOnApplyWindowInsetsListener { view, insets ->
      val system = systemInsets(insets)
      view.setPadding(
        PADDING + system.left,
        PADDING + system.top,
        PADDING + system.right,
        PADDING + system.bottom
      )
      insets
    }

    changeSettingsCheckbox = CheckBox(this)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      changeSettingsCheckbox.isChecked = true
    } else {
      changeSettingsCheckbox.text = "Change system settings (required)"
      changeSettingsCheckbox.isChecked = Settings.System.canWrite(this)
      changeSettingsCheckbox.setOnTouchListener { _, event ->
        if (event.action == MotionEvent.ACTION_DOWN && !changeSettingsCheckbox.isChecked) {
          val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName"))
          startActivity(intent)
        }
        true
      }
      layout.addView(changeSettingsCheckbox)
    }

    notificationSettingsCheckbox = CheckBox(this)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      // Note: it is possible to mute an Application on Android 6 too, but
      // * I found no way to query if the application has bene muted
      //  * one has to mute the application explicitely, user is not asked to grant permission
      notificationSettingsCheckbox.isChecked = true
    } else {
      notificationSettingsCheckbox.text = "Notification permission (required)"
      configureNotificationCheckbox(notificationSettingsCheckbox, this)
      layout.addView(notificationSettingsCheckbox)
    }

    val startButton = Button(this)
    startButton.text = "Start " + this.getString(R.string.app_name)
    startButton.setOnClickListener {
      if (!changeSettingsCheckbox.isChecked || !notificationSettingsCheckbox.isChecked) {
        Toast.makeText(this, "Not all permissions are set", Toast.LENGTH_LONG).show()
      } else {
        val intent = Intent(this, RotationService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          startForegroundService(intent)
        } else {
          startService(intent)
        }
        Toast.makeText(this, "Pull down the notification bar to change orientation", Toast.LENGTH_LONG).show()
      }
    }
    layout.addView(startButton)

    val autostartCheckBox = CheckBox(this)
    autostartCheckBox.text = "Start automatically on boot (optional)"
    autostartCheckBox.isChecked = RotationPrefs.isAutostartEnabled(this)
    autostartCheckBox.setOnCheckedChangeListener { _, isChecked ->
      RotationPrefs.setAutostartEnabled(this, isChecked)
    }
    layout.addView(autostartCheckBox)

    val stopButton = Button(this)
    stopButton.text = "Stop " + this.getString(R.string.app_name)
    stopButton.setOnClickListener {
      stopService(Intent(this, RotationService::class.java))
    }
    layout.addView(stopButton)
    setContentView(layout)
  }

  override fun onResume() {
    super.onResume()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      changeSettingsCheckbox.isChecked = Settings.System.canWrite(this)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      notificationSettingsCheckbox.isChecked = areNotificationsEnabled(this)
    }
  }
}
