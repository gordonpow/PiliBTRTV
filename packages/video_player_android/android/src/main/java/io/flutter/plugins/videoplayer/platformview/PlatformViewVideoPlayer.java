// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.platformview;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.MediaItem;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.ExoPlayerEventListener;
import io.flutter.plugins.videoplayer.VideoAsset;
import io.flutter.plugins.videoplayer.VideoPlayer;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;
import io.flutter.plugins.videoplayer.VideoPlayerOptions;
import io.flutter.view.TextureRegistry.SurfaceProducer;

/**
 * A subclass of {@link VideoPlayer} that adds functionality related to platform view as a way of
 * displaying the video in the app.
 */
public class PlatformViewVideoPlayer extends VideoPlayer {
  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @VisibleForTesting
  public PlatformViewVideoPlayer(
      @NonNull VideoPlayerCallbacks events,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    super(events, mediaItem, options, /* surfaceProducer */ null, exoPlayerProvider);
  }

  /**
   * Creates a platform view video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @NonNull
  public static PlatformViewVideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options) {
    return new PlatformViewVideoPlayer(
        events,
        asset.getMediaItem(),
        options,
        () -> {
          androidx.media3.exoplayer.trackselection.DefaultTrackSelector trackSelector =
              new androidx.media3.exoplayer.trackselection.DefaultTrackSelector(context);
          // 隧道播放（實驗）：讀 Flutter shared_preferences 的 flutter.player_tunneling
          // （檔名 FlutterSharedPreferences，key 前綴 flutter.）。只有此 SurfaceView 路徑會啟用。
          try {
            boolean tunneling =
                context
                    .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getBoolean("flutter.player_tunneling", false);
            if (tunneling) {
              trackSelector.setParameters(
                  trackSelector.buildUponParameters().setTunnelingEnabled(true));
            }
          } catch (Exception e) {
            // 讀不到設定就維持一般模式
          }
          ExoPlayer.Builder builder =
              new ExoPlayer.Builder(context)
                  .setTrackSelector(trackSelector)
                  .setLoadControl(io.flutter.plugins.videoplayer.FastStartLoadControl.create())
                  .setMediaSourceFactory(asset.getMediaSourceFactory(context));
          ExoPlayer exoPlayer = builder.build();
          io.flutter.plugins.videoplayer.PlayerStats.attach(exoPlayer);
          exoPlayer.addAnalyticsListener(
              io.flutter.plugins.videoplayer.PlayerStats.listener(exoPlayer));
          return exoPlayer;
        });
  }

  @NonNull
  @Override
  protected ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer) {
    return new PlatformViewExoPlayerEventListener(exoPlayer, videoPlayerEvents);
  }
}
