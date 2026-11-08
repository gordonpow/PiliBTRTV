package com.bili.tv.bili_tv_app

import android.annotation.TargetApi
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs

object CrashChannel {
    private const val CHANNEL_NAME = "com.bili.tv/crash"
    private const val PREFS_NAME = "crash_prefs"
    private const val KEY_ACKED_TS = "acked_ts"
    private const val CRASH_FILE_NAME = "last_crash.txt"

    @Volatile
    private var defaultHandlerInstalled = false

    fun installHandler(context: Context) {
        if (defaultHandlerInstalled) return
        defaultHandlerInstalled = true

        val appContext = context.applicationContext
        // 首次安裝或清除資料：以目前時間為基準，之前的系統紀錄不詢問；
        // 之後（包含這次執行）發生的閃退時間一定大於基準
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_ACKED_TS)) {
            prefs.edit().putLong(KEY_ACKED_TS, System.currentTimeMillis()).commit()
        }
        val originalHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val file = File(appContext.filesDir, CRASH_FILE_NAME)
                val stack = Log.getStackTraceString(throwable)
                file.writeText("${System.currentTimeMillis()}\n$stack")
            } catch (_: Exception) {
            }
            originalHandler?.uncaughtException(thread, throwable)
        }
    }

    fun register(engine: FlutterEngine, context: Context) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLastCrash" -> {
                    try {
                        result.success(getLastCrash(context))
                    } catch (e: Exception) {
                        result.error("CRASH_ERROR", e.message, null)
                    }
                }
                "ackCrash" -> {
                    try {
                        val ts = when (val arg = call.arguments) {
                            is Number -> arg.toLong()
                            is Map<*, *> -> (arg["timestamp"] ?: arg["ts"]) as? Number
                            else -> call.argument<Number>("timestamp") ?: call.argument<Number>("ts")
                        }?.toLong()
                        ackCrash(context, ts)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getLastCrash(context: Context): Map<String, Any?>? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ackedTs = prefs.getLong(KEY_ACKED_TS, 0L)

        // 1. API 30 以上讀取 ApplicationExitInfo
        val exitCrash = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            getHistoricalExitCrash(context, ackedTs)
        } else {
            null
        }

        // 2. 讀取 last_crash.txt（API 30 以下只靠此檔案）
        val fileCrash = getFileCrash(context, ackedTs)

        // 3. 合併或選取最新一筆
        return when {
            exitCrash != null && fileCrash != null -> {
                val exitTs = exitCrash["timestamp"] as Long
                val fileTs = fileCrash["timestamp"] as Long
                if (abs(exitTs - fileTs) <= 5000) {
                    // 相差 5 秒內視為同一次，合併成一筆
                    val merged = HashMap<String, Any?>(exitCrash)
                    merged["stack"] = fileCrash["stack"]
                    if (fileTs > exitTs) {
                        merged["timestamp"] = fileTs
                    }
                    merged
                } else if (exitTs >= fileTs) {
                    exitCrash
                } else {
                    fileCrash
                }
            }
            exitCrash != null -> exitCrash
            fileCrash != null -> fileCrash
            else -> null
        }
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun getHistoricalExitCrash(context: Context, ackedTs: Long): Map<String, Any?>? {
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return null
            val exitInfos = am.getHistoricalProcessExitReasons(context.packageName, 0, 5) ?: return null
            for (info in exitInfos) {
                if (info.timestamp > ackedTs) {
                    val reasonStr = when (info.reason) {
                        ApplicationExitInfo.REASON_CRASH -> "crash"
                        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native"
                        ApplicationExitInfo.REASON_ANR -> "anr"
                        else -> null
                    }
                    if (reasonStr != null) {
                        // 原生崩潰的 trace 是二進位 protobuf tombstone，只讀 ANR 的文字 trace
                        val traceText = if (info.reason != ApplicationExitInfo.REASON_ANR) null else try {
                            info.traceInputStream?.use { stream ->
                                stream.bufferedReader(Charsets.UTF_8).lineSequence().take(150).joinToString("\n")
                            }
                        } catch (_: Exception) {
                            null
                        }
                        val map = HashMap<String, Any?>()
                        map["reason"] = reasonStr
                        map["timestamp"] = info.timestamp
                        map["description"] = info.description
                        map["trace"] = if (traceText.isNullOrBlank()) null else traceText
                        return map
                    }
                }
            }
        } catch (_: Exception) {
        }
        return null
    }

    private fun getFileCrash(context: Context, ackedTs: Long): Map<String, Any?>? {
        val file = File(context.filesDir, CRASH_FILE_NAME)
        if (!file.exists()) return null
        try {
            val content = file.readText()
            val firstNewline = content.indexOf('\n')
            val tsStr = if (firstNewline != -1) content.substring(0, firstNewline).trim() else content.trim()
            val ts = tsStr.toLongOrNull() ?: return null
            if (ts <= ackedTs) return null
            val stack = if (firstNewline != -1) content.substring(firstNewline + 1).trim() else ""
            val map = HashMap<String, Any?>()
            map["reason"] = "crash"
            map["timestamp"] = ts
            map["description"] = null
            map["stack"] = if (stack.isNotEmpty()) stack else null
            return map
        } catch (_: Exception) {
            return null
        }
    }

    private fun ackCrash(context: Context, timestamp: Long?) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ts = timestamp ?: System.currentTimeMillis()
        val currentAcked = prefs.getLong(KEY_ACKED_TS, 0L)
        prefs.edit().putLong(KEY_ACKED_TS, maxOf(currentAcked, ts)).apply()
        val file = File(context.filesDir, CRASH_FILE_NAME)
        if (file.exists()) {
            try {
                file.delete()
            } catch (_: Exception) {
            }
        }
    }
}
