import 'package:bili_tv_app/services/translate/content_translator.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:flutter/widgets.dart';

/// 解析 B 站內容要顯示的文字（#17，R-3、R-4）。
///
/// 英文介面且翻譯已啟用時：有快取直接用英文；沒有則先顯示原文，非同步
/// 翻譯完成後呼叫 [onChange]。其他情況只做繁簡轉換（不查 I18nPack 字典）。
/// 快取 key 與翻譯輸入一律用原文 raw。
class ContentResolver {
  ContentResolver(this._onChange, this._isMounted);

  final VoidCallback _onChange;
  final bool Function() _isMounted;

  String _raw = '';
  bool _listening = false;
  String? _translated;
  TranslateRequest? _request;

  /// 目前應顯示的文字。
  String get display => _translated ?? ZhConvert.convertContent(_raw);

  /// 設定原文；內容或設定改變時重新解析。回傳目前顯示文字是否已變。
  void update(String raw) {
    if (!_listening) {
      _listening = true;
      ContentTranslator.instance.changes.addListener(_onTranslatorChanged);
    }
    _raw = raw;
    _request?.cancel();
    _request = null;
    _translated = null;
    final translator = ContentTranslator.instance;
    if (!translator.enabled || raw.isEmpty) return;
    final hit = translator.cached(raw);
    if (hit != null) {
      _translated = hit;
      return;
    }
    if (!ContentTranslator.needsTranslate(raw)) return;
    final req = translator.request(raw);
    _request = req;
    req.future.then((r) {
      if (!identical(_request, req)) return;
      _request = null;
      if (r == null || !_isMounted()) return;
      _translated = r;
      _onChange();
    });
  }

  // 模型就緒或開關改變：重新解析並通知重繪。
  void _onTranslatorChanged() {
    if (!_isMounted()) return;
    update(_raw);
    _onChange();
  }

  /// 取消尚未開始的翻譯任務並停止監聽（widget dispose 時呼叫）。
  void dispose() {
    if (_listening) {
      _listening = false;
      ContentTranslator.instance.changes.removeListener(_onTranslatorChanged);
    }
    _request?.cancel();
    _request = null;
  }
}

/// 顯示 B 站內容（標題、UP 主名稱、直播標題、簽名）的文字。
///
/// 行為與 Text 相同，差別只在英文介面：不查介面字典，改走 ML Kit 翻譯。
class ContentText extends StatefulWidget {
  const ContentText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  @override
  State<ContentText> createState() => _ContentTextState();
}

class _ContentTextState extends State<ContentText> {
  late final ContentResolver _resolver = ContentResolver(
    () => setState(() {}),
    () => mounted,
  );

  @override
  void initState() {
    super.initState();
    _resolver.update(widget.text);
  }

  @override
  void didUpdateWidget(ContentText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _resolver.update(widget.text);
  }

  @override
  void dispose() {
    _resolver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return flutter.Text(
      _resolver.display,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      softWrap: widget.softWrap,
    );
  }
}
