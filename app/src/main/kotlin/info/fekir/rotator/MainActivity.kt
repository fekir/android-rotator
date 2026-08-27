package info.fekir.rotator

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.Toast
import info.fekir.rotator.R;
import android.view.WindowInsets

private data class Insets(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
)

private fun systemInsets(insets: WindowInsets): Insets {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
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
}

class MainActivity : Activity() {

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 1
        const val PADDING = 40
    }

    private fun leftInset(insets: WindowInsets): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.getInsets(WindowInsets.Type.systemBars()).left
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetLeft
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = LinearLayout(this).apply {
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

        val settingsButton = Button(this)
        settingsButton.text = "Grant permissions"

        settingsButton.setOnClickListener {
            openPermissions()
        }

        val startButton = Button(this)
        startButton.text = "Start " + this.getString(R.string.app_name);

        startButton.setOnClickListener {
            if (hasPermissions()) {
                val intent = Intent(this, RotationService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            } else {
                openPermissions()
            }
        }

        layout.addView(settingsButton)
        layout.addView(startButton)

        val autostartCheckBox = CheckBox(this)
        autostartCheckBox.text = "Start automatically on boot"
        autostartCheckBox.isChecked = RotationPrefs.isAutostartEnabled(this)
        autostartCheckBox.setOnCheckedChangeListener { _, isChecked ->
            RotationPrefs.setAutostartEnabled(this, isChecked)
        }
        layout.addView(autostartCheckBox)

        setContentView(layout)
    }

    private fun hasPermissions(): Boolean {
        val hasNotifications =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                PackageManager.PERMISSION_GRANTED

        return Settings.System.canWrite(this) && hasNotifications
    }

    private fun openPermissions() {
        if (!Settings.System.canWrite(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_WRITE_SETTINGS,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf("android.permission.POST_NOTIFICATIONS"),
                NOTIFICATION_PERMISSION_REQUEST
            )
        }
    }
}
