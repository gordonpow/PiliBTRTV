package io.flutter.plugins.videoplayer;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.os.Build;
import android.os.SystemClock;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DecoderCounters;
import androidx.media3.exoplayer.DecoderReuseEvaluation;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import java.lang.ref.WeakReference;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/** 播放診斷統計：只保留最近建立的播放器資料，供 App 透過 MethodChannel 讀取。 */
@OptIn(markerClass = UnstableApi.class)
public final class PlayerStats {
  private static final Object LOCK = new Object();
  private static final int MAX_EVENTS = 50;

  private static String decoderName = "";
  private static boolean isHardware = false;
  private static long decoderInitMs = 0;
  private static int inputWidth = 0;
  private static int inputHeight = 0;
  private static float inputFps = 0f;
  private static long droppedTotal = 0;
  private static long renderedTotal = 0;

  // 影格處理延遲（區間累加，snapshot 後清空）
  private static long frameOffsetSumUs = 0;
  private static long frameOffsetCount = 0;
  private static long bandwidthBps = 0;
  private static int bufferingCount = 0;
  private static long bufferingStartMs = -1;
  private static long bufferingTotalMs = 0;
  private static final ArrayDeque<String> events = new ArrayDeque<>();

  private static WeakReference<ExoPlayer> playerRef = new WeakReference<>(null);

  private PlayerStats() {}

  /** 註冊最近建立的播放器，並清掉上一個播放器的統計。 */
  public static void attach(@NonNull ExoPlayer player) {
    synchronized (LOCK) {
      playerRef = new WeakReference<>(player);
      decoderName = "";
      isHardware = false;
      decoderInitMs = 0;
      inputWidth = 0;
      inputHeight = 0;
      inputFps = 0f;
      bandwidthBps = 0;
      droppedTotal = 0;
      renderedTotal = 0;
      frameOffsetSumUs = 0;
      frameOffsetCount = 0;
      bufferingCount = 0;
      bufferingStartMs = -1;
      bufferingTotalMs = 0;
      events.clear();
    }
  }

  private static void addEvent(String s) {
    // 呼叫端已持有 LOCK
    if (events.size() >= MAX_EVENTS) events.pollFirst();
    events.addLast(s);
  }

  private static final Map<String, Boolean> hwCache = new HashMap<>();

  private static boolean queryHardware(String name) {
    synchronized (hwCache) {
      Boolean c = hwCache.get(name);
      if (c != null) return c;
      boolean v = queryHardwareUncached(name);
      hwCache.put(name, v);
      return v;
    }
  }

