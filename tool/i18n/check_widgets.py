"""找出漏網的元件：直接 import flutter/material.dart，又用到被
lib/widgets/zh_material_widgets.dart 包裝的元件（Tooltip、IconButton、Tab、
InputDecoration）的檔案。這些檔案會讓 tooltip／提示文字不經過 ZhConvert，
應改 import package:bili_tv_app/widgets/zh_material.dart。

用法（用 -I 隔離，避免載入工作目錄裡的模組）：

    python -I tool/i18n/check_widgets.py

有漏網時印出檔案與行號，結束碼為 1；沒有時結束碼為 0。
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 被包裝的元件（見 lib/widgets/zh_material_widgets.dart）
WRAPPED = ('Tooltip', 'IconButton', 'Tab', 'InputDecoration')

# 定義包裝元件的檔案本身要直接 import material。
SKIP = ('lib/widgets/zh_',)

MATERIAL_IMPORT = re.compile(r"import\s+'package:flutter/material\.dart'([^;]*);")
USE = re.compile(r'(?<![\w.])(' + '|'.join(WRAPPED) + r')\b\s*(\(|\.)')
LINE_COMMENT = re.compile(r'//.*')


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    bad = []
    for path in sorted(glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        if rel.startswith(SKIP):
            continue
        with open(path, encoding='utf-8') as f:
            src = f.read()
        imports = MATERIAL_IMPORT.findall(src)
        if not imports:
            continue
        # 有 hide 掉全部被包裝元件、或 show 子句不含它們的 import 不會造成漏網
        risky = False
        for clause in imports:
            if re.search(r'\bshow\b', clause) and not any(
                re.search(r'\b' + w + r'\b', clause) for w in WRAPPED
            ):
                continue
            risky = True
        if not risky:
            continue
        for no, line in enumerate(src.splitlines(), 1):
            code = LINE_COMMENT.sub('', line)
            m = USE.search(code)
            if m:
                bad.append(f'{rel}:{no}: {m.group(1)}')
    if bad:
        print('直接 import flutter/material.dart 又用到被包裝元件的檔案：')
        for b in bad:
            print('  ' + b)
        print('請改 import package:bili_tv_app/widgets/zh_material.dart')
        return 1
    print('check_widgets: 沒有漏網')
    return 0


if __name__ == '__main__':
    sys.exit(main())
