import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:http/http.dart' as http;

import 'dm_view.pb.dart';

/// gRPC（HTTP/1.1 上的 application/grpc）的 frame 編解碼與 DmView 請求。
/// 比照 PiliPlus 的 GrpcReq：5 位元組前綴（壓縮旗標＋大端長度）＋ protobuf。
abstract final class DmGrpc {
  static const _url =
      'https://app.bilibili.com/bilibili.community.service.dm.v1.DM/DmView';
  static const _gzipMinLength = 64;
  static const _build = 2001100;
  static const _mobiApp = 'android_hd';
  static const _userAgent =
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android '
      'model/android_hd mobi_app/android_hd build/2001100 channel/master '
      'innerVer/2001100 osVer/15 network/2';

  /// 編碼 gRPC frame；長度超過 64 位元組時 gzip。
  static Uint8List encodeFrame(Uint8List proto) {
    final compress = proto.length > _gzipMinLength;
    if (compress) proto = Uint8List.fromList(gzip.encode(proto));
    return Uint8List(5 + proto.length)
      ..[0] = compress ? 1 : 0
      ..buffer.asByteData(1, 4).setInt32(0, proto.length, Endian.big)
      ..setAll(5, proto);
  }

  /// 解碼 gRPC frame 回 protobuf bytes；格式不符丟 FormatException。
  static Uint8List decodeFrame(Uint8List data) {
    if (data.length < 5) throw const FormatException('grpc frame too short');
    final length = ByteData.sublistView(data, 1, 5).getInt32(0, Endian.big);
    if (length < 0 || data.length < 5 + length) {
      throw const FormatException('grpc frame length mismatch');
    }
    final body = Uint8List.sublistView(data, 5, 5 + length);
    return data[0] == 1 ? Uint8List.fromList(gzip.decode(body)) : body;
  }

  static void _varint(BytesBuilder b, int v) {
    while (v > 0x7f) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  static void _str(BytesBuilder b, int field, String s) {
    if (s.isEmpty) return;
    final bytes = utf8.encode(s);
    _varint(b, (field << 3) | 2);
    _varint(b, bytes.length);
    b.add(bytes);
  }

  static void _int(BytesBuilder b, int field, int v) {
    _varint(b, field << 3);
    _varint(b, v);
  }

  /// 手工編 bilibili.metadata.Metadata（未登入：無 access_key）。
  static String metadataBin(String buvid) {
    final b = BytesBuilder();
    _str(b, 2, _mobiApp);
    _str(b, 3, 'android');
    _int(b, 4, _build);
    _str(b, 5, 'master');
    _str(b, 6, buvid);
    _str(b, 7, 'android');
    return base64Encode(b.toBytes());
  }

  static String _deviceBin(String buvid) {
    final b = BytesBuilder();
    _int(b, 1, 5);
    _int(b, 2, _build);
    _str(b, 3, buvid);
    _str(b, 4, _mobiApp);
    _str(b, 5, 'android');
    _str(b, 7, 'master');
    _str(b, 8, 'android');
    _str(b, 9, 'android');
    _str(b, 10, '15');
    _str(b, 13, '2.0.1');
    return base64Encode(b.toBytes());
  }

  static String _fawkesBin() {
    final b = BytesBuilder();
    _str(b, 1, _mobiApp);
    _str(b, 2, 'prod');
    _str(b, 3, 'btrtv0001');
    return base64Encode(b.toBytes());
  }

  static String _networkBin() {
    final b = BytesBuilder();
    _int(b, 1, 1); // WIFI
    return base64Encode(b.toBytes());
  }

  static String _localeBin() {
    final ids = BytesBuilder();
    _str(ids, 1, 'zh');
    _str(ids, 2, 'Hans');
    _str(ids, 3, 'CN');
    final idBytes = ids.toBytes();
    final b = BytesBuilder();
    for (final f in const [1, 2]) {
      _varint(b, (f << 3) | 2);
      _varint(b, idBytes.length);
      b.add(idBytes);
    }
    _str(b, 4, 'Asia/Shanghai');
    return base64Encode(b.toBytes());
  }

  static Map<String, String> headers(String buvid) => {
    'content-type': 'application/grpc',
    'grpc-encoding': 'gzip',
    'gzip-accept-encoding': 'gzip,identity',
    'user-agent': _userAgent,
    'x-bili-gaia-vtoken': '',
    'x-bili-aurora-zone': '',
    'x-bili-trace-id': '11111111111111111111111111111111:1111111111111111:0:0',
    'bili-http-engine': 'cronet',
    'x-bili-network-bin': _networkBin(),
    'x-bili-locale-bin': _localeBin(),
    'x-bili-exps-bin': '',
    'buvid': buvid,
    'x-bili-fawkes-req-bin': _fawkesBin(),
    'x-bili-device-bin': _deviceBin(buvid),
    'x-bili-metadata-bin': metadataBin(buvid),
  };

  /// 取得 DmView 回應；失敗（HTTP／grpc-status 非 0／逾時）丟例外。
  static Future<DmViewReply> dmView({
    required int aid,
    required int cid,
    required String buvid,
    http.Client? client,
  }) async {
    final req = DmViewReq(pid: Int64(aid), oid: Int64(cid), type: 1);
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            Uri.parse(_url),
            headers: headers(buvid),
            body: encodeFrame(req.writeToBuffer()),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('grpc http ${res.statusCode}');
      }
      final status = res.headers['grpc-status'];
      if (status != null && status != '0') {
        throw Exception('grpc-status $status ${res.headers['grpc-message']}');
      }
      return DmViewReply.fromBuffer(decodeFrame(res.bodyBytes));
    } finally {
      if (client == null) c.close();
    }
  }
}
