import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:brotli/brotli.dart';
import 'dart:math'; // For random buvid
import 'api/live_api.dart';
import 'auth_service.dart'; // Import AuthService

/// 直播彈幕 Socket 服務
class LiveSocketService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;

  /// 最後一次收到伺服器封包的時間；心跳時超過 [_rxTimeout] 未收到視為斷線
  DateTime _lastRx = DateTime.now();
  static const Duration _rxTimeout = Duration(seconds: 70);
  final StreamController<Map<String, dynamic>> _msgController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _msgController.stream;

  void _log(String msg) {
    debugPrint(msg);
  }

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // 連線世代：每次 connect / disconnect 遞增，舊連線的回呼比對不符就忽略
  int _gen = 0;
  bool _connecting = false;
  int _connectGen = -1;
  bool _disposed = false;

  void _emit(Map<String, dynamic> msg) {
    if (_disposed || _msgController.isClosed) return;
    _msgController.add(msg);
  }

  /// 連線直播間。
  ///
  /// 事件：`error`（錯誤訊息）、`connected`（認證成功）、
  /// `disconnected`（意外斷線或連線失敗，呼叫端應退避重連；
  /// 主動 [disconnect] 不會發出此事件）。
  Future<void> connect(int roomId) async {
    if (_disposed) return;
    // 同一代連線進行中，不重複連線
    if (_connecting && _connectGen == _gen) return;
    disconnect(); // 先斷開舊連線（遞增世代）
    final gen = _gen;
    _connecting = true;
    _connectGen = gen;

    try {
      // 1. 獲取彈幕伺服器配置
      final conf = await LiveApi.getDanmakuConf(roomId);
      if (gen != _gen) return;
      if (conf == null) {
        _fail(gen, '獲取彈幕配置失敗');
        return;
      }

      final token = conf['token'];
      final hostList = conf['host_list'] as List;
      if (hostList.isEmpty) {
        _fail(gen, '彈幕伺服器清單為空');
        return;
      }

      // 優先使用 wss
      final hostInfo = hostList.firstWhere(
        (h) => h['wss_port'] != null,
        orElse: () => hostList.first,
      );
      final host = hostInfo['host'];
      final port = hostInfo['wss_port'] ?? hostInfo['port'];
      final wssUrl = 'wss://$host:$port/sub';

      _log('Connecting to Live WS: $wssUrl');

      // 2. 建立連線
      final WebSocket socket;
      try {
        socket = await WebSocket.connect(
          wssUrl,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Origin': 'https://live.bilibili.com',
            'Referer': 'https://live.bilibili.com/',
          },
        );
      } catch (e) {
        _log('WS Handshake Error: $e');
        _fail(gen, '握手失敗: $e');
        return;
      }
      if (gen != _gen) {
        // 連線期間已被主動斷開或被新連線取代
        try {
          socket.close(status.goingAway);
        } catch (_) {}
        return;
      }

      // 不設 pingInterval：B 站彈幕伺服器不回 WebSocket pong，dart:io 會在
      // 2 倍 pingInterval 後自行以 1001 關閉連線（原本 10 秒 → 每 20 秒斷線）。
      // 存活改由應用層心跳回覆（op 3）判斷，見 [_startHeartbeat]。
      _lastRx = DateTime.now();
      final channel = IOWebSocketChannel(socket);
      _channel = channel;
      _isConnected = true;
      _log('WS Connected & Channel Ready');

      // 3. 監聽訊息（先監聽，再發送）
      channel.stream.listen(
        (message) {
          if (gen != _gen) return;
          _lastRx = DateTime.now();
          try {
            _handleMessage(message);
          } catch (e) {
            _log('Message Handle Error: $e');
          }
        },
        onError: (error) {
          if (gen != _gen || !identical(_channel, channel)) return;
          _log('WS Error: $error');
          _handleUnexpectedClose('連線中斷: $error');
        },
        onDone: () {
          if (gen != _gen || !identical(_channel, channel)) return;
          _log(
            'WS Closed (Code: ${socket.closeCode}, Reason: ${socket.closeReason})',
          );
          _handleUnexpectedClose(null);
        },
      );

      // 4. 傳送進房認證包
      _sendAuth(roomId, token);

      // 5. 開啟心跳
      _startHeartbeat();
    } catch (e) {
      _log('Connect Error: $e');
      _fail(gen, '連線失敗: $e');
    } finally {
      if (_connectGen == gen) _connecting = false;
    }
  }

  /// 連線流程失敗：仍是當前世代才通知畫面（舊世代的失敗不影響新連線）
  void _fail(int gen, String msg) {
    if (gen != _gen) return;
    _isConnected = false;
    _emit({'type': 'error', 'msg': msg});
    _emit({'type': 'disconnected'});
  }

  /// 意外斷線（非 [disconnect] 觸發）：清理並通知畫面重連
  void _handleUnexpectedClose(String? errorMsg) {
    final channel = _channel;
    _channel = null;
    _heartbeatTimer?.cancel();
    _isConnected = false;
    try {
      channel?.sink.close(status.goingAway);
    } catch (_) {}
    if (errorMsg != null) _emit({'type': 'error', 'msg': errorMsg});
    _emit({'type': 'disconnected'});
  }

  /// 主動斷線：遞增世代，使舊連線的回呼全部失效，不發出 disconnected 事件
  void disconnect() {
    _gen++;
    final channel = _channel;
    _channel = null;
    try {
      channel?.sink.close(status.goingAway);
    } catch (_) {}
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isConnected = false;
  }

  void _sendAuth(int roomId, String token) {
    final uid = AuthService.isLoggedIn ? (AuthService.mid ?? 0) : 0;
    final buvid = _generateBuvid();

    _log(
      '🔐 Sending Auth (Room: $roomId, UID: $uid, Proto: 2, Buvid: $buvid)...',
    );
    if (token.isEmpty) _log('⚠️ Warning: Token is empty');

    final body = jsonEncode({
      'uid': uid,
      'roomid': roomId,
      'protover': 2,
      'buvid': buvid,
      'platform': 'web',
      'type': 2,
      'key': token,
    });

    _sendPacket(1, 7, utf8.encode(body));
  }

  String _generateBuvid() {
    final random = Random();
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      final digit = random.nextInt(16);
      buf.write(digit.toRadixString(16).toUpperCase());
    }
    buf.write('infoc');
    return buf.toString();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // 每 30 秒傳送一次心跳
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        // 70 秒沒有任何回應（含心跳回覆）：連線已失效，通知畫面重連
        if (DateTime.now().difference(_lastRx) > _rxTimeout) {
          _log('WS heartbeat timeout');
          _handleUnexpectedClose(null);
          return;
        }
        // Bilibili quirk: server expects "[object Object]" as heartbeat body
        // to return correct popularity. Empty body returns 1.
        _sendPacket(
          1,
          2,
          utf8.encode('[object Object]'),
        ); // Opcode 2 = Heartbeat
        // debugPrint('💓 Heartbeat sent');
      }
    });
  }

  /// 封包併發送
  /// Total Len (4) | Header Len (2) | Proto Ver (2) | Opcode (4) | Seq (4) | Body
  void _sendPacket(int ver, int op, List<int> body) {
    final headerLen = 16;
    final totalLen = headerLen + body.length;
    final buffer = ByteData(totalLen);

    buffer.setUint32(0, totalLen);
    buffer.setUint16(4, headerLen);
    buffer.setUint16(6, ver);
    buffer.setUint32(8, op);
    buffer.setUint32(12, 1); // Seq, always 1

    for (var i = 0; i < body.length; i++) {
      buffer.setUint8(16 + i, body[i]);
    }

    _channel?.sink.add(buffer.buffer.asUint8List());
  }

  /// 處理接收到的二進位制資料
  void _handleMessage(dynamic message) {
    if (message is! List<int>) return;

    final data = Uint8List.fromList(message);
    var offset = 0;

    while (offset < data.length) {
      if (data.length - offset < 16) break;

      final view = ByteData.sublistView(data, offset);
      final totalLen = view.getUint32(0);
      final ver = view.getUint16(6);
      final op = view.getUint32(8);

      if (totalLen < 16) break; // Invalid packet

      // Ensure we have the full packet
      if (data.length - offset < totalLen) break;

      final body = data.sublist(offset + 16, offset + totalLen);

      debugPrint('RX: Op=$op Ver=$ver Len=$totalLen'); // Verbose debug

      if (op == 5) {
        // Notification
        if (ver == 0) {
          // JSON Plain Text
          try {
            final jsonStr = utf8.decode(body);
            // debugPrint('JSON: $jsonStr');
            _parseCommand(jsonDecode(jsonStr));
          } catch (e) {
            debugPrint('JSON decode error: $e');
          }
        } else if (ver == 2) {
          // Zlib Compressed
          try {
            final decompressed = zlib.decode(body);
            // debugPrint('Zlib Decompressed: ${decompressed.length}');
            _handleMessage(decompressed); // Recursive parse
          } catch (e) {
            debugPrint('Zlib decode error: $e');
          }
        } else if (ver == 3) {
          // Brotli Compressed
          try {
            final decompressed = brotli.decode(body);
            debugPrint('Brotli Decompressed: ${decompressed.length}');
            _handleMessage(decompressed); // Recursive parse
          } catch (e) {
            debugPrint('Brotli decode error: $e');
          }
        }
      } else if (op == 3) {
        // Heartbeat Reply
        final viewers = ByteData.sublistView(body).getUint32(0);
        // debugPrint('Heartbeat Reply: $viewers');
        _emit({'type': 'popularity', 'count': viewers});
      } else if (op == 8) {
        // Auth Reply
        _log('Live WS Auth Success');
        // 認證成功後立即送一次心跳（同網頁版），之後每 30 秒一次
        _sendPacket(1, 2, utf8.encode('[object Object]'));
        _emit({'type': 'connected'});
      }

      offset += totalLen;
    }
  }

  void _parseCommand(Map<String, dynamic> json) {
    if (!json.containsKey('cmd')) return;
    final cmd = json['cmd'] as String;
    // _log('CMD: $cmd'); // Enable debug to see traffic

    try {
      if (cmd == 'DANMU_MSG') {
        final info = json['info'] as List;
        final content = info[1] as String;
        final user = info[2] as List;
        final userName = user[1] as String;

        _log('💬 Danmaku: $content');

        // Parse color
        int color = 16777215; // White
        try {
          if (info.isNotEmpty && info[0] is List && info[0].length > 3) {
            color = info[0][3];
          }
        } catch (e) {
          // ignore
        }

        _emit({
          'type': 'danmaku',
          'content': content,
          'user': userName,
          'color': color,
        });
      } else if (cmd == 'SEND_GIFT') {
        // Gift
      } else if (cmd == 'INTERACT_WORD') {
        // Entry / Follow
      }
    } catch (e) {
      _log('Error Parse CMD: $cmd\nData: $json\nError: $e');
    }
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _msgController.close();
  }
}
