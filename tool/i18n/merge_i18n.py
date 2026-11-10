"""Merge translated batches (i18n/batches/out-*.json) into i18n/en.json.

Each batch: {"strings": {zh: en}, "templates": {zh: en}}.
Checks: valid JSON, non-empty value, same placeholders (each exactly once; order may change for English word order).
Bad items go to i18n/merge-errors.txt (re-translate them); earlier good
translations in en.json are kept.
"""
import datetime
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PH = re.compile(r'\{\d+\}')
CJK = re.compile(r'[㐀-鿿豈-﫿]')
# English values that may keep Chinese characters (language names shown as is).
CJK_OK = {'繁體中文', '簡體中文'}


def main():
    i18n = os.path.join(ROOT, 'i18n')
    en_path = os.path.join(i18n, 'en.json')
    en = {'strings': {}, 'templates': {}}
    if os.path.exists(en_path):
        with open(en_path, encoding='utf-8') as f:
            en.update(json.load(f))

    errors, merged = [], 0
    for path in sorted(glob.glob(os.path.join(i18n, 'batches', 'out-*.json'))):
        name = os.path.basename(path)
        try:
            with open(path, encoding='utf-8') as f:
                data = json.load(f)
            if not isinstance(data, dict):
                raise ValueError('top level is not an object')
        except Exception as e:
            errors.append(f'{name}\t<file>\tinvalid JSON: {e}')
            continue
        for kind in ('strings', 'templates'):
            items = data.get(kind, {})
            if not isinstance(items, dict):
                errors.append(f'{name}\t{kind}\t<all>\tnot an object')
                continue
            for k, v in items.items():
                if not isinstance(v, str) or not v.strip():
                    errors.append(f'{name}\t{kind}\t{k}\tempty or non-string value')
                elif CJK.search(v) and v not in CJK_OK:
                    errors.append(f'{name}	{kind}	{k}	value contains Chinese: {v}')
                elif sorted(PH.findall(k)) != sorted(PH.findall(v)):
                    errors.append(f'{name}\t{kind}\t{k}\tplaceholder mismatch: {v}')
                else:
                    en[kind][k] = v
                    merged += 1

    out = {'version': datetime.datetime.now().strftime('%Y%m%d%H%M'),
           'strings': dict(sorted(en['strings'].items())),
           'templates': dict(sorted(en['templates'].items()))}
    with open(en_path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    with open(os.path.join(i18n, 'merge-errors.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(errors) + ('\n' if errors else ''))
    print(f'merged={merged} errors={len(errors)} total_strings={len(out["strings"])} '
          f'total_templates={len(out["templates"])}')


if __name__ == '__main__':
    main()
