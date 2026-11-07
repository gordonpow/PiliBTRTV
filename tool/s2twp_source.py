"""將 lib/**/*.dart 的簡體文字以 OpenCC s2twp 轉為台灣繁體。

含有 KEEP_MARK 的行與其後一行、以及 (begin)/(end) 之間的區塊視為「與伺服器簡體文字比對、保留原文」，不轉換。
用法：python tool/s2twp_source.py
"""
import glob
import os

import opencc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEEP_MARK = '保留原文'
cc = opencc.OpenCC('s2twp')


def main():
    changed = 0
    for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        with open(path, encoding='utf-8', newline='') as f:
            src = f.read()
        lines = src.split('\n')
        out = []
        in_block = False
        skip_next = False
        for line in lines:
            if skip_next:
                skip_next = False
                out.append(line)
            elif KEEP_MARK in line:
                # (begin) / (end) 包住的區塊整段保留
                if '(begin)' in line:
                    in_block = True
                elif '(end)' in line:
                    in_block = False
                else:
                    skip_next = True
                out.append(line)
            elif in_block:
                out.append(line)
            else:
                out.append(cc.convert(line))
        res = '\n'.join(out)
        if res != src:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(res)
            changed += 1
    print('changed', changed, 'files')


if __name__ == '__main__':
    main()
