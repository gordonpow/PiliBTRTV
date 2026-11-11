@Tags(['network'])
library;

import 'dart:io' show Platform;

import 'package:bili_tv_app/services/api/subtitle_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真實網路測試：預設略過。
/// 執行：BILI_NET_AID=... BILI_NET_CID=... flutter test test/subtitle_grpc_network_test.dart
void main() {
  final aid = int.tryParse(Platform.environment['BILI_NET_AID'] ?? '');
  final cid = int.tryParse(Platform.environment['BILI_NET_CID'] ?? '');
  test(
    '未登入 gRPC DmView 取得 subtitle_url',
    () async {
      final tracks = await SubtitleApi.getSubtitlesGrpc(aid: aid!, cid: cid!);
      // ignore: avoid_print
      print(tracks.map((t) => '${t.lan} ${t.lanDoc} ${t.url}').join('\n'));
      expect(tracks, isNotEmpty);
      expect(tracks.first.url, startsWith('https://'));
    },
    skip: (aid == null || cid == null)
        ? '需設定 BILI_NET_AID／BILI_NET_CID'
        : false,
  );
}
