import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:fluttertoast/fluttertoast.dart';

/// 與 [Fluttertoast.showToast] 相同，但 msg 會依語言設定轉換繁簡。
Future<bool?> showZhToast({
  required String msg,
  Toast? toastLength,
  ToastGravity? gravity,
  int timeInSecForIosWeb = 1,
  Color? backgroundColor,
  Color? textColor,
  double? fontSize,
}) {
  return Fluttertoast.showToast(
    msg: ZhConvert.convert(msg),
    toastLength: toastLength,
    gravity: gravity,
    timeInSecForIosWeb: timeInSecForIosWeb,
    backgroundColor: backgroundColor,
    textColor: textColor,
    fontSize: fontSize,
  );
}
