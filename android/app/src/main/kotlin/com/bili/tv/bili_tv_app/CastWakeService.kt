package com.bili.tv.bili_tv_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID

/**
 * App 未開啟時接收手機投放的前景服務（協定 v1，與 lib/services/cast/cast_service.dart 對應）。
 * 只在沒有 MainActivity 存活時監聽 TCP 3322；MainActivity 存活時由 Dart 的 LocalServer 擁有該連接埠。
 */
class CastWakeService : Service() {

    companion object {
        private const val TAG = "CastWake"
        const val PORT = 3322
        const val EXTRA_PAYLOAD = "cast_payload"
        private const val EXTRA_ENABLED = "enabled"
        private const val CHANNEL_ID = "cast_background"
        private const val NOTIFICATION_ID = 6201

        // 注意：以下 key 依賴 shared_preferences_android 舊版 API（2.4.x）：
        // 檔名 FlutterSharedPreferences、key 前綴 flutter.。升級該套件到新 API 時這裡要一起改。
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_BACKGROUND = "flutter.cast_background"
        private const val KEY_TV_ID = "flutter.cast_tv_id"
        private const val KEY_PAIRED = "flutter.cast_paired"

        private const val MAX_BYTES = 8 * 1024
        private const val BIND_RETRY_MS = 2000L
        private const val BIND_RETRY_MAX = 30
        private const val RESUME_DELAY_MS = 1500L
        private const val WATCHDOG_MS = 10_000L
        private const val OVERLAY_MS = 3000L
        private const val WAKE_COOLDOWN_MS = 30_000L
        private val BVID_RE = Regex("^BV[0-9A-Za-z]{10}$")

        /** MainActivity 存活數，由 MainActivity 維護（只在主執行緒修改）。 */
        @Volatile
        var activityAlive: Int = 0

        @Volatile
        private var instance: CastWakeService? = null

        fun isEnabled(ctx: Context): Boolean = try {
            ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_BACKGROUND, false)
        } catch (e: Exception) {
            false
        }

