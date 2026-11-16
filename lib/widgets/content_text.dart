import 'package:bili_tv_app/models/reply_item.dart';
import 'package:bili_tv_app/services/translate/content_translator.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:cached_network_image/cached_network_image.dart';
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
    this.emotes = const {},
  });

  final String text;

  /// 表情代碼對應的圖片（留言用）；文字中的 `[代碼]` 會換成圖片。
  final Map<String, ReplyEmote> emotes;
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

  static final _emotePattern = RegExp(r'\[[^\[\]\n]{1,30}\]');

  // 顯示文字經過繁簡轉換，代碼可能已被轉成繁體，所以兩種寫法都對應。
  Map<String, ReplyEmote>? _emoteLookup;
  Map<String, ReplyEmote>? _emoteSource;

  Map<String, ReplyEmote> _lookup() {
    if (!identical(_emoteSource, widget.emotes) || _emoteLookup == null) {
      _emoteSource = widget.emotes;
      _emoteLookup = {
        for (final e in widget.emotes.entries) ...{
          e.key: e.value,
          ZhConvert.convertContent(e.key): e.value,
        },
      };
    }
    return _emoteLookup!;
  }

  InlineSpan? _richText(String text) {
    if (widget.emotes.isEmpty) return null;
    final lookup = _lookup();
    final fontSize = widget.style?.fontSize ?? 14;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _emotePattern.allMatches(text)) {
      final emote = lookup[m.group(0)];
      if (emote == null) continue;
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final size = emote.large ? fontSize * 3 : fontSize * 1.4;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CachedNetworkImage(
            imageUrl: emote.url,
            width: size,
            height: size,
            fit: BoxFit.contain,
            memCacheHeight: (size * 2).round(),
            errorWidget: (_, _, _) =>
                flutter.Text(m.group(0)!, style: widget.style),
          ),
        ),
      );
      last = m.end;
    }
    if (spans.isEmpty) return null;
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final display = _resolver.display;
    final rich = _richText(display);
    if (rich != null) {
      return flutter.Text.rich(
        rich,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
        softWrap: widget.softWrap,
      );
    }
    return flutter.Text(
      display,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      softWrap: widget.softWrap,
    );
  }
}
