#!/usr/bin/env python3
"""Static checks that run without a Dart toolchain.

Complements `flutter analyze` rather than replacing it. These are the rules the
analyzer cannot express: the layer boundary from docs/02 §4.1 and the
"no hardcoded colour outside core/theme" rule from docs/04 §12.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def strip_dart(src: str) -> str:
    """Remove comments and string literals, handling Dart interpolation.

    A naive regex gets this wrong: an apostrophe inside a double-quoted string
    ("That's") opens a phantom single-quoted literal and every count after it
    is garbage. This scans character by character instead.
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]

        # line comment
        if src.startswith('//', i):
            i = src.find('\n', i)
            if i < 0:
                break
            continue
        # block comment
        if src.startswith('/*', i):
            end = src.find('*/', i + 2)
            i = n if end < 0 else end + 2
            continue

        # raw string
        if ch == 'r' and i + 1 < n and src[i + 1] in '\'"':
            quote = src[i + 1]
            triple = src.startswith(quote * 3, i + 1)
            term = quote * 3 if triple else quote
            j = src.find(term, i + 1 + len(term))
            i = n if j < 0 else j + len(term)
            continue

        if ch in '\'"':
            quote = ch
            triple = src.startswith(quote * 3, i)
            term = quote * 3 if triple else quote
            i += len(term)
            depth = 0
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                # ${ ... } interpolation: the contents are real code, so its
                # brackets must still be counted.
                if src.startswith('${', i):
                    out.append('${')
                    depth += 1
                    i += 2
                    start = i
                    brace = 1
                    while i < n and brace:
                        if src[i] == '{':
                            brace += 1
                        elif src[i] == '}':
                            brace -= 1
                        i += 1
                    out.append(src[start:i])
                    continue
                if not triple and src[i] == '\n':
                    break
                if src.startswith(term, i):
                    i += len(term)
                    break
                i += 1
            continue

        out.append(ch)
        i += 1
    return ''.join(out)


def main() -> int:
    files = sorted((ROOT / 'lib').rglob('*.dart')) + \
            sorted((ROOT / 'test').rglob('*.dart'))
    errors: list[str] = []

    for f in files:
        rel = f.relative_to(ROOT)
        src = f.read_text()
        code = strip_dart(src)

        # 1. every package import resolves
        for m in re.finditer(r"""(?:import|export)\s+'package:lifedna/([^']+)'""", src):
            if not (ROOT / 'lib' / m.group(1)).exists():
                errors.append(f'{rel}: unresolved import package:lifedna/{m.group(1)}')

        # 2. relative exports resolve (barrel files)
        for m in re.finditer(r"""export\s+'(?!package:)([^']+)'""", src):
            if not (f.parent / m.group(1)).exists():
                errors.append(f'{rel}: unresolved export {m.group(1)}')

        # 3. delimiters balance
        for op, cl, name in (('{', '}', 'brace'), ('(', ')', 'paren'), ('[', ']', 'bracket')):
            if code.count(op) != code.count(cl):
                errors.append(
                    f'{rel}: unbalanced {name} '
                    f'({code.count(op)} vs {code.count(cl)})')

        # 4. colour discipline (docs/04 §12)
        in_theme = 'core/theme' in str(rel)
        is_test = str(rel).startswith('test/')
        if not in_theme and not is_test:
            for m in re.finditer(r'\bColors\.(?!transparent\b)[a-zA-Z]+', code):
                errors.append(f'{rel}: hardcoded {m.group(0)} outside core/theme')
            for m in re.finditer(r'Color\(0x[0-9a-fA-F]{6,8}\)', code):
                errors.append(f'{rel}: hardcoded {m.group(0)} outside core/theme')

        # 5. layer boundary (docs/02 §4.1) — the domain must stay pure Dart
        pure = ('/domain/' in str(rel) or '/engines/' in str(rel)
                or 'shared/value_objects' in str(rel) or 'shared/enums' in str(rel))
        if pure and not is_test:
            for banned in ('package:flutter/', 'package:firebase',
                           'package:cloud_firestore', 'dart:io',
                           'package:flutter_riverpod', 'package:go_router'):
                if f"import '{banned}" in src:
                    errors.append(f'{rel}: LAYER VIOLATION — imports {banned}')

    print(f'checked {len(files)} files')
    if errors:
        print(f'\n{len(errors)} issue(s):')
        for e in errors:
            print('  ' + e)
        return 1
    print('all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
