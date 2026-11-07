"""Make the Chinese script dictionaries in assets/zh/ for lib/utils/zh_convert.dart.

The app converts text when it draws it:
  traditional mode: OpenCC s2tw  (assets/zh/s2t.txt)
  simplified mode:  OpenCC tw2sp (assets/zh/t2s.txt)

The Dart side does a longest-match lookup on one table (plus, in
simplified mode, an exact-match table for UI strings, t2s_ui.txt). OpenCC converts in
several steps (phrases, characters, Taiwan variants), so each key of the
OpenCC source dictionaries is converted here with the real OpenCC chain
(Python package `opencc`). That gives one table with the same result as
OpenCC for each entry.

    pip install opencc
    python tool/gen_zh_dict.py [folder for the downloaded .txt files]
    python tool/gen_zh_dict.py --ui-only   # only t2s_ui.txt

Dictionary data: OpenCC (https://github.com/BYVoid/OpenCC), Apache-2.0.
"""
import glob
import os
import re
import sys
import tempfile
import urllib.request

import opencc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'zh')
BASE = 'https://raw.githubusercontent.com/BYVoid/OpenCC/master/'

# OpenCC source dictionaries whose keys are converted for each mode.
SOURCES = {
    's2t': ('s2tw', ['STPhrases', 'STCharacters', 'TWVariants']),
    't2s': ('tw2sp', ['TWVariantsRevPhrases', 'TWPhrasesRev', 'TSPhrases',
                      'TSCharacters', 'TWVariants:values']),
}

_tw2s = opencc.OpenCC('tw2s')


def _not_simplified(key):
    """Simplified mode converts server text, which is already Simplified.
    A Taiwan phrase written the same in both scripts (for example 智慧 or
    影片) must not change it, so only phrases with a Traditional-only
    character stay (for example 設定 -> 设置)."""
    return _tw2s.convert(key) != key


PHRASE_FILTER = {'t2s': _not_simplified}

# Entries added after the OpenCC ones. 台灣 is common in Taiwan: keep it
# as written instead of OpenCC's 臺灣 (the login region name uses it).
OVERRIDES = {'s2t': {'台灣': '台灣'}}

# Simplified forms of the Taiwan screen wording .
SCREEN_S = {'全屏幕': '全屏', '横向屏幕': '横屏', '直向屏幕': '竖屏',
            '小屏幕': '小屏'}


def load(folder, name):
    """Keys of an OpenCC dictionary. 'X:values' gives the values of X."""
    name, _, part = name.partition(':')
    path = os.path.join(folder, name + '.txt')
    if not os.path.exists(path):
        urllib.request.urlretrieve(f'{BASE}data/dictionary/{name}.txt', path)
    out = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            key, _, values = line.partition('\t')
            out.extend(values.split(' ') if part == 'values' else [key])
    return out


def build(config, keys, phrase_filter=None):
    cc = opencc.OpenCC(config)
    table = {}
    for key in dict.fromkeys(keys):
        if len(key) == 1:
            value = cc.convert(key)
            if value != key:
                table[key] = value
    for key in dict.fromkeys(keys):
        if len(key) < 2 or (phrase_filter and not phrase_filter(key)):
            continue
        # Keep every phrase, also one that converts like its characters or
        # to itself: in a longest match it stops a shorter phrase that
        # overlaps it (as in OpenCC).
        table[key] = cc.convert(key)
    return table


def _longest_match(text, table, max_len):
    """Same conversion as ZhConvert._convert in Dart."""
    out, i = [], 0
    while i < len(text):
        n = min(max_len.get(text[i], 0), len(text) - i)
        while n > 0:
            value = table.get(text[i:i + n])
            if value is not None:
                out.append(value)
                i += n
                break
            n -= 1
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def write_ui_table():
    """assets/zh/t2s_ui.txt: whole UI strings (string literals in lib/
    without interpolation) with their full OpenCC tw2sp result, for the
    ones where t2s.txt gives a different result. t2s.txt leaves out
    Taiwan phrases that also change Simplified server text (影片 -> 视频);
    for a known UI string the full conversion is safe."""
    table, max_len = {}, {}
    with open(os.path.join(OUT, 't2s.txt'), encoding='utf-8') as f:
        for line in f:
            key, _, value = line.rstrip('\n').partition('\t')
            if key:
                table[key] = value
                max_len[key[0]] = max(max_len.get(key[0], 0), len(key))
    cc = opencc.OpenCC('tw2sp')
    # 單引號與雙引號字串都處理；含 $ 插值的字串略過（簡體模式靠字表轉換）
    literal = re.compile(
        r"'([^'\n$\\]*[一-鿿][^'\n$\\]*)'"
        r'|"([^"\n$\\]*[一-鿿][^"\n$\\]*)"'
    )
    ui = {}
    for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        if os.sep + 'grpc' + os.sep in path:
            continue
        with open(path, encoding='utf-8') as f:
            # 逐行處理並略過註解行，避免註解中的撇號讓引號配對錯位
            code = ''.join(l for l in f if not l.lstrip().startswith('//'))
            for single, double in literal.findall(code):
                text = single or double
                full = cc.convert(text)
                # The Taiwan UI says 全螢幕 / 橫向螢幕; Simplified users
                # expect the short forms 全屏 / 横屏.
                for a, b in SCREEN_S.items():
                    full = full.replace(a, b)
                if full != _longest_match(text, table, max_len):
                    ui[text] = full
    with open(os.path.join(OUT, 't2s_ui.txt'), 'w', encoding='utf-8',
              newline='\n') as f:
        for k in sorted(ui):
            f.write(f'{k}\t{ui[k]}\n')
    print('t2s_ui', len(ui), 'entries')


def main():
    if '--ui-only' in sys.argv:
        # 只重新產生 t2s_ui.txt（需要 assets/zh/t2s.txt 已存在）
        write_ui_table()
        return
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(tempfile.gettempdir(), 'opencc_dict')
    os.makedirs(folder, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for out_name, (config, names) in SOURCES.items():
        keys = [k for n in names for k in load(folder, n)]
        table = build(config, keys, PHRASE_FILTER.get(out_name))
        table.update(OVERRIDES.get(out_name, {}))
        with open(os.path.join(OUT, out_name + '.txt'), 'w', encoding='utf-8',
                  newline='\n') as f:
            for k in sorted(table):
                f.write(f'{k}\t{table[k]}\n')
        print(out_name, len(table), 'entries')
    write_ui_table()
    lic = os.path.join(OUT, 'LICENSE')
    if not os.path.exists(lic):
        urllib.request.urlretrieve(BASE + 'LICENSE', lic)


if __name__ == '__main__':
    main()
