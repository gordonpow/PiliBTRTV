package com.bili.tv.bili_tv_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** 開機或 App 更新後，若使用者開啟「App 未開啟時也接收投放」就啟動 CastWakeService。 */
class CastBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        try {
            if (CastWakeService.isEnabled(context)) CastWakeService.start(context)
        } catch (e: Exception) {
            Log.w("CastWake", "boot start failed: $e")
        }
    }
}
