import 'package:flutter/widgets.dart';

import '../settings_index.dart';

/// 讓設定 row 在搜尋結果選中自己時請求焦點。
///
/// 使用的 State 要提供 [focusTargetLabel] 與 [focusTargetNode]。
mixin SettingFocusTargetMixin<W extends StatefulWidget> on State<W> {
  String get focusTargetLabel;
  FocusNode get focusTargetNode;

  @override
  void initState() {
    super.initState();
    SettingsFocusTarget.notifier.addListener(_onFocusTarget);
  }

  @override
  void dispose() {
    SettingsFocusTarget.notifier.removeListener(_onFocusTarget);
    super.dispose();
  }

  void _onFocusTarget() {
    if (SettingsFocusTarget.notifier.value != focusTargetLabel) return;
    if (!focusTargetNode.canRequestFocus) return;
    focusTargetNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = focusTargetNode.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }
}
