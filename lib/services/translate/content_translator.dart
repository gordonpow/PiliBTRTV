import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_tv_app/services/perf_log.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path_provider/path_provider.dart';

/// ML Kit 呼叫的抽象，單元測試用假實作取代。
abstract class TranslateEngine {
  /// 中文與英文模型是否都已下載。
  Future<bool> isModelDownloaded();

  /// 下載中文與英文模型；失敗丟出含底層訊息的例外。
  Future<void> downloadModel();

  /// 中文 → 英文。
  Future<String> translate(String text);

  Future<void> close();
}

/// Google ML Kit 的實作（外掛不回報下載進度）。
class MlKitTranslateEngine implements TranslateEngine {
  static const _zh = 'zh';
  static const _en = 'en';

  OnDeviceTranslatorModelManager? _manager;
  OnDeviceTranslator? _translator;

  OnDeviceTranslatorModelManager get _modelManager =>
      _manager ??= OnDeviceTranslatorModelManager();

  @override
  Future<bool> isModelDownloaded() async =>
      await _modelManager.isModelDownloaded(_zh) &&
      await _modelManager.isModelDownloaded(_en);

  @override
  Future<void> downloadModel() async {
    final zh = await _modelManager.downloadModel(_zh, isWifiRequired: false);
    final en = await _modelManager.downloadModel(_en, isWifiRequired: false);
    if (!zh || !en) throw Exception('model not downloaded (zh=$zh, en=$en)');
  }

  @override
  Future<String> translate(String text) async {
    final t = _translator ??= OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.chinese,
      targetLanguage: TranslateLanguage.english,
    );
    return (await t.translateText(text)).trim();
  }

  @override
  Future<void> close() async {
    final t = _translator;
    _translator = null;
    await t?.close();
  }
}

/// 一筆可取消的翻譯請求。
class TranslateRequest {
  TranslateRequest._(this._task);

  final _Task _task;
  bool _cancelled = false;

  /// 譯文；取消、失敗或無譯文時為 null。
  Future<String?> get future => _task.completer.future;

  /// 放棄這筆請求。同字串沒有其他等待者且尚未開始翻譯時，移出佇列。
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _task.waiters--;
    if (_task.waiters <= 0 && !_task.started) {
      _task.onDrop(_task);
    }
  }
}

class _Task {
  _Task(this.raw, this.onDrop, this.priority);

  final String raw;
  final void Function(_Task) onDrop;
  final completer = Completer<String?>();
  int waiters = 1;
  int priority;
  bool started = false;
}

/// B 站內容（標題、UP 主名稱、字幕）的裝置端中→英翻譯（#17）。
///
/// 規格：docs/work/content-translate/2-spec.md（R-3～R-5、R-14）。
/// 快取 key 與 ML Kit 輸入一律是 B 站原文 raw。
class ContentTranslator with WidgetsBindingObserver {
  ContentTranslator._()
    : _engine = MlKitTranslateEngine(),
      _directoryProvider = _defaultDirectory,
      saveDelay = const Duration(seconds: 10),
      pollInterval = const Duration(seconds: 5),
      _observeLifecycle = true;

  /// 測試用：換掉 ML Kit 與快取資料夾。
  @visibleForTesting
  ContentTranslator.withEngine(
    this._engine, {
    Future<Directory> Function()? directory,
    this.saveDelay = const Duration(seconds: 10),
    this.pollInterval = const Duration(seconds: 5),
  }) : _directoryProvider = directory ?? _defaultDirectory,
       _observeLifecycle = false;

  /// 全域實例；測試可換成 [ContentTranslator.withEngine] 建立的假實作。
  static ContentTranslator instance = ContentTranslator._();

  static const _cacheMax = 5000;
  static const _cacheFile = 'translate_cache.json';
  // 假名、中日韓漢字、相容漢字、韓文音節（用 code point 組，避免被 i18n 掃描）
  static final _cjk = RegExp(
    '[${_r(0x3040, 0x30ff)}${_r(0x3400, 0x4dbf)}${_r(0x4e00, 0x9fff)}'
    '${_r(0xf900, 0xfaff)}${_r(0xac00, 0xd7af)}]',
  );

  static String _r(int a, int b) =>
      '${String.fromCharCode(a)}-${String.fromCharCode(b)}';

  final TranslateEngine _engine;
  final Future<Directory> Function() _directoryProvider;
  final Duration saveDelay;

  /// 模型下載失敗、略過或被重啟打斷時，輪詢「模型是否已下載完」的間隔。
  final Duration pollInterval;
  final bool _observeLifecycle;
  bool _observing = false;

  /// 翻譯可用狀態（modelReady、開關）改變時遞增；ContentText 等監聽後
  /// 重新解析顯示文字。
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  bool _modelReady = false;

