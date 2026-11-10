// ignore_for_file: deprecated_member_use

import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter/material.dart' as material;

// 以字串接收標籤文字、再用 Flutter 原生 Text 畫出的 material 元件。
// 這裡的版本會把字串依語言設定轉換（見 ZhConvert）。
// zh_material.dart 以這些類別取代 Flutter 原本的。
// 漏網檢查見 tool/i18n/check_widgets.py。

String? _zh(String? text) => text == null ? null : ZhConvert.convert(text);

/// [material.Tooltip]，[message] 會轉換。
class Tooltip extends material.Tooltip {
  const Tooltip({
    super.key,
    super.message,
    super.richMessage,
    super.height,
    super.constraints,
    super.padding,
    super.margin,
    super.verticalOffset,
    super.preferBelow,
    super.excludeFromSemantics,
    super.decoration,
    super.textStyle,
    super.textAlign,
    super.waitDuration,
    super.showDuration,
    super.exitDuration,
    super.enableTapToDismiss,
    super.triggerMode,
    super.enableFeedback,
    super.onTriggered,
    super.mouseCursor,
    super.ignorePointer,
    super.positionDelegate,
    super.child,
  });

  @override
  String? get message => _zh(super.message);
}

/// [material.IconButton]，[tooltip] 會轉換。
class IconButton extends material.IconButton {
  const IconButton({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
  });

  @override
  String? get tooltip => _zh(super.tooltip);
}

/// [material.Tab]，[text] 會轉換。
class Tab extends material.Tab {
  const Tab({
    super.key,
    super.text,
    super.icon,
    super.iconMargin,
    super.height,
    super.child,
  });

  @override
  String? get text => _zh(super.text);
}

/// [material.InputDecoration]，提示、標籤、說明與錯誤文字會轉換。
/// 只列出常用欄位；需要其他欄位時再加。
class InputDecoration extends material.InputDecoration {
  const InputDecoration({
    super.icon,
    super.labelText,
    super.label,
    super.labelStyle,
    super.helperText,
    super.helperStyle,
    super.hintText,
    super.hintStyle,
    super.errorText,
    super.errorStyle,
    super.floatingLabelBehavior,
    super.isCollapsed,
    super.isDense,
    super.contentPadding,
    super.prefixIcon,
    super.prefixText,
    super.suffixIcon,
    super.suffixText,
    super.counterText,
    super.filled,
    super.fillColor,
    super.focusColor,
    super.hoverColor,
    super.errorBorder,
    super.focusedBorder,
    super.focusedErrorBorder,
    super.disabledBorder,
    super.enabledBorder,
    super.border,
    super.enabled,
    super.constraints,
    super.visualDensity,
  });

  @override
  String? get labelText => _zh(super.labelText);

  @override
  String? get helperText => _zh(super.helperText);

  @override
  String? get hintText => _zh(super.hintText);

  @override
  String? get errorText => _zh(super.errorText);

  @override
  String? get prefixText => _zh(super.prefixText);

  @override
  String? get suffixText => _zh(super.suffixText);

  @override
  String? get counterText => _zh(super.counterText);
}
