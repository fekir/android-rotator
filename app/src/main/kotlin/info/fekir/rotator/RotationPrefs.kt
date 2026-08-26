package info.fekir.rotator

import android.content.Context

object RotationPrefs {
    private const val PREFS_NAME = "rotation_switcher"
    private const val KEY_LAST_ROTATION = "last_rotation"
    private const val KEY_AUTOSTART = "autostart_enabled"
    private const val NO_ROTATION = -1

    // null means auto-rotate.
    fun saveRotation(context: Context, rotation: Int?) {
        prefs(context).edit().putInt(KEY_LAST_ROTATION, rotation ?: NO_ROTATION).apply()
    }

    fun loadRotation(context: Context): Int? {
        val value = prefs(context).getInt(KEY_LAST_ROTATION, NO_ROTATION)
        return if (value == NO_ROTATION) null else value
    }

    fun setAutostartEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_AUTOSTART, enabled).apply()
    }

    fun isAutostartEnabled(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_AUTOSTART, false)
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
