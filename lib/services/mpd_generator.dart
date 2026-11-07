import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'package:bili_tv_app/services/btr/btr_proxy.dart';

class MpdGenerator {
  /// 生成 DASH MPD 文件
  /// [dashData] 是 Bilibili API 返回的 dash 对象
  static Future<String> generate(Map<String, dynamic> dashData) async {
    final buffer = StringBuffer();

    // MPD 头部
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"');
    buffer.writeln(
      '     profiles="urn:mpeg:dash:profile:isoff-on-demand:2011"',
    );
    buffer.writeln(
      '     minBufferTime="PT${dashData['minBufferTime'] ?? 1.5}S"',
    );
    buffer.writeln('     type="static"');
    buffer.writeln(
      '     mediaPresentationDuration="PT${dashData['duration']}S">',
    );

    buffer.writeln('  <Period>');

    // 视频自适应集
    if (dashData['video'] != null) {
      buffer.writeln(
        '    <AdaptationSet mimeType="video/mp4" contentType="video" subsegmentAlignment="true" subsegmentStartsWithSAP="1">',
      );
      for (var video in dashData['video']) {
        await _writeRepresentation(buffer, video, true);
      }
      buffer.writeln('    </AdaptationSet>');
    }

    // 音频自适应集
    if (dashData['audio'] != null) {
      buffer.writeln(
        '    <AdaptationSet mimeType="audio/mp4" contentType="audio" subsegmentAlignment="true" subsegmentStartsWithSAP="1">',
      );
      for (var audio in dashData['audio']) {
        await _writeRepresentation(buffer, audio, false);
      }
      buffer.writeln('    </AdaptationSet>');
    }

    buffer.writeln('  </Period>');
    buffer.writeln('</MPD>');

    // 直接返回内容
    return buffer.toString();
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<void> _writeRepresentation(
    StringBuffer buffer,
    Map<String, dynamic> stream,
    bool isVideo,
  ) async {
    // 基础信息
    final id = stream['id'];
    final codecs = stream['codecs'] ?? (isVideo ? 'avc1.64001E' : 'mp4a.40.2');
    final bandwidth = stream['bandwidth'];
    final width = stream['width'];
    final height = stream['height'];
    final frameRate = stream['frameRate'];
    // 优先使用 baseUrl，备用使用 backupUrl
    final baseUrl = stream['baseUrl'] ?? stream['base_url'];

    buffer.write(
      '      <Representation id="$id" codecs="$codecs" bandwidth="$bandwidth"',
    );
    if (isVideo) {
      buffer.write(' width="$width" height="$height" frameRate="$frameRate"');
      // 基本播放不需要 Sar / ScanType
    }
    buffer.writeln('>');

    // BTR 多 CDN 加速：只寫入本機代理 URL 一個 BaseURL
    final baseUrlStr = baseUrl.toString();
    final backups = <String>[
      if (stream['backupUrl'] is List)
        for (final b in stream['backupUrl'])
          if (b is String && b.isNotEmpty) b,
    ];
    var proxied = false;
    if (BtrConfig.playback && BtrProxy.isEligible(baseUrlStr)) {
      final wrapped = await BtrProxy.wrap(baseUrlStr, backups: backups);
      if (wrapped != baseUrlStr) {
        buffer.writeln('        <BaseURL>${_xmlEscape(wrapped)}</BaseURL>');
        proxied = true;
      }
    }

    if (!proxied) {
      // 基础 URL（XML 转义）
      buffer.writeln('        <BaseURL>${_xmlEscape(baseUrlStr)}</BaseURL>');

      // 备用 URL (CDN 容灾)
      for (final backup in backups) {
        buffer.writeln('        <BaseURL>${_xmlEscape(backup)}</BaseURL>');
      }
    }

    // 初始化范围 (分片 MP4 必须)
    // Bilibili 通常通过 SegmentBase 提供 Initialization 和 indexRange

    if (stream['SegmentBase'] != null) {
      final seg = stream['SegmentBase'];
      final init = seg['Initialization'];
      final index = seg['indexRange'];
      buffer.writeln('        <SegmentBase indexRange="$index">');
      buffer.writeln('          <Initialization range="$init"/>');
      buffer.writeln('        </SegmentBase>');
    }

    buffer.writeln('      </Representation>');
  }
}
