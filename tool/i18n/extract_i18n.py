"""Extract Traditional Chinese UI literals from lib/ for the English language pack.

Run from the repo root:  python -I tool/i18n/extract_i18n.py

Outputs (under i18n/):
  source.json     {"strings": {...}, "templates": {...}}  (values empty)
  todo.json       same shape, only keys not yet translated in en.json
  review.txt      skipped literals (compared/parsed, map keys) with file:line

Interpolations ($name, ${expr}) become {0}, {1}... in templates.
Excluded literals come from tool/i18n/exclude.txt and from automatic rules
(server-compare comment markers, debugPrint/log lines).

Prints: total CJK literals, translated, untranslated list, stale en.json keys
(keys whose source literal no longer exists; `--prune` removes them).
Exit code 1 when untranslated > 0 or when a template cannot be matched at run
time (fewer than 2 Chinese chars, adjacent placeholders) and is not listed in
tool/i18n/exclude.txt (a file that formats it in Dart, e.g. format_count.dart).
"""
import glob
import importlib.util
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, 'i18n')
CJK = re.compile(r'[㐀-鿿豈-﫿]')  # CJK ideographs + compatibility (U+F900-FAFF)

spec = importlib.util.spec_from_file_location('dartlex', os.path.join(HERE, 'dartlex.py'))
dartlex = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dartlex)

# Comment that marks literals compared with Simplified server text.
SERVER_MARK = '與伺服器回傳的簡體文字比對'
# Lines whose literals are logs, not UI.
LOG_LINE = re.compile(r'\b(?:debugPrint|print|log|PerfLog\.\w+|developer\.log)\s*\(')

BEFORE = re.compile(
    r'(?:==|!=|\bcontains\(|\bstartsWith\(|\bendsWith\(|\bRegExp\(\s*r?|\bindexOf\(|'
    r'\breplaceFirst\(|\bsplit\(|\bcase)\s*$')
AFTER = re.compile(r'^\s*(?:==|!=)')
MAP_KEY_BEFORE = re.compile(r'(?:[{,]|^)\s*$')
MAP_KEY_AFTER = re.compile(r'^\s*:(?!:)')

# A literal is a log message when it sits inside the parentheses of one of these calls.
LOG_CALL = re.compile(r'\b(?:debugPrint|print|log|PerfLog\.\w+|developer\.log)\s*$')


def in_log_call(src, pos):
    """True when `pos` is inside the argument list of a log call (same statement only)."""
    depth = 0
    i = pos - 1
    stop = max(0, pos - 800)
    while i >= stop:
        c = src[i]
        if c == ')':
            depth += 1
        elif c == '(':
            if depth == 0:
                if LOG_CALL.search(src[max(0, i - 40):i]):
                    return True
            else:
                depth -= 1
        elif c in ';{}' and depth == 0:
            return False
        i -= 1
    return False


ESC = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', 'v': '\v'}


def load_exclude():
    """exclude.txt rows: `path` (whole file) or `path<TAB>text` (lines containing text)."""
    files, lines = set(), []
    p = os.path.join(HERE, 'exclude.txt')
    if os.path.exists(p):
        with open(p, encoding='utf-8') as f:
            for row in f:
                row = row.rstrip('\r\n')
                if not row.strip() or row.lstrip().startswith('#'):
                    continue
                if '\t' in row:
                    a, b = row.split('\t', 1)
                    lines.append((a.strip(), b))
                else:
                    files.add(row.strip())
    return files, lines


def unescape(t):
    out, i = [], 0
    while i < len(t):
        c = t[i]
        if c == '\\' and i + 1 < len(t):
            d = t[i + 1]
            if d in ESC:
                out.append(ESC[d])
                i += 2
            elif d == 'u':
                m = re.match(r'\{([0-9a-fA-F]+)\}|([0-9a-fA-F]{4})', t[i + 2:])
                if m:
                    out.append(chr(int(m.group(1) or m.group(2), 16)))
                    i += 2 + m.end()
                else:
                    out.append(d)
                    i += 2
            elif d == 'x' and re.match(r'[0-9a-fA-F]{2}', t[i + 2:i + 4]):
                out.append(chr(int(t[i + 2:i + 4], 16)))
                i += 4
            else:
                out.append(d)
                i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def cjk_count(s):
    return len(CJK.findall(s))


