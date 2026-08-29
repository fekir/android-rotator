package info.fekir.rotator

import android.app.Activity
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

class MainActivity : Activity() {
  private companion object {
    const val NOTIFICATION_PERMISSION_REQUEST = 1
    const val PADDING = 40
  }

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
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      notificationSettingsCheckbox.isChecked = true
    } else {
      notificationSettingsCheckbox.text = "Notification permission (required)"
      notificationSettingsCheckbox.isChecked =
        checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED
      notificationSettingsCheckbox.setOnTouchListener { _, event ->
        if (event.action == MotionEvent.ACTION_DOWN && !notificationSettingsCheckbox.isChecked) {
          requestPermissions(
            arrayOf("android.permission.POST_NOTIFICATIONS"),
            NOTIFICATION_PERMISSION_REQUEST
          )
        }
        true
      }
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
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      notificationSettingsCheckbox.isChecked =
        checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED
    }
  }
}
