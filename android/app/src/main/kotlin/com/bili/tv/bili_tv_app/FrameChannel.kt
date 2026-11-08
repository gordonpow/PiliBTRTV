package com.bili.tv.bili_tv_app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
                                val headers = mapOf(
                                    "Referer" to "https://www.bilibili.com/",
                                    "User-Agent" to USER_AGENT
                                )
                                try {
                                    r.setDataSource(url, headers)
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
                            val bitmap: Bitmap? = if (r != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                                    r.getScaledFrameAtTime(
                                        timeUs,
                                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                        width,
                                        height
                                    )
                                } else {
                                    val raw = r.getFrameAtTime(
                                        timeUs,
                                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC
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

                            val jpegBytes: ByteArray? = if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                                bitmap.recycle()
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