def main():
    ex_files, ex_lines = load_exclude()
    strings, templates = {}, {}
    review = []
    unhandled = []
    excluded = 0
    excl_rows = []
    total_literals = 0

    files = sorted(glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True))
    for path in files:
        rel = os.path.relpath(path, ROOT).replace('\\', '/')
        if rel.endswith('.g.dart'):
            continue
        with open(path, encoding='utf-8', newline='') as f:
            src = f.read()
        lines = src.split('\n')
        # Server-compare regions: "(begin)" ... "(end)" or the marker line + next 2 lines.
        marked = set()   # begin/end regions: always excluded
        near = set()     # marker + next 2 lines: excluded only when compared
        open_at = None
        for i, l in enumerate(lines):
            if SERVER_MARK in l:
                if '(begin)' in l:
                    open_at = i
                elif '(end)' in l:
                    if open_at is not None:
                        marked.update(range(open_at, i + 1))
                    open_at = None
                else:
                    near.update(range(i, i + 3))

        for qs, end, parts, raw in dartlex.literals(src):
            texts = [src[s:e] for k, s, e in parts if k == 't']
            if not any(CJK.search(t) for t in texts):
                continue
            ln = src.count('\n', 0, qs)
            line = lines[ln].rstrip('\r')
            where = f'{rel}:{ln + 1}'
            snippet = src[qs:end].replace('\n', '\\n').replace('\r', '')[:80]
            total_literals += 1

            ls = src.rfind('\n', 0, qs) + 1
            le = src.find('\n', end)
            le = len(src) if le < 0 else le
            before, after = src[ls:qs], src[end:le]
            if raw and before.endswith('r'):
                before = before[:-1]
            compared = bool(BEFORE.search(before) or AFTER.search(after))
            is_html = any('<!DOCTYPE' in t for t in texts)  # web pages served to a phone
            if (is_html or rel in ex_files or ln in marked or (ln in near and compared) or LOG_LINE.search(line) or in_log_call(src, qs)
                    or any(rel == a and b in line for a, b in ex_lines)):
                excluded += 1
                excl_rows.append(f'{where}	{snippet}')
                continue

            # Compared / map-key literals stay in the pack: translation only touches
            # text drawn by widgets, so the comparison itself is not affected.
            if BEFORE.search(before) or AFTER.search(after):
                review.append(f'{where}\tcompared / matched (kept in pack)\t{snippet}')
            elif MAP_KEY_AFTER.match(after) and MAP_KEY_BEFORE.search(before):
                review.append(f'{where}\tpossible map key (kept in pack)\t{snippet}')

            buf, n_ph, adjacent, prev_e = [], 0, False, False
            for k, s, e in parts:
                if k == 't':
                    t = src[s:e]
                    buf.append(t if raw else unescape(t))
                    if t:
                        prev_e = False
                else:
                    if prev_e:
                        adjacent = True
                    buf.append('{%d}' % n_ph)
                    n_ph += 1
                    prev_e = True
            key = ''.join(buf)

            if n_ph == 0:
                strings[key] = ''
            elif cjk_count(key) < 2:
                review.append(f'{where}\ttemplate with <2 Chinese chars\t{snippet}')
            elif adjacent:
                review.append(f'{where}\tadjacent placeholders\t{snippet}')
            else:
                templates[key] = ''

    en = {'strings': {}, 'templates': {}}
    en_path = os.path.join(OUT, 'en.json')
    if os.path.exists(en_path):
        with open(en_path, encoding='utf-8') as f:
            en.update(json.load(f))
    todo = {
        'strings': {k: '' for k in strings if not en['strings'].get(k)},
        'templates': {k: '' for k in templates if not en['templates'].get(k)},
    }

    os.makedirs(OUT, exist_ok=True)

    def dump(name, obj):
        with open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as f:
            json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')

    dump('source.json', {'strings': strings, 'templates': templates})
    dump('todo.json', todo)
    rows = sorted(set(review))
    with open(os.path.join(OUT, 'review.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(rows) + ('\n' if rows else ''))

    with open(os.path.join(OUT, 'excluded.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(excl_rows) + '\n')

    n_keys = len(strings) + len(templates)
    n_todo = len(todo['strings']) + len(todo['templates'])
    print(f'cjk_literals={total_literals} excluded={excluded} review_skipped={len(rows)} '
          f'keys={n_keys} (strings={len(strings)} templates={len(templates)}) '
          f'translated={n_keys - n_todo} untranslated={n_todo}')
    stale = [('strings', k) for k in en['strings'] if k not in strings]
    stale += [('templates', k) for k in en['templates'] if k not in templates]
    for kind, k in stale:
        print(f'  STALE {kind[:-1]}:', repr(k))
    if '--prune' in sys.argv and stale:
        for kind, k in stale:
            del en[kind][k]
        with open(en_path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(en, f, ensure_ascii=False, indent=1)
            f.write('\n')
        print(f'pruned={len(stale)}')
    for row in unhandled:
        print('  UNHANDLED template:', row)
    for k in todo['strings']:
        print('  UNTRANSLATED string:', repr(k))
    for k in todo['templates']:
        print('  UNTRANSLATED template:', repr(k))
    sys.exit(1 if (n_todo or unhandled) else 0)


if __name__ == '__main__':
    main()
