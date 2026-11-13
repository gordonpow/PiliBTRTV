package com.bili.tv.bili_tv_app

import android.graphics.Bitmap
import android.media.MediaDataSource
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.Executors

object FrameChannel {
    private const val CHANNEL = "com.bili.tv/frame"
    private const val TAG = "FrameChannel"
    private const val USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var currentUrl: String? = null
    private var retriever: MediaMetadataRetriever? = null

    @Volatile
    private var latestLocalGen = 0L

    /** 把多個檔案依序虛擬串接成一個資料來源（不複製位元組），用 RandomAccessFile 依 offset 讀取。 */
    @android.annotation.TargetApi(Build.VERSION_CODES.M)
    private class ConcatDataSource(paths: List<String>) : MediaDataSource() {
        private val files = ArrayList<RandomAccessFile>()
        private val sizes = ArrayList<Long>()
        private val total: Long

        init {
            try {
                for (p in paths) {
                    val f = RandomAccessFile(p, "r")
                    files.add(f)
                    sizes.add(f.length())
                }
            } catch (e: Exception) {
                close()
                throw e
            }
            total = sizes.sum()
        }

        @Synchronized
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
            if (position >= total) return -1
            var pos = position
            var idx = 0
            while (idx < files.size && pos >= sizes[idx]) {
                pos -= sizes[idx]
                idx++
            }
            var done = 0
            while (done < size && idx < files.size) {
                val f = files[idx]
                f.seek(pos)
                val want = minOf((size - done).toLong(), sizes[idx] - pos).toInt()
                val n = f.read(buffer, offset + done, want)
                if (n <= 0) break
                done += n
                pos += n
                if (pos >= sizes[idx]) {
                    idx++
                    pos = 0
                }
            }
            return if (done == 0) -1 else done
        }

        override fun getSize(): Long = total

        override fun close() {
            for (f in files) {
                try { f.close() } catch (_: Exception) {}
            }
        }
    }

    /** 解出串接檔案的第一個關鍵幀並編成 JPEG；綠色壞幀回 null。 */
    @android.annotation.TargetApi(Build.VERSION_CODES.M)
    private fun decodeLocal(paths: List<String>, width: Int): ByteArray? {
        val src = ConcatDataSource(paths)
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(src)
            val height = width * 9 / 16
            val bmp: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                r.getScaledFrameAtTime(0L, MediaMetadataRetriever.OPTION_NEXT_SYNC, width, height)
            } else {
                val raw = r.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_NEXT_SYNC)
                if (raw != null) {
                    val scaled = Bitmap.createScaledBitmap(raw, width, height, true)
                    if (scaled != raw) raw.recycle()
                    scaled
                } else {
                    null
                }
            }
            if (bmp == null) return null
            if (isMostlyGreen(bmp)) {
                bmp.recycle()
                return null
            }
            val stream = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            bmp.recycle()
            return stream.toByteArray()
        } finally {
            try { r.release() } catch (_: Exception) {}
            try { src.close() } catch (_: Exception) {}
        }
    }

    /** 8x8 格點抽樣：R、B < 40 且 G > 60 的比例超過 90% 就視為綠色壞幀。 */
    private fun isMostlyGreen(bmp: Bitmap): Boolean {
        val w = bmp.width
        val h = bmp.height
        if (w <= 0 || h <= 0) return false
        var green = 0
        var total = 0
        for (iy in 0 until 8) {
            for (ix in 0 until 8) {
                val p = bmp.getPixel((ix * w + w / 2) / 8, (iy * h + h / 2) / 8)
                val rr = (p shr 16) and 0xFF
                val gg = (p shr 8) and 0xFF
                val bb = p and 0xFF
                total++
                if (rr < 40 && bb < 40 && gg > 60) green++
            }
        }
        return green * 10 > total * 9
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFrame" -> {
                    val url = call.argument<String>("url")
                    val timeMs = (call.argument<Number>("timeMs"))?.toLong() ?: 0L
                    val width = call.argument<Int>("width") ?: 480

                    if (url.isNullOrEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            if (currentUrl != url) {
                                try {
                                    retriever?.release()
                                } catch (e: Exception) {
                                    Log.w(TAG, "Failed to release previous retriever", e)
                                }
                                val r = MediaMetadataRetriever()
                                try {
                                    if (url.startsWith("/")) {
                                        // 本機檔案（直播時移預覽）
                                        r.setDataSource(url)
                                    } else {
                                        val headers = mapOf(
                                            "Referer" to "https://www.bilibili.com/",
                                            "User-Agent" to USER_AGENT
                                        )
                                        r.setDataSource(url, headers)
                                    }
                                } catch (e: Exception) {
                                    try { r.release() } catch (_: Exception) {}
                                    throw e
                                }
                                retriever = r
                                currentUrl = url
                            }

                            val timeUs = timeMs * 1000L
                            val height = width * 9 / 16
                            val r = retriever
                            // 本機時移片段只有開頭一個關鍵幀，用 NEXT_SYNC 避免取到綠幕
                            val frameOption = if (url.startsWith("/")) {
                                MediaMetadataRetriever.OPTION_NEXT_SYNC
                            } else {
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                            }
                            val bitmap: Bitmap? = if (r != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                                    r.getScaledFrameAtTime(
                                        timeUs,
                                        frameOption,
                                        width,
                                        height
                                    )
                                } else {
                                    val raw = r.getFrameAtTime(
                                        timeUs,
                                        frameOption
                                    )
                                    if (raw != null) {
                                        val scaled = Bitmap.createScaledBitmap(raw, width, height, true)
                                        if (scaled != raw) {
                                            raw.recycle()
                                        }
                                        scaled
                                    } else {
                                        null
                                    }
                                }
                            } else {
                                null
                            }

                            // 本機時移片段偶爾解出整張綠色（缺少參考幀）：視為沒有圖
                            val usable: Bitmap? = if (bitmap != null && url.startsWith("/") && isMostlyGreen(bitmap)) {
                                bitmap.recycle()
                                null
                            } else {
                                bitmap
                            }
                            val jpegBytes: ByteArray? = if (usable != null) {
                                val stream = ByteArrayOutputStream()
                                usable.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                                usable.recycle()
                                stream.toByteArray()
                            } else {
                                null
                            }

                            mainHandler.post {
                                result.success(jpegBytes)
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "getFrame failed for url: $url at $timeMs ms", e)
                            mainHandler.post {
                                result.success(null)
                            }
                        }
                    }
                }
                "getLocalFrame" -> {
                    val paths = call.argument<List<String>>("paths")
                    val width = call.argument<Int>("width") ?: 320
                    val gen = call.argument<Number>("gen")?.toLong() ?: 0L
                    if (paths.isNullOrEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    // 預覽請求（gen > 0）到達時記下最新序號，排隊中的舊預覽請求開始處理前就會被丟棄；
                    // 背景預先擷取（gen = 0）不參與丟棄，也不會讓預覽請求失效
                    if (gen > latestLocalGen) latestLocalGen = gen
                    executor.execute {
                        if (gen > 0 && gen < latestLocalGen) {
                            mainHandler.post { result.success(null) }
                            return@execute
                        }
                        val bytes = try {
                            decodeLocal(paths, width)
                        } catch (e: Exception) {
                            Log.w(TAG, "getLocalFrame failed", e)
                            null
                        }
                        mainHandler.post { result.success(bytes) }
                    }
                }
                "release" -> {
                    executor.execute {
                        try {
                            retriever?.release()
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to release retriever", e)
                        } finally {
                            retriever = null
                            currentUrl = null
                        }
                        mainHandler.post {
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
