// 內含會依語言設定轉換繁簡的 Text（zh_text.dart）的 material 函式庫。
// 另外 Tooltip、IconButton、Tab、InputDecoration 的字串參數也會轉換
// （zh_material_widgets.dart）。見 tool/use_zh_text.py、
// tool/i18n/check_widgets.py。
export 'package:bili_tv_app/widgets/zh_material_widgets.dart';
export 'package:bili_tv_app/widgets/zh_text.dart';
export 'package:flutter/material.dart'
    hide Text, Tooltip, IconButton, Tab, InputDecoration;