  /// 模型已就緒（R-5）：啟動時檢查一次，下載成功時設 true。
  bool get modelReady => _modelReady;
  set modelReady(bool v) {
    if (_modelReady == v) return;
    _modelReady = v;
    notifyChanged();
  }

  /// 設定開關變動後呼叫，通知顯示處重新解析。
  void notifyChanged() => changes.value++;

  // Map 字面值保留插入順序，當作 LRU。
  final _cache = <String, String>{};
  final _queue = <_Task>[];
  final _inflight = <String, _Task>{};
  bool _running = false;
  Future<void>? _loadFuture;
  bool _dirty = false;
  Timer? _saveTimer;
  Future<void> _writeChain = Future<void>.value();

  /// 英文介面＋已開啟「翻譯 B 站內容」＋模型已就緒時為 true。
  bool get enabled =>
      SettingsService.translateContent &&
      ZhConvert.script == ZhScript.english &&
      modelReady;

  /// 是否含中日韓字元（只有這種字串才需要翻譯）。
  static bool needsTranslate(String raw) => _cjk.hasMatch(raw);

  /// 背景下載失敗後多久內不重試。
  static const retryBackoff = Duration(hours: 24);

  bool _bgDownloading = false;
  bool _loggedTranslateFailure = false;

  /// 啟動時呼叫（ZhConvert.init 之後）：開關為 true 才檢查模型並載入快取；
  /// 英文介面且模型未下載時在背景下載（不阻塞、不跳對話框）。
  Future<void> init() async {
    if (!SettingsService.translateContent) return;
    bool ready;
    try {
      ready = await _engine.isModelDownloaded();
    } catch (e) {
      PerfLog.add('翻譯: 模型檢查失敗 $e');
      ready = false;
    }
    PerfLog.add('翻譯: 啟動檢查 模型${ready ? '已下載' : '未下載'}');
    if (ready) {
      await enable();
    } else if (ZhConvert.script == ZhScript.english) {
      unawaited(downloadInBackground());
      _watchModel();
    }
  }

  static const _pollMax = 60;
  bool _watching = false;

  /// 下載可能在原生層由先前（重啟前）的程序完成，或這次下載丟例外／被
  /// 退避略過，導致 modelReady 一直是 false；輪詢到模型存在就 enable＋通知，
  /// 讓畫面上已顯示的原文自動換成譯文。
  void _watchModel() {
    if (_watching || modelReady) return;
    _watching = true;
    unawaited(() async {
      try {
        for (var i = 0; i < _pollMax && !modelReady; i++) {
          await Future<void>.delayed(pollInterval);
          if (modelReady) return;
          if (!SettingsService.translateContent) return;
          if (_bgDownloading) continue;
          if (await isModelDownloaded()) {
            PerfLog.add('翻譯: 輪詢發現模型已就緒');
            await enable();
            return;
          }
        }
      } finally {
        _watching = false;
      }
    }());
  }

