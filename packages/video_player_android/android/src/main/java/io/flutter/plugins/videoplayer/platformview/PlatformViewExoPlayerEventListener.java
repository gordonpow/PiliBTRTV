// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.platformview;

import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.Format;
import androidx.media3.common.VideoSize;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.ExoPlayerEventListener;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;

public final class PlatformViewExoPlayerEventListener extends ExoPlayerEventListener {
  public PlatformViewExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @NonNull VideoPlayerCallbacks events) {
    super(exoPlayer, events);
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  protected void sendInitialized() {
    // We can't rely on VideoSize here, because at this point it is not available - the platform
    // view was not created yet. We use the video format instead.
    Format videoFormat = exoPlayer.getVideoFormat();
    if (videoFormat == null) {
      // 裝置無法解碼影片軌時，ExoPlayer 會只播聲音並進入 READY，此時沒有影片格式。
      // 原本 requireNonNull 會讓 App 閃退；改用 VideoSize（通常為 0x0）回報初始化。
      VideoSize videoSize = exoPlayer.getVideoSize();
      events.onInitialized(
          videoSize.width, videoSize.height, exoPlayer.getDuration(), /* rotationCorrection= */ 0);
      return;
    }
    RotationDegrees rotationCorrection;
    try {
      rotationCorrection = RotationDegrees.fromDegrees(videoFormat.rotationDegrees);
    } catch (IllegalArgumentException e) {
      // 旋轉角度不是 0、90、180、270 時不做修正（與 texture 模式相同）
      rotationCorrection = RotationDegrees.ROTATE_0;
    }
    int width = videoFormat.width;
    int height = videoFormat.height;

    // Switch the width/height if video was taken in portrait mode and a rotation
    // correction was detected.
    if (rotationCorrection == RotationDegrees.ROTATE_90
        || rotationCorrection == RotationDegrees.ROTATE_270) {
      width = videoFormat.height;
      height = videoFormat.width;

      rotationCorrection = RotationDegrees.fromDegrees(0);
    }

    events.onInitialized(width, height, exoPlayer.getDuration(), rotationCorrection.getDegrees());
  }
}
