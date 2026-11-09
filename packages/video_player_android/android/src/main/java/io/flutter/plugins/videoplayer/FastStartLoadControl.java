// PiliBTRTV 修改：起播只需緩衝約 0.5 秒（ExoPlayer 預設 2.5 秒），縮短按下影片到開始播放的時間。
package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.LoadControl;

@UnstableApi
public final class FastStartLoadControl {
  private FastStartLoadControl() {}

  @NonNull
  public static LoadControl create() {
    return new DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            DefaultLoadControl.DEFAULT_MIN_BUFFER_MS,
            DefaultLoadControl.DEFAULT_MAX_BUFFER_MS,
            500,
            2000)
        .build();
  }
}