  private static boolean queryHardwareUncached(String name) {
    try {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        String n = name.toLowerCase();
        return !n.contains("google") && !n.contains("software") && !n.startsWith("c2.android");
      }
      for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
        if (!info.isEncoder() && info.getName().equals(name)) {
          return info.isHardwareAccelerated();
        }
      }
    } catch (Exception e) {
      // 查不到就當作非硬體，不影響播放
    }
    return false;
  }

  @NonNull
  public static AnalyticsListener listener(@NonNull ExoPlayer owner) {
    return new AnalyticsListener() {
      // 只接受目前註冊的播放器事件，避免暖機／舊播放器污染統計
      private boolean isCurrent() {
        return playerRef.get() == owner;
      }

      @Override
      public void onVideoDecoderInitialized(
          @NonNull EventTime eventTime,
          @NonNull String name,
          long initializedTimestampMs,
          long initializationDurationMs) {
        if (!isCurrent()) return;
        boolean hw = queryHardware(name);
        synchronized (LOCK) {
          decoderName = name;
          isHardware = hw;
          decoderInitMs = initializationDurationMs;
          droppedTotal = 0;
          renderedTotal = 0;
          frameOffsetSumUs = 0;
          frameOffsetCount = 0;
          addEvent(
              "解碼器初始化 name=" + name + " hw=" + hw + " 耗時=" + initializationDurationMs + "ms");
        }
      }

      @Override
      public void onVideoInputFormatChanged(
          @NonNull EventTime eventTime,
          @NonNull Format format,
          @Nullable DecoderReuseEvaluation decoderReuseEvaluation) {
        if (!isCurrent()) return;
        synchronized (LOCK) {
          inputWidth = format.width;
          inputHeight = format.height;
          inputFps = format.frameRate;
          addEvent("影片格式改變 " + format.width + "x" + format.height + "@" + format.frameRate);
        }
      }

      @Override
      public void onDroppedVideoFrames(
          @NonNull EventTime eventTime, int droppedFrames, long elapsedMs) {
        if (!isCurrent()) return;
        synchronized (LOCK) {
          droppedTotal += droppedFrames;
        }
      }

      @Override
      public void onVideoFrameProcessingOffset(
          @NonNull EventTime eventTime, long totalProcessingOffsetUs, int frameCount) {
        if (!isCurrent()) return;
        synchronized (LOCK) {
          frameOffsetSumUs += totalProcessingOffsetUs;
          frameOffsetCount += frameCount;
        }
      }

      @Override
      public void onBandwidthEstimate(
          @NonNull EventTime eventTime,
          int totalLoadTimeMs,
          long totalBytesLoaded,
          long bitrateEstimate) {
        if (!isCurrent()) return;
        synchronized (LOCK) {
          bandwidthBps = bitrateEstimate;
        }
      }

      @Override
      public void onPlaybackStateChanged(@NonNull EventTime eventTime, int state) {
        if (!isCurrent()) return;
        synchronized (LOCK) {
          long now = SystemClock.elapsedRealtime();
          if (state == Player.STATE_BUFFERING) {
            if (bufferingStartMs < 0) {
              bufferingStartMs = now;
              bufferingCount++;
              addEvent("開始緩衝 累計=" + bufferingCount + "次");
            }
          } else if (bufferingStartMs >= 0) {
            long d = now - bufferingStartMs;
            bufferingStartMs = -1;
            bufferingTotalMs += d;
            addEvent("結束緩衝 持續=" + d + "ms 累計=" + bufferingCount + "次");
          }
        }
      }

      @Override
      public void onPlayerError(@NonNull EventTime eventTime, @NonNull PlaybackException error) {
        if (!isCurrent()) return;
        // 只記錯誤代碼名稱，訊息可能含網址
        synchronized (LOCK) {
          addEvent("播放錯誤 code=" + error.getErrorCodeName());
        }
      }

      @Override
      public void onVideoDisabled(@NonNull EventTime eventTime, @NonNull DecoderCounters counters) {
        if (!isCurrent()) return;
        synchronized (LOCK) {
          renderedTotal = counters.renderedOutputBufferCount;
        }
      }
    };
  }

  /** 由 MethodChannel（主執行緒）呼叫；區間欄位（影格延遲、事件）讀取後清空。 */
  @NonNull
  public static Map<String, Object> snapshot(boolean drain) {
    long rendered = -1;
    ExoPlayer p = playerRef.get();
    if (p != null) {
      try {
        DecoderCounters c = p.getVideoDecoderCounters();
        if (c != null) {
          c.ensureUpdated();
          rendered = c.renderedOutputBufferCount;
        }
      } catch (Exception e) {
        // 非播放執行緒或已釋放：改用 onVideoDisabled 記下的值
      }
    }
    Boolean tunneling = null;
    if (p != null) {
      try {
        tunneling = p.isTunnelingEnabled();
      } catch (Exception e) {
        // 取不到就回 null（未知）
      }
    }
    Map<String, Object> m = new HashMap<>();
    m.put("tunnelingActive", tunneling);
    synchronized (LOCK) {
      m.put("decoderName", decoderName);
      m.put("isHardware", isHardware);
      m.put("decoderInitMs", decoderInitMs);
      m.put("inputWidth", inputWidth);
      m.put("inputHeight", inputHeight);
      m.put("inputFps", (double) inputFps);
      m.put("droppedTotal", droppedTotal);
      m.put("renderedTotal", rendered >= 0 ? rendered : renderedTotal);
      m.put(
          "frameOffsetAvgUs",
          frameOffsetCount > 0 ? (double) frameOffsetSumUs / frameOffsetCount : 0.0);
      m.put("frameOffsetCount", frameOffsetCount);
      m.put("bandwidthBps", bandwidthBps);
      m.put("bufferingCount", bufferingCount);
      m.put("bufferingTotalMs", bufferingTotalMs);
      m.put("events", new ArrayList<String>(events));
      if (drain) {
        events.clear();
        frameOffsetSumUs = 0;
        frameOffsetCount = 0;
      }
    }
    return m;
  }
}
