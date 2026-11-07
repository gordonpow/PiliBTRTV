"""讓 lib/ 中所有 `Text(...)` 依語言設定轉換繁簡（見 lib/utils/zh_convert.dart）。

把 Flutter material／widgets 函式庫的 import 改為 lib/widgets/ 內的版本，
它們匯出相同的函式庫，但 `Text` 換成 zh_text.dart 的版本：

    package:flutter/material.dart -> package:bili_tv_app/widgets/zh_material.dart
    package:flutter/widgets.dart  -> package:bili_tv_app/widgets/zh_widgets.dart

保留 `show`／`hide` 子句；帶 `as` 前綴的 import 不改。腳本可重複執行：

    python tool/use_zh_text.py
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TARGETS = {
    'package:flutter/material.dart': 'package:bili_tv_app/widgets/zh_material.dart',
    'package:flutter/widgets.dart': 'package:bili_tv_app/widgets/zh_widgets.dart',
}

# 定義 Text 替代品的檔案要保留 Flutter 原本的 import。
SKIP = ('lib/widgets/zh_',)

IMPORT = re.compile(
    r"import '(" + '|'.join(re.escape(k) for k in TARGETS) + r")'(?P<rest>[^;]*);"
)


def fix(match):
    rest = match.group('rest')
    if re.search(r'\bas\s+\w+', rest):
        return match.group(0)
    return f"import '{TARGETS[match.group(1)]}'{rest};"


def main():
    changed = 0
    for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        if rel.startswith(SKIP):
            continue
        with open(path, encoding='utf-8', newline='') as f:
            src = f.read()
        out = IMPORT.sub(fix, src)
        if out != src:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(out)
            changed += 1
    print('changed', changed, 'files')


if __name__ == '__main__':
    main()
