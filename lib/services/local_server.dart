import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../plugins/ad_filter_plugin.dart';
import '../plugins/danmaku_enhance_plugin.dart';
import '../core/plugin/plugin_manager.dart';

/// 全域性 HTTP 服務
///
/// 提供:
/// 1. MPD 檔案代理 (播放器使用)
/// 2. 外掛配置 REST API
/// 3. Web 管理介面
class LocalServer {
  static final LocalServer _instance = LocalServer._internal();
  static LocalServer get instance => _instance;

  LocalServer._internal();

  HttpServer? _server;
  String? _currentMpdContent;
  String? _localIp;

  static const int port = 3322;

  /// 服務是否正在執行
  bool get isRunning => _server != null;

  /// 獲取服務地址 (用於顯示)
  String? get address => _localIp != null ? 'http://$_localIp:$port' : null;

  /// 獲取 MPD 播放地址
  String get mpdUrl => 'http://127.0.0.1:$port/video.mpd';

  /// 啟動服務
  Future<void> start() async {
    if (_server != null) return;

    try {
      // 獲取本地 IP（使用 NetworkInterface）
      _localIp = await _getLocalIp();

      // 繫結到所有網路介面
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleRequest);

      debugPrint('🌐 LocalServer started at http://$_localIp:$port');
    } catch (e) {
      debugPrint('❌ LocalServer failed to start: $e');
    }
  }

  /// 獲取本地 WiFi/乙太網路 IP 地址
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        // 優先選擇 WiFi 或乙太網路介面
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('eth') ||
            name.contains('en0')) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback) {
              return addr.address;
            }
          }
        }
      }
      // 回退：返回第一個非迴環地址
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }

  /// 停止服務
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _currentMpdContent = null;
    debugPrint('🔴 LocalServer stopped');
  }

  /// 設定當前 MPD 內容
  void setMpdContent(String content) {
    _currentMpdContent = content;
  }

  /// 清除 MPD 內容
  void clearMpdContent() {
    _currentMpdContent = null;
  }

  /// 處理 HTTP 請求
  Future<void> _handleRequest(HttpRequest request) async {
    // CORS 頭
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, DELETE, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    // 預檢請求
    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      // MPD 檔案
      if (path.endsWith('.mpd')) {
        await _serveMpd(request);
      }
      // API 路由
      else if (path.startsWith('/api/')) {
        await _handleApi(request);
      }
      // Web 管理介面
      else if (path == '/' || path == '/index.html') {
        await _serveWebUI(request);
      }
      // 404
      else {
        request.response.statusCode = 404;
        request.response.write('Not Found');
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error: $e');
    }

    await request.response.close();
  }

  /// 提供 MPD 檔案
  Future<void> _serveMpd(HttpRequest request) async {
    if (_currentMpdContent == null) {
      request.response.statusCode = 404;
      request.response.write('No MPD content available');
      return;
    }

    request.response.headers.contentType = ContentType(
      'application',
      'dash+xml',
    );
    request.response.write(_currentMpdContent);
  }

  /// 處理 API 請求
  Future<void> _handleApi(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // 去廣告外掛 API
    if (path.startsWith('/api/ad-filter/')) {
      await _handleAdFilterApi(request, path, method);
    }
    // 彈幕增強外掛 API
    else if (path.startsWith('/api/danmaku/')) {
      await _handleDanmakuApi(request, path, method);
    } else {
      request.response.statusCode = 404;
      request.response.write('API not found');
    }
  }

  /// 去廣告外掛 API
  Future<void> _handleAdFilterApi(
    HttpRequest request,
    String path,
    String method,
  ) async {
    final plugin = PluginManager().getPlugin<AdFilterPlugin>('ad_filter');
    if (plugin == null) {
      _jsonResponse(request, {'error': 'Plugin not found'}, 404);
      return;
    }

    // /api/ad-filter/config - 獲取/更新配置
    if (path == '/api/ad-filter/config') {
      if (method == 'GET') {
        final config = plugin.getConfig();
        _jsonResponse(request, {
          'filterSponsored': config.filterSponsored,
          'filterClickbait': config.filterClickbait,
          'filterLowQuality': config.filterLowQuality,
          'minViewCount': config.minViewCount,
        });
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        if (body != null) {
          if (body.containsKey('filterSponsored')) {
            plugin.setFilterSponsored(body['filterSponsored'] as bool);
          }
          if (body.containsKey('filterClickbait')) {
            plugin.setFilterClickbait(body['filterClickbait'] as bool);
          }
          if (body.containsKey('filterLowQuality')) {
            plugin.setFilterLowQuality(body['filterLowQuality'] as bool);
          }
          if (body.containsKey('minViewCount')) {
            plugin.setMinViewCount(body['minViewCount'] as int);
          }
          _jsonResponse(request, {'success': true});
        } else {
          _jsonResponse(request, {'error': 'Invalid body'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/keywords
    else if (path == '/api/ad-filter/keywords') {
      if (method == 'GET') {
        _jsonResponse(request, {'keywords': plugin.getKeywords()});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final keyword = body?['keyword'] as String?;
        if (keyword != null && keyword.isNotEmpty) {
          plugin.addKeyword(keyword);
          _jsonResponse(request, {'success': true, 'keyword': keyword});
        } else {
          _jsonResponse(request, {'error': 'Missing keyword'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/keywords/{keyword}
    else if (path.startsWith('/api/ad-filter/keywords/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/ad-filter/keywords/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/upnames - UP主名稱黑名單
    else if (path == '/api/ad-filter/upnames') {
      if (method == 'GET') {
        _jsonResponse(request, {'upnames': plugin.getBlockedUpNames()});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final name = body?['name'] as String?;
        if (name != null && name.isNotEmpty) {
          plugin.addBlockedUpName(name);
          _jsonResponse(request, {'success': true, 'name': name});
        } else {
          _jsonResponse(request, {'error': 'Missing name'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/upnames/{name}
    else if (path.startsWith('/api/ad-filter/upnames/')) {
      final name = Uri.decodeComponent(
        path.substring('/api/ad-filter/upnames/'.length),
      );
      if (method == 'DELETE') {
        plugin.unblockUploaderByName(name);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/blocked - UP主 MID 黑名單
    else if (path == '/api/ad-filter/blocked') {
      if (method == 'GET') {
        _jsonResponse(request, {'blocked': plugin.getBlockedMids()});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/blocked/{mid}
    else if (path.startsWith('/api/ad-filter/blocked/')) {
      final midStr = path.substring('/api/ad-filter/blocked/'.length);
      final mid = int.tryParse(midStr);
      if (method == 'DELETE' && mid != null) {
        plugin.unblockUploader(mid);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Invalid request'}, 400);
      }
    } else {
      _jsonResponse(request, {'error': 'Not found'}, 404);
    }
  }

  /// 彈幕增強外掛 API
  Future<void> _handleDanmakuApi(
    HttpRequest request,
    String path,
    String method,
  ) async {
    final plugin = PluginManager().getPlugin<DanmakuEnhancePlugin>(
      'danmaku_enhance',
    );
    if (plugin == null) {
      _jsonResponse(request, {'error': 'Plugin not found'}, 404);
      return;
    }

    // /api/danmaku/config - 獲取/更新配置
    if (path == '/api/danmaku/config') {
      if (method == 'GET') {
        final config = plugin.getConfig();
        _jsonResponse(request, {'enableFilter': config.enableFilter});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        if (body != null) {
          if (body.containsKey('enableFilter')) {
            plugin.setEnableFilter(body['enableFilter'] as bool);
          }
          _jsonResponse(request, {'success': true});
        } else {
          _jsonResponse(request, {'error': 'Invalid body'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/partial (部分匹配)
    else if (path == '/api/danmaku/block/partial' ||
        path == '/api/danmaku/block') {
      if (method == 'GET') {
        _jsonResponse(request, {'keywords': plugin.getConfig().blockKeywords});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final keyword = body?['keyword'] as String?;
        if (keyword != null && keyword.isNotEmpty) {
          plugin.addBlockKeyword(keyword);
          _jsonResponse(request, {'success': true, 'keyword': keyword});
        } else {
          _jsonResponse(request, {'error': 'Missing keyword'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/partial/{keyword}
    else if (path.startsWith('/api/danmaku/block/partial/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/partial/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeBlockKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // 相容舊 API: /api/danmaku/block/{keyword}
    else if (path.startsWith('/api/danmaku/block/') &&
        !path.contains('/full')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeBlockKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/full (全詞匹配)
    else if (path == '/api/danmaku/block/full') {
      if (method == 'GET') {
        _jsonResponse(request, {'keywords': plugin.getFullKeywords()});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final keyword = body?['keyword'] as String?;
        if (keyword != null && keyword.isNotEmpty) {
          plugin.addFullKeyword(keyword);
          _jsonResponse(request, {'success': true, 'keyword': keyword});
        } else {
          _jsonResponse(request, {'error': 'Missing keyword'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/full/{keyword}
    else if (path.startsWith('/api/danmaku/block/full/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/full/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeFullKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/{keyword}
    else if (path.startsWith('/api/danmaku/block/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeBlockKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    } else {
      _jsonResponse(request, {'error': 'Not found'}, 404);
    }
  }

  /// 讀取 JSON 請求體
  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 傳送 JSON 響應
  void _jsonResponse(
    HttpRequest request,
    Map<String, dynamic> data, [
    int statusCode = 200,
  ]) {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
  }

  /// 提供 Web 管理介面
  Future<void> _serveWebUI(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_webUIHtml);
  }

  /// Web 管理介面 HTML
  static const String _webUIHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BiliTV 外掛管理</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #fff; 
      min-height: 100vh;
      padding: 20px;
    }
    .container { max-width: 800px; margin: 0 auto; }
    h1 { 
      text-align: center; 
      margin-bottom: 30px;
      color: #fb7299;
      font-size: 28px;
    }
    .card {
      background: rgba(255,255,255,0.05);
      border-radius: 16px;
      padding: 24px;
      margin-bottom: 20px;
      backdrop-filter: blur(10px);
      border: 1px solid rgba(255,255,255,0.1);
    }
    .card h2 {
      color: #fb7299;
      margin-bottom: 16px;
      font-size: 20px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card h3 {
      color: #fff;
      margin: 16px 0 8px;
      font-size: 16px;
    }
    .input-row {
      display: flex;
      gap: 10px;
      margin-bottom: 16px;
    }
    input[type="text"] {
      flex: 1;
      padding: 12px 16px;
      border: 1px solid rgba(255,255,255,0.2);
      border-radius: 8px;
      background: rgba(255,255,255,0.1);
      color: #fff;
      font-size: 16px;
      outline: none;
      transition: border-color 0.2s;
    }
    input[type="text"]:focus {
      border-color: #fb7299;
    }
    input[type="text"]::placeholder {
      color: rgba(255,255,255,0.4);
    }
    button {
      padding: 12px 24px;
      border: none;
      border-radius: 8px;
      background: #fb7299;
      color: #fff;
      font-size: 16px;
      cursor: pointer;
      transition: transform 0.1s, background 0.2s;
    }
    button:hover { background: #e5638a; }
    button:active { transform: scale(0.98); }
    .tags {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      min-height: 32px;
    }
    .tag {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 8px 12px;
      background: rgba(251,114,153,0.2);
      border-radius: 20px;
      font-size: 14px;
    }
    .tag.highlight {
      background: rgba(255,215,0,0.2);
    }
    .tag.blocked {
      background: rgba(255,0,0,0.2);
    }
    .tag .delete {
      cursor: pointer;
      opacity: 0.6;
      font-size: 16px;
    }
    .tag .delete:hover { opacity: 1; }
    .empty {
      color: rgba(255,255,255,0.4);
      font-style: italic;
    }
    .switch-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 0;
      border-bottom: 1px solid rgba(255,255,255,0.1);
    }
    .switch-row:last-child { border-bottom: none; }
    .switch-label {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .switch-label span:first-child {
      font-size: 16px;
    }
    .switch-label span:last-child {
      font-size: 12px;
      color: rgba(255,255,255,0.5);
    }
    .switch {
      position: relative;
      width: 50px;
      height: 28px;
      background: rgba(255,255,255,0.2);
      border-radius: 14px;
      cursor: pointer;
      transition: background 0.2s;
    }
    .switch.on {
      background: #fb7299;
    }
    .switch::after {
      content: '';
      position: absolute;
      top: 2px;
      left: 2px;
      width: 24px;
      height: 24px;
      background: #fff;
      border-radius: 50%;
      transition: left 0.2s;
    }
    .switch.on::after {
      left: 24px;
    }
    .tabs {
      display: flex;
      margin-bottom: 16px;
      gap: 8px;
    }
    .tab {
      padding: 8px 16px;
      background: rgba(255,255,255,0.1);
      border-radius: 8px;
      cursor: pointer;
      transition: background 0.2s;
    }
    .tab.active {
      background: #fb7299;
    }
    .tab:hover:not(.active) {
      background: rgba(255,255,255,0.2);
    }
    .section { display: none; }
    .section.active { display: block; }
    .divider {
      height: 1px;
      background: rgba(255,255,255,0.1);
      margin: 16px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>📺 BiliTV 外掛管理</h1>
    
    <!-- 去廣告外掛 -->
    <div class="card">
      <h2>🚫 去廣告增強</h2>
      
      <!-- 過濾開關 -->
      <div class="switch-row">
        <div class="switch-label">
          <span>過濾廣告推廣</span>
          <span>隱藏商業合作、恰飯、推廣等內容</span>
        </div>
        <div class="switch" id="filterSponsored" onclick="toggleAdConfig('filterSponsored')"></div>
      </div>
      <div class="switch-row">
        <div class="switch-label">
          <span>過濾標題黨</span>
          <span>隱藏震驚體、誇張標題影片</span>
        </div>
        <div class="switch" id="filterClickbait" onclick="toggleAdConfig('filterClickbait')"></div>
      </div>
      <div class="switch-row">
        <div class="switch-label">
          <span>過濾低播放量</span>
          <span>隱藏播放量低於1000的影片</span>
        </div>
        <div class="switch" id="filterLowQuality" onclick="toggleAdConfig('filterLowQuality')"></div>
      </div>
      
      <div class="divider"></div>
      
      <!-- UP主拉黑 -->
      <h3>👤 UP主拉黑</h3>
      <div class="input-row">
        <input type="text" id="upNameInput" placeholder="輸入UP主名稱">
        <button onclick="addUpName()">新增</button>
      </div>
      <div class="tags" id="upNames"></div>
      
      <div class="divider"></div>
      
      <!-- 自定義關鍵詞 -->
      <h3>🔤 自定義遮蔽關鍵詞</h3>
      <p style="font-size:12px;color:rgba(255,255,255,0.5);margin-bottom:12px;">標題中包含這些關鍵詞的影片將被遮蔽</p>
      <div class="input-row">
        <input type="text" id="adKeywordInput" placeholder="輸入要遮蔽的標題關鍵詞">
        <button onclick="addAdKeyword()">新增</button>
      </div>
      <div class="tags" id="adKeywords"></div>
    </div>

    <!-- 彈幕遮蔽外掛 -->
    <div class="card">
      <h2>💬 彈幕遮蔽</h2>
      
      <!-- 開關 -->
      <div class="switch-row">
        <div class="switch-label">
          <span>啟用彈幕遮蔽</span>
          <span>遮蔽包含指定關鍵詞的彈幕</span>
        </div>
        <div class="switch" id="enableFilter" onclick="toggleDanmakuConfig('enableFilter')"></div>
      </div>
      
      <div class="divider"></div>
      
      <!-- 部分匹配關鍵詞 -->
      <h3>📝 部分匹配關鍵詞</h3>
      <p style="font-size:12px;color:rgba(255,255,255,0.5);margin-bottom:12px;">包含即遮蔽（如 "第一" 會遮蔽 "我是第一名"）</p>
      <div class="input-row">
        <input type="text" id="partialKeywordInput" placeholder="輸入部分匹配關鍵詞">
        <button onclick="addDanmakuKeyword('partial')">新增</button>
      </div>
      <div class="tags" id="partialKeywords"></div>

      <div class="divider" style="margin: 20px 0;"></div>

      <!-- 全詞匹配關鍵詞 -->
      <h3>🔤 全詞匹配關鍵詞</h3>
      <p style="font-size:12px;color:rgba(255,255,255,0.5);margin-bottom:12px;">必須完全一致才遮蔽（如 "第一" 只遮蔽 "第一"）</p>
      <div class="input-row">
        <input type="text" id="fullKeywordInput" placeholder="輸入全詞匹配關鍵詞">
        <button onclick="addDanmakuKeyword('full')">新增</button>
      </div>
      <div class="tags" id="fullKeywords"></div>
    </div>
  </div>

  <script>
    let adConfig = {};
    let danmakuConfig = {};

    async function loadData() {
      // 載入去廣告配置
      try {
        const configRes = await fetch('/api/ad-filter/config');
        adConfig = await configRes.json();
        updateSwitch('filterSponsored', adConfig.filterSponsored);
        updateSwitch('filterClickbait', adConfig.filterClickbait);
        updateSwitch('filterLowQuality', adConfig.filterLowQuality);
      } catch (e) { console.error(e); }

      // 載入UP主名稱
      try {
        const upRes = await fetch('/api/ad-filter/upnames');
        const upData = await upRes.json();
        renderTags('upNames', upData.upnames || [], deleteUpName, false, true);
      } catch (e) { console.error(e); }

      // 載入自定義關鍵詞
      try {
        const adRes = await fetch('/api/ad-filter/keywords');
        const adData = await adRes.json();
        renderTags('adKeywords', adData.keywords || [], deleteAdKeyword);
      } catch (e) { console.error(e); }

      // 載入彈幕配置
      try {
        const dmConfigRes = await fetch('/api/danmaku/config');
        danmakuConfig = await dmConfigRes.json();
        updateSwitch('enableFilter', danmakuConfig.enableFilter);
      } catch (e) { console.error(e); }

      // 載入部分匹配關鍵詞
      loadDanmakuKeywords('partial');
      // 載入全詞匹配關鍵詞
      loadDanmakuKeywords('full');
    }

    async function loadDanmakuKeywords(type) {
      try {
        // partial 也可以用 /api/danmaku/block (相容)
        const path = type === 'partial' ? '/api/danmaku/block' : '/api/danmaku/block/' + type;
        const res = await fetch(path);
        const data = await res.json();
        renderTags(type + 'Keywords', data.keywords || [], (k) => deleteDanmakuKeyword(type, k));
      } catch (e) { console.error(e); }
    }

    function updateSwitch(id, value) {
      const el = document.getElementById(id);
      if (el) {
        el.classList.toggle('on', value);
      }
    }

    async function toggleAdConfig(key) {
      adConfig[key] = !adConfig[key];
      updateSwitch(key, adConfig[key]);
      await fetch('/api/ad-filter/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [key]: adConfig[key] })
      });
    }

    async function toggleDanmakuConfig(key) {
      danmakuConfig[key] = !danmakuConfig[key];
      updateSwitch(key, danmakuConfig[key]);
      await fetch('/api/danmaku/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [key]: danmakuConfig[key] })
      });
    }

    function renderTags(containerId, keywords, deleteFunc, isHighlight, isBlocked) {
      const container = document.getElementById(containerId);
      if (!container) return;
      if (keywords.length === 0) {
        container.innerHTML = '<span class="empty">暫無</span>';
        return;
      }
      container.innerHTML = '';
      keywords.forEach(k => {
        const tag = document.createElement('span');
        tag.className = 'tag' + (isHighlight ? ' highlight' : '') + (isBlocked ? ' blocked' : '');
        tag.innerHTML = k + ' <span class="delete">×</span>';
        tag.querySelector('.delete').onclick = (e) => {
          e.stopPropagation();
          deleteFunc(k);
        };
        container.appendChild(tag);
      });
    }

    async function addUpName() {
      const input = document.getElementById('upNameInput');
      const name = input.value.trim();
      if (!name) return;
      await fetch('/api/ad-filter/upnames', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name })
      });
      input.value = '';
      loadData();
    }

    async function deleteUpName(name) {
      await fetch('/api/ad-filter/upnames/' + encodeURIComponent(name), { method: 'DELETE' });
      loadData();
    }

    async function addAdKeyword() {
      const input = document.getElementById('adKeywordInput');
      const keyword = input.value.trim();
      if (!keyword) return;
      await fetch('/api/ad-filter/keywords', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ keyword })
      });
      input.value = '';
      loadData();
    }

    async function deleteAdKeyword(keyword) {
      await fetch('/api/ad-filter/keywords/' + encodeURIComponent(keyword), { method: 'DELETE' });
      loadData();
    }

    async function addDanmakuKeyword(type) {
      const input = document.getElementById(type + 'KeywordInput');
      const keyword = input.value.trim();
      if (!keyword) return;
      
      const path = type === 'partial' ? '/api/danmaku/block' : '/api/danmaku/block/' + type;
      
      await fetch(path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ keyword })
      });
      input.value = '';
      loadDanmakuKeywords(type); // 只重新整理對應列表
    }

    async function deleteDanmakuKeyword(type, keyword) {
      const path = type === 'partial' 
        ? '/api/danmaku/block/' + encodeURIComponent(keyword)
        : '/api/danmaku/block/' + type + '/' + encodeURIComponent(keyword);
        
      await fetch(path, { method: 'DELETE' });
      loadDanmakuKeywords(type); // 只重新整理對應列表
    }

    // 回車鍵提交
    document.getElementById('upNameInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addUpName();
    });
    document.getElementById('adKeywordInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addAdKeyword();
    });
    document.getElementById('partialKeywordInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addDanmakuKeyword('partial');
    });
    document.getElementById('fullKeywordInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addDanmakuKeyword('full');
    });

    loadData();
  </script>
</body>
</html>
''';
}