  /// 背景下載模型：成功後 enable＋通知；失敗只記錄，並記下時間讓 24 小時內
  /// 不重試。[force] 為 true（使用者剛選 English）時略過退避。永遠不丟例外。
  Future<void> downloadInBackground({bool force = false}) async {
    if (_bgDownloading || !SettingsService.translateContent) return;
    if (!force) {
      final last = SettingsService.translateDownloadFailedAt;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last > 0 && now - last < retryBackoff.inMilliseconds) {
        PerfLog.add('翻譯: 背景下載略過（上次失敗未滿 24 小時）');
        return;
      }
    }
    _bgDownloading = true;
    try {
      if (await isModelDownloaded()) {
        await enable();
        return;
      }
      await downloadModel();
      notifyChanged();
    } catch (_) {
      // 失敗原因已由 downloadModel 寫進 PerfLog
      await SettingsService.setTranslateDownloadFailedAt(
        DateTime.now().millisecondsSinceEpoch,
      );
      _watchModel();
    } finally {
      _bgDownloading = false;
    }
  }

  /// 載入快取後才設 modelReady（避免先顯示未載入的狀態）。
  Future<void> enable() async {
    await _loadCache();
    modelReady = true;
  }

  Future<bool> isModelDownloaded() async {
    try {
      return await _engine.isModelDownloaded();
    } catch (_) {
      return false;
    }
  }

  /// 下載模型；失敗丟出含底層訊息的例外。成功後設 modelReady 並載入快取。
  Future<void> downloadModel() async {
    PerfLog.add('翻譯: 開始下載模型');
    try {
      await _engine.downloadModel();
    } catch (e) {
      modelReady = false;
      PerfLog.add('翻譯: 模型下載失敗 $e');
      throw Exception('$e');
    }
    PerfLog.add('翻譯: 模型下載成功');
    await enable();
  }

  /// 關閉翻譯器：放棄佇列、釋放 ML Kit、立即存檔快取。
  Future<void> close() async {
    modelReady = false;
    for (final t in List.of(_queue)) {
      _drop(t);
    }
    await _flush();
    try {
      await _engine.close();
    } catch (_) {}
  }

  /// 同步查快取（key 為 B 站原文 raw）；沒有回 null。
  String? cached(String raw) {
    final hit = _cache.remove(raw);
    if (hit != null) _cache[raw] = hit;
    return hit;
  }

  /// 翻譯單一字串（raw 原文）。不含中日韓字元時原樣回傳；失敗回 null。
  Future<String?> translate(String raw) => request(raw).future;

  /// 同 [translate]，但可取消尚未開始的任務（R-4）。
  ///
  /// [priority] 越大越先翻譯；同優先序新請求排前面（LIFO，剛進入畫面的
  /// 卡片優先）。字幕（translateBatch）用 1，永遠排在卡片（0）之前。
  TranslateRequest request(String raw, {int priority = 0}) {
    final hit = cached(raw);
    if (hit != null || !needsTranslate(raw)) {
      final task = _Task(raw, _drop, priority)..completer.complete(hit ?? raw);
      return TranslateRequest._(task);
    }
    var task = _inflight[raw];
    if (task != null) {
      task.waiters++;
      if (priority > task.priority && !task.started) {
        task.priority = priority;
        _queue.remove(task);
        _enqueue(task);
      }
    } else {
      task = _Task(raw, _drop, priority);
      _inflight[raw] = task;
      _enqueue(task);
      scheduleMicrotask(_pump);
    }
    return TranslateRequest._(task);
  }

  /// 依序翻譯字幕各行；[isCancelled] 每句之間檢查，回 true 即停止。
  /// [onLine] 在每句完成時回呼（index、譯文），供字幕逐句替換。
  Future<void> translateBatch(
    List<String> lines, {
    required bool Function() isCancelled,
    required void Function(int index, String translated) onLine,
  }) async {
    for (var i = 0; i < lines.length; i++) {
      if (isCancelled()) return;
      final r = await request(lines[i], priority: 1).future;
      if (isCancelled()) return;
      if (r != null) onLine(i, r);
    }
  }

  void _enqueue(_Task t) {
    final i = _queue.indexWhere((q) => q.priority <= t.priority);
    _queue.insert(i < 0 ? _queue.length : i, t);
  }

  void _drop(_Task t) {
    _queue.remove(t);
    if (identical(_inflight[t.raw], t)) _inflight.remove(t.raw);
    if (!t.completer.isCompleted) t.completer.complete(null);
  }

  // 序列佇列（並行 1），同 A 的 _offlineChain。
  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final t = _queue.removeAt(0);
        t.started = true;
        String? result;
        try {
          final r = (await _engine.translate(t.raw)).trim();
          if (r.isNotEmpty) {
            result = r;
            _put(t.raw, r);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('content translate failed: $e');
          if (!_loggedTranslateFailure) {
            _loggedTranslateFailure = true;
            PerfLog.add('翻譯: 首次翻譯失敗 $e');
          }
        }
        if (identical(_inflight[t.raw], t)) _inflight.remove(t.raw);
        if (!t.completer.isCompleted) t.completer.complete(result);
      }
    } finally {
      _running = false;
    }
  }

  void _put(String raw, String value) {
    _cache.remove(raw);
    if (_cache.length >= _cacheMax) _cache.remove(_cache.keys.first);
    _cache[raw] = value;
    _dirty = true;
    // 每次重設 debounce；App 進背景時另外 flush。
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () {
      _saveTimer = null;
      _writeChain = _writeChain.then((_) => _write());
    });
  }

  static Future<Directory> _defaultDirectory() =>
      getApplicationDocumentsDirectory();

  Future<File> _file() async =>
      File('${(await _directoryProvider()).path}/$_cacheFile');

  Future<void> _loadCache() {
    _observe();
    return _loadFuture ??= _doLoadCache();
  }

  void _observe() {
    if (!_observeLifecycle || _observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_flush());
  }

  Future<void> _doLoadCache() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) throw const FormatException('not a map');
      final loaded = <String, String>{};
      data.forEach((k, v) {
        if (k is String && v is String) loaded[k] = v;
      });
      // 啟動後新翻的優先，放在載入內容之後。
      final fresh = Map.of(_cache);
      _cache
        ..clear()
        ..addAll(loaded)
        ..addAll(fresh);
      while (_cache.length > _cacheMax) {
        _cache.remove(_cache.keys.first);
      }
    } catch (e) {
      // 損毀：清空重建。
      if (kDebugMode) debugPrint('translate cache broken: $e');
      _cache.clear();
      try {
        final file = await _file();
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) _writeChain = _writeChain.then((_) => _write());
    await _writeChain;
  }

  Future<void> _write() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_cache));
      await tmp.rename(file.path);
    } catch (e) {
      _dirty = true;
      if (kDebugMode) debugPrint('translate cache write failed: $e');
    }
  }
}
