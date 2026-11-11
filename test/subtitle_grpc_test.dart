import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:bili_tv_app/grpc/dm_grpc.dart';
import 'package:bili_tv_app/grpc/dm_view.pb.dart';
import 'package:bili_tv_app/services/api/subtitle_api.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gRPC frame', () {
    test('短資料不壓縮，往返一致', () {
      final proto = Uint8List.fromList([1, 2, 3]);
      final frame = DmGrpc.encodeFrame(proto);
      expect(frame.length, 8);
      expect(frame[0], 0);
      expect(frame.sublist(1, 5), [0, 0, 0, 3]);
      expect(DmGrpc.decodeFrame(frame), proto);
    });

    test('長資料 gzip，往返一致', () {
      final proto = Uint8List.fromList(List.filled(500, 7));
      final frame = DmGrpc.encodeFrame(proto);
      expect(frame[0], 1);
      expect(frame.length, lessThan(500));
      expect(DmGrpc.decodeFrame(frame), proto);
    });

    test('解碼 gzip frame（伺服器端格式）', () {
      final body = Uint8List.fromList(gzip.encode(List.filled(100, 9)));
      final frame = Uint8List(5 + body.length)
        ..[0] = 1
        ..buffer.asByteData(1, 4).setInt32(0, body.length, Endian.big)
        ..setAll(5, body);
      expect(DmGrpc.decodeFrame(frame), List.filled(100, 9));
    });

    test('格式錯誤丟 FormatException', () {
      expect(
        () => DmGrpc.decodeFrame(Uint8List.fromList([0, 0])),
        throwsFormatException,
      );
      expect(
        () => DmGrpc.decodeFrame(Uint8List.fromList([0, 0, 0, 0, 9, 1])),
        throwsFormatException,
      );
    });

    test('DmViewReq 欄位編碼：pid=1、oid=2、type=3', () {
      final bytes = DmViewReq(
        pid: Int64(5),
        oid: Int64(6),
        type: 1,
      ).writeToBuffer();
      expect(bytes, [0x08, 5, 0x10, 6, 0x18, 1]);
    });
  });

  group('DmView 解析', () {
    // 手工組 DmViewReply bytes：subtitle(3){ subtitles(3)[ item ] }
    Uint8List item(int id, String lan, String doc, String url, int type) {
      final b = BytesBuilder()
        ..add([0x08, id])
        ..add([0x1a, lan.length, ...lan.codeUnits])
        ..add([0x22, doc.length, ...doc.codeUnits])
        ..add([0x2a, url.length, ...url.codeUnits]);
      if (type != 0) b.add([0x38, type]);
      return b.toBytes();
    }

    Uint8List reply(List<Uint8List> items) {
      final sub = BytesBuilder();
      for (final i in items) {
        sub.add([0x1a, i.length, ...i]);
      }
      final s = sub.toBytes();
      return Uint8List.fromList([0x1a, s.length, ...s]);
    }

    test('轉成 SubtitleTrack：補 https:、type→isAi', () {
      final bytes = reply([
        item(1, 'zh-CN', '中文', '//i0.hdslb.com/a.json', 0),
        item(2, 'ai-zh', '中文（自动生成）', 'http://i0.hdslb.com/b.json', 1),
        item(3, 'en', 'English', '', 0),
      ]);
      final tracks = SubtitleApi.parseDmView(DmViewReply.fromBuffer(bytes));
      expect(tracks.length, 2);
      expect(tracks[0].lan, 'zh-CN');
      expect(tracks[0].url, 'https://i0.hdslb.com/a.json');
      expect(tracks[0].isAi, isFalse);
      expect(tracks[1].url, 'https://i0.hdslb.com/b.json');
      expect(tracks[1].isAi, isTrue);
    });

    test('無 subtitle 回空清單', () {
      expect(SubtitleApi.parseDmView(DmViewReply.fromBuffer([])), isEmpty);
    });
  });
}
