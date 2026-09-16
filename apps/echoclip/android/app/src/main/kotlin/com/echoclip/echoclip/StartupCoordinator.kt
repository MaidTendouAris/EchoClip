package com.echoclip.echoclip

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/** Compatibility cleanup only: Android no longer offers boot startup. */
internal object StartupCoordinator {
    fun disabledSettings(context: Context): Map<String, Any?> {
        var snapshot = ScheduleCoordinator.snapshot(context)
        if (snapshot["startupEnabled"] == true) {
            snapshot = ScheduleCoordinator.upsert(context,
                JSONObject().put("operation", "set_startup_enabled").put("enabled", false).toString())
        }
        NotificationManagerCompat.from(context).cancel(32610)
        return snapshot + mapOf("startupSupported" to false, "startupEnabled" to false,
            "startupSilent" to false)
    }

    fun onBoot(context: Context) { disabledSettings(context) }
}