        fun start(ctx: Context) {
            try {
                val intent = Intent(ctx, CastWakeService::class.java).putExtra(EXTRA_ENABLED, true)
                ContextCompat.startForegroundService(ctx, intent)
            } catch (e: Exception) {
                Log.w(TAG, "start failed: $e")
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.stopService(Intent(ctx, CastWakeService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "stop failed: $e")
            }
        }

        /** 同步關閉監聽（可在主執行緒呼叫）。 */
        fun pauseListening() {
            instance?.closeListener()
        }

        /** 延遲後重新監聽；執行時再檢查沒有 Activity 且服務仍在。 */
        fun resumeListening() {
            val svc = instance ?: return
            svc.mainHandler.postDelayed({
                val s = instance
                if (s != null && s === svc && activityAlive == 0) s.openListener()
            }, RESUME_DELAY_MS)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var generation = 0
    private var server: ServerSocket? = null
    private var failed = false
    private var lastWakeAt = 0L
    private var overlayView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "投放接收", NotificationManager.IMPORTANCE_LOW)
                )
            }
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // API 31 以上背景啟動可能丟 ForegroundServiceStartNotAllowedException
            Log.w(TAG, "startForeground failed: $e")
            failed = true
            stopSelf()
        }
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("PiliBTRTV 投放接收中")
            .setContentText("手機可以直接投放到這台電視")
            .setContentIntent(open)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (failed) return START_NOT_STICKY
        // 有 enabled extra 時以它為準；開機、系統重啟（intent 為 null）才讀設定
        val enabled = if (intent != null && intent.hasExtra(EXTRA_ENABLED)) {
            intent.getBooleanExtra(EXTRA_ENABLED, false)
        } else {
            isEnabled(this)
        }
        if (!enabled) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (activityAlive == 0) openListener()
        return START_STICKY
    }

    override fun onDestroy() {
        closeListener()
        removeOverlay()
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ---------- 監聽 ----------

    /** 同步關閉 ServerSocket，並讓進行中的繫結重試作廢。 */
    private fun closeListener() {
        synchronized(lock) {
            generation++
            try {
                server?.close()
            } catch (_: Exception) {
            }
            server = null
        }
    }

    /** 開始監聽：先作廢舊執行緒，再開新的繫結執行緒。 */
    private fun openListener() {
        val gen: Int
        synchronized(lock) {
            if (server != null) return
            generation++
            gen = generation
        }
        Thread({ listenLoop(gen) }, "CastWake-listen").start()
    }

    private fun isCurrent(gen: Int): Boolean =
        synchronized(lock) { gen == generation } && activityAlive == 0 && instance === this

    private fun listenLoop(gen: Int) {
        var sock: ServerSocket? = null
        var attempts = 0
        while (attempts < BIND_RETRY_MAX && isCurrent(gen)) {
            attempts++
            try {
                val s = ServerSocket()
                s.reuseAddress = true
                s.bind(InetSocketAddress(PORT))
                synchronized(lock) {
                    if (gen != generation) {
                        s.close()
                        return
                    }
                    server = s
                }
                sock = s
                break
            } catch (e: Exception) {
                Log.w(TAG, "bind $PORT failed (#$attempts): $e")
                try {
                    Thread.sleep(BIND_RETRY_MS)
                } catch (_: InterruptedException) {
                    return
                }
            }
        }
        if (sock == null) {
            if (isCurrent(gen)) Log.w(TAG, "give up binding $PORT")
            return
        }
        Log.i(TAG, "listening on $PORT")
        while (isCurrent(gen)) {
            val client = try {
                sock.accept()
            } catch (e: Exception) {
                break
            }
            try {
                client.soTimeout = 5000
                handle(client)
            } catch (e: Exception) {
                Log.w(TAG, "handle failed: $e")
            } finally {
                try {
                    client.close()
                } catch (_: Exception) {
                }
            }
        }
        synchronized(lock) {
            if (server === sock) server = null
        }
        try {
            sock.close()
        } catch (_: Exception) {
        }
    }

    // ---------- HTTP ----------

    private class HttpError(val code: Int, val reason: String) : Exception(reason)

    private fun handle(client: Socket) {
        val input = BufferedInputStream(client.getInputStream())
        val out = client.getOutputStream()
        try {
            val head = readHead(input)
            val lines = head.split("\r\n")
            val parts = lines[0].split(" ")
            if (parts.size < 3) throw HttpError(400, "bad_request")
            val method = parts[0]
            val path = parts[1].substringBefore('?').substringBefore('#')
            val headers = HashMap<String, String>()
            for (i in 1 until lines.size) {
                val line = lines[i]
                val idx = line.indexOf(':')
                if (idx <= 0) continue
                headers[line.substring(0, idx).trim().lowercase()] = line.substring(idx + 1).trim()
            }
            if (headers.containsKey("transfer-encoding")) throw HttpError(411, "length_required")
            route(method, path, headers, input, out)
        } catch (e: HttpError) {
            send(out, e.code, JSONObject().put("ok", false).put("reason", e.reason))
        } catch (e: java.net.SocketTimeoutException) {
            send(out, 408, JSONObject().put("ok", false).put("reason", "timeout"))
        } catch (e: IOException) {
            // 手機已斷線
        }
    }

    /** 讀到 CRLF CRLF 為止（不含結尾），上限 8 KB。 */
    private fun readHead(input: InputStream): String {
        val buf = ByteArrayOutputStream()
        var state = 0
        while (true) {
            val b = input.read()
            if (b < 0) throw IOException("eof")
            buf.write(b)
            if (buf.size() > MAX_BYTES) throw HttpError(431, "header_too_large")
            state = when {
                b == '\r'.code && (state == 0 || state == 2) -> state + 1
                b == '\n'.code && (state == 1 || state == 3) -> state + 1
                else -> 0
            }
            if (state == 4) break
        }
        val s = buf.toString("ISO-8859-1")
        return s.substring(0, s.length - 4)
    }

    private fun route(
        method: String,
        path: String,
        headers: Map<String, String>,
        input: InputStream,
        out: java.io.OutputStream
    ) {
        when (path) {
            "/api/cast/info" -> {
                if (method != "GET") throw HttpError(405, "method_not_allowed")
                val name = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
                send(
                    out, 200,
                    JSONObject().put("app", "PiliBTRTV").put("v", 1).put("id", tvId())
                        .put("name", name.ifEmpty { "Android TV" }).put("port", PORT)
                )
            }
            "/api/cast/play" -> {
                if (method != "POST") throw HttpError(405, "method_not_allowed")
                handlePlay(headers, input, out)
            }
            "/api/cast/result" -> {
                if (method != "GET") throw HttpError(405, "method_not_allowed")
                throw HttpError(404, "not_found")
            }
            else -> throw HttpError(404, "not_found")
        }
    }

    private fun handlePlay(headers: Map<String, String>, input: InputStream, out: java.io.OutputStream) {
        val mime = headers["content-type"]?.substringBefore(';')?.trim()?.lowercase()
        if (mime != "application/json") throw HttpError(415, "unsupported_media_type")
        val len = headers["content-length"]?.trim()?.toIntOrNull()
        if (len == null || len < 0) throw HttpError(400, "bad_request")
        if (len > MAX_BYTES) throw HttpError(413, "payload_too_large")
        if (headers["expect"]?.trim()?.lowercase() == "100-continue" && len > 0) {
            out.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
            out.flush()
        }
        val bytes = ByteArray(len)
        var read = 0
        while (read < len) {
            val n = input.read(bytes, read, len - read)
            if (n < 0) throw IOException("eof")
            read += n
        }
        val raw = String(bytes, Charsets.UTF_8)
        val body = try {
            JSONObject(raw)
        } catch (e: Exception) {
            throw HttpError(400, "bad_request")
        }
        val deviceId = body.opt("deviceId")
        if (deviceId !is String || deviceId.isEmpty() || deviceId.length > 64) {
            throw HttpError(400, "bad_request")
        }
        val epId = asLong(body.opt("epId"))
        val bvid = body.opt("bvid")
        if (!((epId != null && epId > 0) || (bvid is String && BVID_RE.matches(bvid)))) {
            throw HttpError(400, "bad_request")
        }

        val token = body.opt("token")
        if (token !is String || token.isEmpty()) {
            // 未配對：只喚起 App（有冷卻），不播放
            send(out, 503, JSONObject().put("ok", false).put("reason", "not_ready"))
            val now = SystemClock.elapsedRealtime()
            if (lastWakeAt == 0L || now - lastWakeAt >= WAKE_COOLDOWN_MS) {
                lastWakeAt = now
                launchApp(null)
            }
            return
        }
        if (!tokenMatches(deviceId, token)) {
            throw HttpError(403, "bad_token")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !Settings.canDrawOverlays(this)) {
            throw HttpError(503, "not_ready")
        }
        send(out, 200, JSONObject().put("ok", true))
        pauseListening()
        launchApp(raw)
    }

    private fun asLong(v: Any?): Long? = when (v) {
        is Number -> v.toLong()
        is String -> v.toLongOrNull()
        else -> null
    }

    /** 在已配對清單找同 deviceId 的 token，以 constant-time 比對。 */
    private fun tokenMatches(deviceId: String, token: String): Boolean {
        return try {
            val raw = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_PAIRED, null)
            if (raw.isNullOrEmpty()) return false
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val e = arr.optJSONObject(i) ?: continue
                if (e.optString("deviceId") == deviceId) {
                    val saved = e.optString("token")
                    return saved.isNotEmpty() &&
                        MessageDigest.isEqual(
                            saved.toByteArray(Charsets.UTF_8),
                            token.toByteArray(Charsets.UTF_8)
                        )
                }
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun tvId(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val cur = prefs.getString(KEY_TV_ID, null)
        if (!cur.isNullOrEmpty()) return cur
        val id = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_TV_ID, id).apply()
        return id
    }

    private fun send(out: java.io.OutputStream, code: Int, body: JSONObject) {
        try {
            val text = when (code) {
                200 -> "OK"
                400 -> "Bad Request"
                403 -> "Forbidden"
                404 -> "Not Found"
                405 -> "Method Not Allowed"
                408 -> "Request Timeout"
                411 -> "Length Required"
                413 -> "Payload Too Large"
                415 -> "Unsupported Media Type"
                431 -> "Request Header Fields Too Large"
                503 -> "Service Unavailable"
                else -> "Error"
            }
            val payload = body.toString().toByteArray(Charsets.UTF_8)
            val head = "HTTP/1.1 $code $text\r\n" +
                "Content-Type: application/json\r\n" +
                "Cache-Control: no-store\r\n" +
                "Connection: close\r\n" +
                "Content-Length: ${payload.size}\r\n\r\n"
            out.write(head.toByteArray(Charsets.ISO_8859_1))
            out.write(payload)
            out.flush()
        } catch (_: Exception) {
            // 手機已斷線
        }
    }

    // ---------- 開啟 App ----------

    private fun launchApp(payload: String?) {
        mainHandler.post {
            try {
                // R-1：API 29 以上先放一個透明 overlay 視窗，提高背景開啟 Activity 的成功率
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) addOverlay()
                val intent = Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                if (payload != null) intent.putExtra(EXTRA_PAYLOAD, payload)
                startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "launchApp failed: $e")
            }
            mainHandler.postDelayed({ removeOverlay() }, OVERLAY_MS)
            // R-2：看門狗，App 沒有起來就恢復監聽
            mainHandler.postDelayed({
                if (activityAlive == 0) resumeListening()
            }, WATCHDOG_MS)
        }
    }

    private fun addOverlay() {
        try {
            if (overlayView != null || !Settings.canDrawOverlays(this)) return
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val view = View(this)
            val lp = WindowManager.LayoutParams(
                1, 1,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )
            wm.addView(view, lp)
            overlayView = view
        } catch (e: Exception) {
            Log.w(TAG, "addOverlay failed: $e")
        }
    }

    private fun removeOverlay() {
        val view = overlayView ?: return
        overlayView = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(view)
        } catch (e: Exception) {
            Log.w(TAG, "removeOverlay failed: $e")
        }
    }
}
