"""Tiny Dart lexer: yields string-literal content spans (start, end) in a file.

Only the text parts of a literal are yielded; `${...}` and `$name`
interpolations are skipped (their nested literals are yielded on their own).

`literals(src)` returns one record per literal:
(quote_start, end, parts, raw) where parts is a list of ('t', s, e) text
spans and ('e', s, e) interpolation spans, in source order.
"""
import re

CJK = re.compile(r'[㐀-鿿豈-﫿]')


def _lex(src):
    i, n = 0, len(src)
    out = []
    lits = []

    def lex_code(i, stop_brace):
        depth = 0
        while i < n:
            c = src[i]
            if c == '/' and src.startswith('//', i):
                j = src.find('\n', i)
                i = n if j < 0 else j
            elif c == '/' and src.startswith('/*', i):
                d, i = 1, i + 2
                while i < n and d:
                    if src.startswith('/*', i):
                        d, i = d + 1, i + 2
                    elif src.startswith('*/', i):
                        d, i = d - 1, i + 2
                    else:
                        i += 1
            elif c in '\'"':
                raw = i > 0 and src[i - 1] == 'r' and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == '_'))
                i = lex_str(i, raw)
            elif c == '{':
                depth += 1
                i += 1
            elif c == '}':
                if stop_brace and depth == 0:
                    return i + 1
                depth -= 1
                i += 1
            else:
                i += 1
        return i

    def lex_str(i, raw):
        q = src[i]
        triple = src.startswith(q * 3, i)
        delim = q * 3 if triple else q
        i += len(delim)
        seg = i
        qstart = i - len(delim)
        parts = []

        def close(end, stop):
            out.append((seg, stop))
            parts.append(('t', seg, stop))
            lits.append((qstart, end, parts, raw))
            return end

        while i < n:
            if src.startswith(delim, i):
                return close(i + len(delim), i)
            c = src[i]
            if not triple and c == '\n':
                return close(i, i)
            if not raw and c == '\\':
                i += 2
            elif not raw and c == '$' and i + 1 < n and src[i + 1] == '{':
                out.append((seg, i))
                parts.append(('t', seg, i))
                st = i
                i = lex_code(i + 2, True)
                parts.append(('e', st, i))
                seg = i
            elif not raw and c == '$' and i + 1 < n and src[i + 1].isascii() and (src[i + 1].isalpha() or src[i + 1] == '_'):
                out.append((seg, i))
                parts.append(('t', seg, i))
                st = i
                i += 2
                while i < n and src[i].isascii() and (src[i].isalnum() or src[i] == '_'):
                    i += 1
                parts.append(('e', st, i))
                seg = i
            else:
                i += 1
        return close(i, i)

    lex_code(0, False)
    return out, lits


def spans(src):
    return _lex(src)[0]


def literals(src):
    return sorted(_lex(src)[1], key=lambda x: x[0])
