package com.bili.tv.bili_tv_app

import android.content.Intent
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val UPDATE_CHANNEL = "com.bili.tv/update"
    private val CODEC_CHANNEL = "com.bili.tv/codec"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // 記錄未捕捉的 Java/Kotlin 例外，下次啟動時詢問是否上傳
        CrashChannel.installHandler(applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CrashChannel.register(flutterEngine, applicationContext)
        FrameChannel.register(flutterEngine)

        // 更新安装 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            result.success(installApk(path))
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                }
                "getSupportedAbis" -> {
                    result.success(Build.SUPPORTED_ABIS.toList())
                }
                "getDeviceInfo" -> {
                    // 錯誤報告用：只回傳裝置硬體與系統版本，不含任何個人資訊
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "release" to Build.VERSION.RELEASE,
                            "sdk" to Build.VERSION.SDK_INT,
                            "abis" to Build.SUPPORTED_ABIS.toList()
                        )
                    )
                }
                "restart" -> {
                    // 啟動新的 task，再結束目前程序，讓所有 Dart 狀態重新開始
                    val launch = packageManager.getLaunchIntentForPackage(packageName)
                    val component = launch?.component
                    if (component == null) {
                        result.error("RESTART_ERROR", "no launch activity", null)
                    } else {
                        result.success(null)
                        val intent = Intent.makeRestartActivityTask(component)
                        startActivity(intent)
                        Runtime.getRuntime().exit(0)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 编码器检测 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CODEC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareDecoders" -> {
                    try {
                        val hwCodecs = getHardwareDecoders()
                        result.success(hwCodecs)
                    } catch (e: Exception) {
                        result.error("CODEC_ERROR", e.message, null)
                    }
                }
                "canHwDecode" -> {
                    val codec = call.argument<String>("codec") ?: ""
                    val w = call.argument<Int>("width") ?: 0
                    val h = call.argument<Int>("height") ?: 0
                    val fps = call.argument<Double>("fps") ?: 0.0
                    result.success(canHwDecode(codec, w, h, fps))
                }
                "decoderCaps" -> {
                    val codec = call.argument<String>("codec") ?: ""
                    val w = call.argument<Int>("width") ?: 0
                    val h = call.argument<Int>("height") ?: 0
                    val fps = call.argument<Double>("fps") ?: 0.0
                    val name = call.argument<String>("decoderName")
                    result.success(decoderCaps(codec, name, w, h, fps))
                }
                "isHdrDisplay" -> result.success(isHdrDisplay())
                "getDeviceInfo" -> result.success(perfDeviceInfo())
                "getProcessCpu" -> result.success(processCpu())
                "getPlayerStats" -> result.success(
                    io.flutter.plugins.videoplayer.PlayerStats.snapshot(call.argument<Boolean>("drain") ?: true)
                )
                else -> result.notImplemented()
            }
        }
    }

    // 效能記錄用：ABI、核心數、記憶體等級、螢幕模式與 HDR（不含個人資訊）
    private fun perfDeviceInfo(): Map<String, Any?> {
        val am = getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            this.display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
        val canMode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
        val mode = if (canMode) display?.mode else null
        val modes = (if (canMode) display?.supportedModes?.toList() else null)?.map {
            "${it.physicalWidth}x${it.physicalHeight}@${"%.1f".format(it.refreshRate)}"
        } ?: emptyList()
        return mapOf(
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "cores" to Runtime.getRuntime().availableProcessors(),
            "memoryClass" to am.memoryClass,
            "isLowRam" to am.isLowRamDevice,
            "modeWidth" to (mode?.physicalWidth ?: 0),
            "modeHeight" to (mode?.physicalHeight ?: 0),
            "modeRefresh" to (mode?.refreshRate?.toDouble() ?: (display?.refreshRate?.toDouble() ?: 0.0)),
            "supportedModes" to modes,
            "hdr" to isHdrDisplay()
        )
    }

    // 讀 /proc/self/stat 的 utime+stime（jiffies）與目前時間，由 Dart 兩次取樣算 CPU 使用率
    private fun processCpu(): Map<String, Any?>? {
        return try {
            val text = File("/proc/self/stat").readText()
            // 第 2 欄 comm 可能含空白，從最後一個 ')' 之後切欄位；其後第 1 欄是第 3 欄 state
            val rest = text.substring(text.lastIndexOf(')') + 2).split(" ")
            val utime = rest[11].toLong()
            val stime = rest[12].toLong()
            mapOf(
                "jiffies" to (utime + stime),
                "elapsedMs" to android.os.SystemClock.elapsedRealtime(),
                "hz" to android.system.Os.sysconf(android.system.OsConstants._SC_CLK_TCK)
            )
        } catch (e: Exception) {
            null
        }
    }

    // 共用硬體判斷：API 29 以上用系統旗標，以下用名稱規則
    private fun isHardwareCodec(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return info.isHardwareAccelerated
        }
        val name = info.name.lowercase()
        return !name.contains("google") &&
            !name.contains("software") &&
            !name.contains("sw") &&
            !name.startsWith("c2.android")
    }

    // 同一個硬體解碼器需同時支援該 MIME、解析度與幀率；例外時回 true（不阻擋）
    private fun canHwDecode(codec: String, width: Int, height: Int, fps: Double): Boolean {
        return try {
            val mime = when (codec) {
                "avc" -> "video/avc"
                "hevc" -> "video/hevc"
                "av1" -> "video/av01"
                else -> return true
            }
            for (info in MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos) {
                if (info.isEncoder) continue
                if (info.name.lowercase().endsWith(".secure")) continue
                if (!isHardwareCodec(info)) continue
                if (info.supportedTypes.none { it.equals(mime, ignoreCase = true) }) continue
                val vc = info.getCapabilitiesForType(mime).videoCapabilities ?: continue
                val ok = if (fps > 0) {
                    vc.areSizeAndRateSupported(width, height, fps)
                } else {
                    vc.isSizeSupported(width, height)
                }
                if (ok) return true
            }
            false
        } catch (e: Exception) {
            true
        }
    }

    // 解碼器能力診斷：隧道支援、可達幀率、效能點。優先查目前播放中的解碼器名稱，
    // 查不到再找第一個支援該 MIME 的硬體解碼器；任何例外回 null
    private fun decoderCaps(
        codec: String,
        decoderName: String?,
        width: Int,
        height: Int,
        fps: Double
    ): Map<String, Any?>? {
        return try {
            val mime = when (codec) {
                "avc" -> "video/avc"
                "hevc" -> "video/hevc"
                "av1" -> "video/av01"
                else -> return null
            }
            val infos = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.filter {
                !it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, ignoreCase = true) }
            }
            val info = infos.firstOrNull { !decoderName.isNullOrEmpty() && it.name == decoderName }
                ?: infos.firstOrNull { isHardwareCodec(it) && !it.name.lowercase().endsWith(".secure") }
                ?: return null
            val caps = info.getCapabilitiesForType(mime)
            val tunnel = caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback)
            val vc = caps.videoCapabilities
            val achievable = vc?.getAchievableFrameRatesFor(width, height)?.let {
                "${it.lower}-${it.upper}"
            }
            var perfPointOk: Boolean? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && vc != null) {
                val points = vc.supportedPerformancePoints
                if (points != null) {
                    val target = MediaCodecInfo.VideoCapabilities.PerformancePoint(width, height, fps.toInt())
                    perfPointOk = points.any { it.covers(target) }
                }
            }
            mapOf(
                "name" to info.name,
                "tunnel" to tunnel,
                "achievable" to achievable,
                "perfPointOk" to perfPointOk
            )
        } catch (e: Exception) {
            null
        }
    }

    // 顯示器是否支援 HDR（API 24 以上）
    private fun isHdrDisplay(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                this.display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            val types = display?.hdrCapabilities?.supportedHdrTypes
            types != null && types.isNotEmpty()
        } catch (e: Exception) {
            false
        }
    }

    // 获取硬件解码器支持的格式
    private fun getHardwareDecoders(): List<String> {
        val supportedFormats = mutableSetOf<String>()
        val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        
        for (info in codecList.codecInfos) {
            // 只检查解码器，跳过编码器
            if (info.isEncoder) continue
            
            // 检查是否是硬件解码器 (不包含 google/software)
            if (isHardwareCodec(info)) {
                for (type in info.supportedTypes) {
                    when {
                        type.equals("video/avc", ignoreCase = true) -> supportedFormats.add("avc")
                        type.equals("video/hevc", ignoreCase = true) -> supportedFormats.add("hevc")
                        type.equals("video/av01", ignoreCase = true) -> supportedFormats.add("av1")
                        type.equals("video/x-vnd.on2.vp9", ignoreCase = true) -> supportedFormats.add("vp9")
                    }
                }
            }
        }
        
        return supportedFormats.toList()
    }

    // 回傳 "ok"，或 "permission"（需先允許安裝未知來源，已開啟設定頁）
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) {
            throw Exception("APK file not found: $path")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settings = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            settings.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            try {
                startActivity(settings)
            } catch (e: ActivityNotFoundException) {
                val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
                fallback.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(fallback)
            }
            return "permission"
        }

        val intent = Intent(Intent.ACTION_VIEW)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Android 7.0+ 使用 FileProvider
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
            intent.setDataAndType(uri, "application/vnd.android.package-archive")
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            // 旧版本直接使用文件路径
            intent.setDataAndType(
                android.net.Uri.fromFile(file),
                "application/vnd.android.package-archive"
            )
        }

        startActivity(intent)
        return "ok"
    }
}
